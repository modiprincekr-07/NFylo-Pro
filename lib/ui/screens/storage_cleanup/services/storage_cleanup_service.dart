import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/storage_cleanup_models.dart';
import 'duplicate_finder_service.dart';

class StorageCleanupResult {
  final List<DuplicateGroup> duplicateGroups;
  final List<LargeFileCleanupItem> largeFiles;
  final List<OldFileCleanupItem> oldFiles;

  const StorageCleanupResult({
    required this.duplicateGroups,
    required this.largeFiles,
    required this.oldFiles,
  });

  int get totalDuplicatesWastedBytes {
    int total = 0;
    for (final g in duplicateGroups) {
      total += g.totalWastedBytes;
    }
    return total;
  }

  int get totalLargeFilesBytes {
    int total = 0;
    for (final f in largeFiles) {
      total += f.size;
    }
    return total;
  }

  int get totalOldFilesBytes {
    int total = 0;
    for (final f in oldFiles) {
      total += f.size;
    }
    return total;
  }

  int get totalPotentialCleanupBytes =>
      totalDuplicatesWastedBytes + totalLargeFilesBytes + totalOldFilesBytes;
}

class StorageCleanupService {
  static const int largeFileThreshold = 25 * 1024 * 1024; // 25 MB
  static const int oldFileDaysThreshold = 90; // 3 months

  /// Performs full cleanup scan for Duplicates, Large Files, and Old Files.
  static Future<StorageCleanupResult> performFullScan({
    String rootPath = '/storage/emulated/0',
    void Function(CleanupScanProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      return const StorageCleanupResult(
        duplicateGroups: [],
        largeFiles: [],
        oldFiles: [],
      );
    }

    final List<LargeFileCleanupItem> largeFiles = [];
    final List<OldFileCleanupItem> oldFiles = [];
    final now = DateTime.now();

    // 1. Scan for Large and Old files first
    onProgress?.call(
      const CleanupScanProgress(
        phase: 'Scanning for heavy & old files...',
        currentItem: 'Analyzing directory tree...',
        progress: 0.05,
        scannedCount: 0,
      ),
    );

    try {
      final stream = rootDir.list(recursive: true, followLinks: false);
      int scannedCount = 0;
      DateTime lastYield = DateTime.now();

      await for (final entity in stream.handleError((_) {})) {
        if (isCancelled?.call() == true) {
          return const StorageCleanupResult(
            duplicateGroups: [],
            largeFiles: [],
            oldFiles: [],
          );
        }

        if (entity is File) {
          scannedCount++;
          final filePath = entity.path;
          final fileName = p.basename(filePath);

          if (!fileName.startsWith('.') && !filePath.contains('/.')) {
            try {
              final stat = entity.statSync();
              final size = stat.size;
              final modified = stat.modified;
              final ext = p.extension(filePath).toLowerCase();
              final parentPath = p.dirname(filePath);

              // Large file detection
              if (size >= largeFileThreshold) {
                largeFiles.add(
                  LargeFileCleanupItem(
                    path: filePath,
                    name: fileName,
                    size: size,
                    modified: modified,
                    extension: ext,
                    parentPath: parentPath,
                    isSelected: false,
                  ),
                );
              }

              // Old file detection (> 90 days and > 1MB)
              final ageDays = now.difference(modified).inDays;
              if (ageDays >= oldFileDaysThreshold && size > 1024 * 1024) {
                oldFiles.add(
                  OldFileCleanupItem(
                    path: filePath,
                    name: fileName,
                    size: size,
                    modified: modified,
                    ageDays: ageDays,
                    extension: ext,
                    parentPath: parentPath,
                    isSelected: false,
                  ),
                );
              }
            } catch (_) {}
          }

          final current = DateTime.now();
          if (current.difference(lastYield).inMilliseconds > 90) {
            lastYield = current;
            onProgress?.call(
              CleanupScanProgress(
                phase: 'Scanning for heavy & old files...',
                currentItem: fileName,
                progress: 0.15,
                scannedCount: scannedCount,
              ),
            );
            await Future.delayed(Duration.zero);
          }
        }
      }
    } catch (_) {}

    // Sort large files descending by size
    largeFiles.sort((a, b) => b.size.compareTo(a.size));

    // Sort old files ascending by modified (oldest first)
    oldFiles.sort((a, b) => a.modified.compareTo(b.modified));

    // 2. Scan for duplicates using DuplicateFinderService
    final duplicateGroups = await DuplicateFinderService.findDuplicates(
      rootPath: rootPath,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    return StorageCleanupResult(
      duplicateGroups: duplicateGroups,
      largeFiles: largeFiles,
      oldFiles: oldFiles,
    );
  }

  /// Safely deletes files from disk and returns the number of successfully deleted files.
  static Future<int> deleteFiles(List<String> paths) async {
    int deletedCount = 0;
    for (final path in paths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
          deletedCount++;
        }
      } catch (e) {
        debugPrint('Error deleting $path: $e');
      }
    }
    return deletedCount;
  }
}
