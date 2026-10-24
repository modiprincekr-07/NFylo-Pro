import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/storage_cleanup_models.dart';

class DuplicateFinderService {
  static const List<String> _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.bmp'
  ];

  /// Scans [rootPath] recursively and detects exact duplicate files and similar images.
  /// Yields execution cooperatively so the UI never stutters.
  static Future<List<DuplicateGroup>> findDuplicates({
    String rootPath = '/storage/emulated/0',
    void Function(CleanupScanProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) return [];

    final Map<int, List<File>> sizeMap = {};
    final List<File> imageCandidates = [];
    int totalScanned = 0;

    // -------------------------------------------------------------
    // PHASE 1: Quick Directory Traversal & Exact File Size Indexing
    // -------------------------------------------------------------
    onProgress?.call(
      const CleanupScanProgress(
        phase: 'Indexing files by size...',
        currentItem: 'Scanning storage...',
        progress: 0.1,
        scannedCount: 0,
      ),
    );

    try {
      final stream = rootDir.list(recursive: true, followLinks: false);
      DateTime lastYield = DateTime.now();

      await for (final entity in stream.handleError((_) {})) {
        if (isCancelled?.call() == true) return [];

        if (entity is File) {
          totalScanned++;
          final filePath = entity.path;
          final fileName = p.basename(filePath);

          // Skip hidden dotfiles, cache directories, or 0-byte empty files
          if (fileName.startsWith('.') || filePath.contains('/.') || filePath.contains('/cache/')) {
            continue;
          }

          try {
            final size = entity.lengthSync();
            if (size > 1024) {
              // Only consider files > 1KB
              sizeMap.putIfAbsent(size, () => []).add(entity);

              final ext = p.extension(filePath).toLowerCase();
              if (_imageExtensions.contains(ext)) {
                imageCandidates.add(entity);
              }
            }
          } catch (_) {}

          final now = DateTime.now();
          if (now.difference(lastYield).inMilliseconds > 80) {
            lastYield = now;
            onProgress?.call(
              CleanupScanProgress(
                phase: 'Indexing files by size...',
                currentItem: fileName,
                progress: 0.25,
                scannedCount: totalScanned,
              ),
            );
            await Future.delayed(Duration.zero);
          }
        }
      }
    } catch (_) {}

    if (isCancelled?.call() == true) return [];

    // Filter out unique file sizes (they CANNOT be duplicates)
    final candidateSizes = sizeMap.entries.where((e) => e.value.length > 1).toList();
    int totalCandidateFiles = 0;
    for (final e in candidateSizes) {
      totalCandidateFiles += e.value.length;
    }

    if (candidateSizes.isEmpty) {
      return [];
    }

    // -------------------------------------------------------------
    // PHASE 2: Fast 4KB Prefix Header Hash
    // -------------------------------------------------------------
    onProgress?.call(
      CleanupScanProgress(
        phase: 'Analyzing header signatures...',
        currentItem: 'Filtering non-duplicates...',
        progress: 0.45,
        scannedCount: totalScanned,
      ),
    );

    final Map<String, List<File>> headerCollisionMap = {};
    int processedHeaders = 0;
    DateTime lastHeaderYield = DateTime.now();

    for (final entry in candidateSizes) {
      if (isCancelled?.call() == true) return [];

      final size = entry.key;
      for (final file in entry.value) {
        processedHeaders++;
        final headerHash = await _readHeaderHash(file);
        if (headerHash != null) {
          final key = '$size-$headerHash';
          headerCollisionMap.putIfAbsent(key, () => []).add(file);
        }

        final now = DateTime.now();
        if (now.difference(lastHeaderYield).inMilliseconds > 90) {
          lastHeaderYield = now;
          final double pRatio = 0.45 + (0.25 * (processedHeaders / totalCandidateFiles));
          onProgress?.call(
            CleanupScanProgress(
              phase: 'Analyzing file headers...',
              currentItem: p.basename(file.path),
              progress: pRatio,
              scannedCount: totalScanned,
            ),
          );
          await Future.delayed(Duration.zero);
        }
      }
    }

    if (isCancelled?.call() == true) return [];

    // Filter out groups with unique header hashes
    final headerCandidates = headerCollisionMap.values.where((list) => list.length > 1).toList();

    // -------------------------------------------------------------
    // PHASE 3: Full File MD5 Hash Calculation
    // -------------------------------------------------------------
    onProgress?.call(
      CleanupScanProgress(
        phase: 'Verifying exact byte matches...',
        currentItem: 'Calculating cryptographic hashes...',
        progress: 0.70,
        scannedCount: totalScanned,
      ),
    );

    final Map<String, List<File>> exactDuplicateMap = {};
    final Set<String> matchedExactFilePaths = {};
    int totalFullFiles = 0;
    for (final list in headerCandidates) {
      totalFullFiles += list.length;
    }

    int processedFullFiles = 0;
    DateTime lastFullYield = DateTime.now();

    for (final list in headerCandidates) {
      if (isCancelled?.call() == true) return [];

      for (final file in list) {
        processedFullFiles++;
        final fullMd5 = await _calculateFullMd5(file);
        if (fullMd5 != null) {
          exactDuplicateMap.putIfAbsent(fullMd5, () => []).add(file);
          matchedExactFilePaths.add(file.path);
        }

        final now = DateTime.now();
        if (now.difference(lastFullYield).inMilliseconds > 90) {
          lastFullYield = now;
          final double pRatio = 0.70 + (0.20 * (processedFullFiles / (totalFullFiles > 0 ? totalFullFiles : 1)));
          onProgress?.call(
            CleanupScanProgress(
              phase: 'Hashing duplicate candidates...',
              currentItem: p.basename(file.path),
              progress: pRatio,
              scannedCount: totalScanned,
            ),
          );
          await Future.delayed(Duration.zero);
        }
      }
    }

    if (isCancelled?.call() == true) return [];

    final List<DuplicateGroup> duplicateGroups = [];
    int groupIndex = 1;

    exactDuplicateMap.forEach((hash, files) {
      if (files.length > 1) {
        final items = _createDuplicateItems(files);
        duplicateGroups.add(
          DuplicateGroup(
            groupId: 'exact_${groupIndex++}',
            fileName: items.first.name,
            fileSize: items.first.size,
            files: items,
            hash: hash,
            isSimilarImage: false,
          ),
        );
      }
    });

    // -------------------------------------------------------------
    // PHASE 4: Visual Perceptual Image Similarity (Similar Photos)
    // -------------------------------------------------------------
    onProgress?.call(
      CleanupScanProgress(
        phase: 'Scanning for similar photos...',
        currentItem: 'Comparing visual samples...',
        progress: 0.90,
        scannedCount: totalScanned,
        duplicatesFound: duplicateGroups.length,
      ),
    );

    // Filter images that are not already captured in exact duplicates
    final remainingImages = imageCandidates
        .where((f) => !matchedExactFilePaths.contains(f.path))
        .take(150) // Cap to top candidates to keep it lightweight
        .toList();

    if (remainingImages.length > 1) {
      final Map<String, List<File>> perceptualMap = {};
      for (final img in remainingImages) {
        if (isCancelled?.call() == true) return duplicateGroups;
        final pHash = await _calculateImagePerceptualHash(img);
        if (pHash != null) {
          perceptualMap.putIfAbsent(pHash, () => []).add(img);
        }
        await Future.delayed(Duration.zero);
      }

      perceptualMap.forEach((pHash, files) {
        if (files.length > 1) {
          final items = _createDuplicateItems(files);
          duplicateGroups.add(
            DuplicateGroup(
              groupId: 'similar_${groupIndex++}',
              fileName: items.first.name,
              fileSize: items.first.size,
              files: items,
              hash: pHash,
              isSimilarImage: true,
            ),
          );
        }
      });
    }

    // Sort groups so largest wasted space comes first
    duplicateGroups.sort((a, b) => b.totalWastedBytes.compareTo(a.totalWastedBytes));

    onProgress?.call(
      CleanupScanProgress(
        phase: 'Complete',
        currentItem: 'Done',
        progress: 1.0,
        scannedCount: totalScanned,
        duplicatesFound: duplicateGroups.length,
      ),
    );

    return duplicateGroups;
  }

  /// Converts files to [DuplicateFileItem] with oldest file marked as original
  /// and all subsequent copies marked for auto-selection.
  static List<DuplicateFileItem> _createDuplicateItems(List<File> files) {
    final items = files.map((f) => DuplicateFileItem.fromFile(f)).toList();
    // Sort oldest first (original is oldest)
    items.sort((a, b) => a.modified.compareTo(b.modified));

    if (items.isNotEmpty) {
      items[0].isOriginal = true;
      items[0].isSelected = false; // Never select original by default

      for (int i = 1; i < items.length; i++) {
        items[i].isOriginal = false;
        items[i].isSelected = true; // Auto-select duplicate copies
      }
    }
    return items;
  }

  /// Reads first 4096 bytes and calculates MD5
  static Future<String?> _readHeaderHash(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final bytes = await raf.read(4096);
        if (bytes.isEmpty) return null;
        return md5.convert(bytes).toString();
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Calculates full MD5 hash of a file
  static Future<String?> _calculateFullMd5(File file) async {
    try {
      final stream = file.openRead();
      final digest = await md5.bind(stream).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  /// Computes a lightweight block-sampling perceptual hash for images.
  /// Samples 32 evenly distributed byte blocks across the body.
  static Future<String?> _calculateImagePerceptualHash(File file) async {
    try {
      final length = await file.length();
      if (length < 2048) return null;

      final raf = await file.open(mode: FileMode.read);
      try {
        const sampleCount = 24;
        const blockSize = 32;
        final step = (length - 512) ~/ (sampleCount + 1);
        if (step <= 0) return null;

        final sampleHex = StringBuffer();
        for (int i = 1; i <= sampleCount; i++) {
          await raf.setPosition(256 + i * step);
          final chunk = await raf.read(blockSize);
          if (chunk.isNotEmpty) {
            int sum = 0;
            for (final b in chunk) {
              sum += b;
            }
            final quantized = (sum ~/ chunk.length) >> 4; // 0-15
            sampleHex.write(quantized.toRadixString(16));
          }
        }
        return sampleHex.toString();
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}
