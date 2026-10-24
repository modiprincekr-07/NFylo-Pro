import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../core/utils.dart';
import '../../../services/app_manager_service.dart';
import '../../../services/folder_share_service.dart';
import '../../widgets/file_action_dialogs.dart';
import '../media_category_screen.dart';
import 'app_manager_screen.dart';
import 'models/storage_analysis_models.dart';
import 'widgets/category_segmented_bar.dart';
import 'widgets/largest_files_list.dart';
import 'widgets/storage_treemap_widget.dart';
import 'widgets/wavy_category_list.dart';

class StorageAnalyzerScreen extends StatefulWidget {
  final String? initialVolumePath;
  const StorageAnalyzerScreen({super.key, this.initialVolumePath});

  @override
  State<StorageAnalyzerScreen> createState() => _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState extends State<StorageAnalyzerScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = true;
  String _currentScanningItem = 'Initializing...';
  int _scannedFilesCount = 0;

  int _totalStorageSize = 0;
  int _totalUsedSize = 0;
  int _totalScannedBytes = 0;
  int _appsSize = 0;

  late AnimationController _radialController;

  // 9 Categories matching Fylo specifications
  late List<StorageCategoryInfo> _categories;
  List<FolderSpaceTile> _folderTiles = [];
  List<LargestFileItem> _largestFiles = [];

  @override
  void initState() {
    super.initState();
    _radialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _initCategories();
    _startStorageScan();
  }

  @override
  void dispose() {
    _radialController.dispose();
    super.dispose();
  }

  void _initCategories() {
    _categories = [
      StorageCategoryInfo(
        id: 'audio',
        name: 'Audio',
        color: const Color(0xFFF97316), // Orange
        icon: Broken.music,
        mediaType: MediaType.audios,
        extensions: ['.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus', '.amr', '.wma'],
      ),
      StorageCategoryInfo(
        id: 'videos',
        name: 'Videos',
        color: const Color(0xFFEF4444), // Red
        icon: Broken.video,
        mediaType: MediaType.videos,
        extensions: ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.3gp'],
      ),
      StorageCategoryInfo(
        id: 'apks',
        name: 'APKs',
        color: const Color(0xFF10B981), // Green
        icon: Broken.box,
        mediaType: MediaType.apks,
        extensions: ['.apk', '.xapk', '.apks'],
      ),
      StorageCategoryInfo(
        id: 'images',
        name: 'Images',
        color: const Color(0xFF8B5CF6), // Purple
        icon: Broken.image,
        mediaType: MediaType.images,
        extensions: ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.avif', '.svg'],
      ),
      StorageCategoryInfo(
        id: 'pdfs',
        name: 'PDFs',
        color: const Color(0xFFEC4899), // Pink
        icon: Broken.document,
        mediaType: MediaType.documents,
        extensions: ['.pdf'],
      ),
      StorageCategoryInfo(
        id: 'archives',
        name: 'Archives',
        color: const Color(0xFFF59E0B), // Amber
        icon: Broken.archive,
        mediaType: MediaType.archives,
        extensions: ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.iso'],
      ),
      StorageCategoryInfo(
        id: 'code',
        name: 'Code',
        color: const Color(0xFF06B6D4), // Cyan
        icon: Broken.code,
        mediaType: MediaType.documents,
        extensions: [
          '.dart', '.py', '.js', '.ts', '.html', '.css', '.java', '.kt',
          '.c', '.cpp', '.h', '.json', '.xml', '.yaml', '.yml', '.sh', '.sql'
        ],
      ),
      StorageCategoryInfo(
        id: 'text',
        name: 'Text',
        color: const Color(0xFF6366F1), // Indigo
        icon: Broken.document_text,
        mediaType: MediaType.documents,
        extensions: ['.txt', '.md', '.log', '.csv', '.tsv', '.rtf', '.ini', '.conf'],
      ),
      StorageCategoryInfo(
        id: 'files',
        name: 'Files',
        color: const Color(0xFF64748B), // Slate
        icon: Broken.folder_2,
        mediaType: MediaType.documents,
        extensions: [], // Fallback for other file types
      ),
    ];
  }

  StorageCategoryInfo _getCategoryForExtension(String ext) {
    for (final cat in _categories) {
      if (cat.extensions.contains(ext)) {
        return cat;
      }
    }
    // Fallback to Files
    return _categories.firstWhere(
      (c) => c.id == 'files',
      orElse: () => _categories.last,
    );
  }

  Future<void> _startStorageScan() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _currentScanningItem = 'Reading system memory...';
      _scannedFilesCount = 0;
      _initCategories();
      _folderTiles = [];
      _largestFiles = [];
      _totalScannedBytes = 0;
    });

    final provider = context.read<FileManagerProvider>();
    final targetPath = widget.initialVolumePath ?? '/storage/emulated/0';

    // 1. Fetch total & used storage via provider
    _totalStorageSize = provider.totalStorageBytes > 0
        ? provider.totalStorageBytes
        : 128 * 1024 * 1024 * 1024;
    _totalUsedSize = provider.usedStorageBytes > 0
        ? provider.usedStorageBytes
        : 84 * 1024 * 1024 * 1024;

    // 2. Fetch app sizes from App Manager Service (if root scanning)
    if (widget.initialVolumePath == null || widget.initialVolumePath == '/storage/emulated/0') {
      setState(() {
        _currentScanningItem = 'Calculating Apps capacity...';
      });
      try {
        final userApps = await AppManagerService.getInstalledApps(includeSystem: false);
        final systemApps = await AppManagerService.getInstalledApps(includeSystem: true);
        int appsSum = 0;
        for (final app in userApps) {
          appsSum += app.apkSize;
        }
        for (final app in systemApps) {
          if (app.isSystem) {
            appsSum += app.apkSize;
          }
        }
        _appsSize = appsSum;
      } catch (_) {
        _appsSize = 0;
      }
    } else {
      _appsSize = 0;
    }

    // 3. Scan directories recursively
    try {
      final rootDir = Directory(targetPath);
      if (rootDir.existsSync()) {
        // Collect top-level directories for proportional Treemap Space Map
        final topFolderSizes = <String, int>{};
        try {
          final topEntities = rootDir.listSync(followLinks: false);
          for (final entity in topEntities) {
            if (entity is Directory) {
              topFolderSizes[entity.path] = 0;
            }
          }
        } catch (_) {}

        final List<LargestFileItem> candidates = [];
        final stream = rootDir.list(recursive: true, followLinks: false);
        DateTime lastUiUpdate = DateTime.now();

        await for (final entity in stream.handleError((_) {})) {
          if (entity is File) {
            _scannedFilesCount++;
            final filePath = entity.path;
            final fileName = p.basename(filePath);

            // Throttle UI update to avoid jank
            final now = DateTime.now();
            if (now.difference(lastUiUpdate).inMilliseconds > 90) {
              lastUiUpdate = now;
              if (mounted) {
                setState(() {
                  _currentScanningItem = fileName;
                });
              }
            }

            try {
              final size = entity.lengthSync();
              final ext = p.extension(filePath).toLowerCase();
              final cat = _getCategoryForExtension(ext);

              cat.size += size;
              cat.count++;
              _totalScannedBytes += size;

              // Attribute size to top-level folder
              for (final folderPath in topFolderSizes.keys) {
                if (filePath.startsWith(folderPath)) {
                  topFolderSizes[folderPath] = (topFolderSizes[folderPath] ?? 0) + size;
                  break;
                }
              }

              // Collect large files (> 5MB or maintain top list)
              if (size > 5 * 1024 * 1024 || candidates.length < 30) {
                try {
                  final modified = entity.lastModifiedSync();
                  candidates.add(
                    LargestFileItem(
                      path: filePath,
                      name: fileName,
                      size: size,
                      modified: modified,
                      extension: ext,
                      color: cat.color,
                      icon: cat.icon,
                    ),
                  );

                  // Keep candidates trimmed to top 30
                  if (candidates.length > 50) {
                    candidates.sort((a, b) => b.size.compareTo(a.size));
                    candidates.removeRange(30, candidates.length);
                  }
                } catch (_) {}
              }
            } catch (_) {}
          }
        }

        // Sort candidates
        candidates.sort((a, b) => b.size.compareTo(a.size));
        _largestFiles = candidates.take(30).toList();

        // Build folder space tiles for Treemap Space Map
        final List<FolderSpaceTile> tiles = [];
        int totalFoldersSize = 0;
        topFolderSizes.forEach((_, s) => totalFoldersSize += s);

        topFolderSizes.forEach((folderPath, size) {
          if (size > 0) {
            final folderName = p.basename(folderPath);
            final style = _getFolderStyle(folderName);
            final double proportion =
                totalFoldersSize > 0 ? (size / totalFoldersSize) : 0.0;

            tiles.add(
              FolderSpaceTile(
                name: folderName,
                path: folderPath,
                size: size,
                color: style.color,
                icon: style.icon,
                proportion: proportion,
              ),
            );
          }
        });

        tiles.sort((a, b) => b.size.compareTo(a.size));
        _folderTiles = tiles;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
      _radialController.forward(from: 0.0);
    }
  }

  _FolderStyle _getFolderStyle(String name) {
    final lower = name.toLowerCase();
    if (lower == 'dcim' || lower.contains('camera')) {
      return _FolderStyle(const Color(0xFF8B5CF6), Broken.camera);
    } else if (lower == 'download' || lower == 'downloads') {
      return _FolderStyle(const Color(0xFF3B82F6), Broken.document_download);
    } else if (lower == 'pictures' || lower == 'photos') {
      return _FolderStyle(const Color(0xFFEC4899), Broken.gallery);
    } else if (lower == 'movies' || lower == 'videos') {
      return _FolderStyle(const Color(0xFFEF4444), Broken.video);
    } else if (lower == 'music' || lower == 'audio') {
      return _FolderStyle(const Color(0xFFF97316), Broken.music);
    } else if (lower == 'documents' || lower == 'docs') {
      return _FolderStyle(const Color(0xFF06B6D4), Broken.document);
    } else if (lower == 'android') {
      return _FolderStyle(const Color(0xFF10B981), Broken.mobile);
    } else if (lower.contains('telegram')) {
      return _FolderStyle(const Color(0xFF0EA5E9), Broken.message);
    } else if (lower.contains('whatsapp')) {
      return _FolderStyle(const Color(0xFF22C55E), Broken.call);
    }
    return _FolderStyle(const Color(0xFF64748B), Broken.folder_2);
  }

  Future<void> _openFile(LargestFileItem item) async {
    try {
      final provider = context.read<FileManagerProvider>();
      await provider.openFile(context, item.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(LargestFileItem item) async {
    await FolderShareService.sharePaths(context, [item.path]);
  }

  Future<void> _batchShareFiles(List<LargestFileItem> items) async {
    if (items.isEmpty) return;
    await FolderShareService.sharePaths(
      context,
      items.map((e) => e.path).toList(),
    );
  }

  Future<void> _deleteFile(LargestFileItem item) async {
    final confirm = await FileActionDialogs.showConfirmDialog(
      context,
      title: 'Delete File',
      content: 'Are you sure you want to delete "${item.name}"? This action cannot be undone.',
    );

    if (confirm && mounted) {
      try {
        final f = File(item.path);
        if (f.existsSync()) {
          f.deleteSync();
        }
        setState(() {
          _largestFiles.removeWhere((e) => e.path == item.path);
          final cat = _getCategoryForExtension(item.extension);
          cat.size = max(0, cat.size - item.size);
          cat.count = max(0, cat.count - 1);
          _totalScannedBytes = max(0, _totalScannedBytes - item.size);
        });
        context.read<FileManagerProvider>().updateStorageSpace();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${item.name}"')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete file: $e')),
          );
        }
      }
    }
  }

  Future<void> _batchDeleteFiles(List<LargestFileItem> items) async {
    if (items.isEmpty) return;
    final confirm = await FileActionDialogs.showConfirmDialog(
      context,
      title: 'Delete ${items.length} Files',
      content: 'Are you sure you want to delete these ${items.length} files? This action cannot be undone.',
    );

    if (confirm && mounted) {
      int deletedCount = 0;
      final deletedPaths = <String>{};

      for (final item in items) {
        try {
          final f = File(item.path);
          if (f.existsSync()) {
            f.deleteSync();
            deletedCount++;
            deletedPaths.add(item.path);
            final cat = _getCategoryForExtension(item.extension);
            cat.size = max(0, cat.size - item.size);
            cat.count = max(0, cat.count - 1);
            _totalScannedBytes = max(0, _totalScannedBytes - item.size);
          }
        } catch (_) {}
      }

      setState(() {
        _largestFiles.removeWhere((e) => deletedPaths.contains(e.path));
      });
      context.read<FileManagerProvider>().updateStorageSpace();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully deleted $deletedCount files')),
      );
    }
  }

  void _onCategoryTap(StorageCategoryInfo cat) {
    if (cat.id == 'apps') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppManagerScreen()),
      );
    } else if (cat.mediaType != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaCategoryScreen(mediaType: cat.mediaType!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isScoped = widget.initialVolumePath != null &&
        widget.initialVolumePath != '/storage/emulated/0';
    final title = isScoped
        ? '${p.basename(widget.initialVolumePath!)} Analytics'
        : 'Storage Analytics';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Broken.arrow_left),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _startStorageScan,
            tooltip: 'Rescan Storage',
          ),
        ],
      ),
      body: _isScanning
          ? _buildScanningView(theme, isDark)
          : _buildAnalyticsDashboard(theme, isDark),
    );
  }

  Widget _buildScanningView(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    strokeWidth: 4.5,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
                Container(
                  width: 95,
                  height: 95,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Broken.document_filter,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Analyzing Device Storage',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Computing category distribution, building visual Space Map, and identifying largest files...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _currentScanningItem,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (_scannedFilesCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$_scannedFilesCount files scanned',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsDashboard(ThemeData theme, bool isDark) {
    final int freeSize = max(0, _totalStorageSize - _totalUsedSize);
    final double usedPercent = _totalStorageSize > 0
        ? (_totalUsedSize / _totalStorageSize) * 100
        : 0.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overall Storage Summary Header Card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Radial ring painter
                AnimatedBuilder(
                  animation: _radialController,
                  builder: (context, child) {
                    return SizedBox(
                      width: 100,
                      height: 100,
                      child: CustomPaint(
                        painter: StorageSummaryRingPainter(
                          usedBytes: _totalUsedSize,
                          totalBytes: _totalStorageSize,
                          animationVal: _radialController.value,
                          isDark: isDark,
                          primaryColor: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Internal Space',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        FileUtils.formatBytes(_totalStorageSize, 1),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '${FileUtils.formatBytes(freeSize, 1)} Free',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '${FileUtils.formatBytes(_totalUsedSize, 1)} Used (${usedPercent.toStringAsFixed(1)}%)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Component 1: Category Segmented Breakdown Bar
          CategorySegmentedBar(
            categories: _categories,
            totalStorage: _totalStorageSize,
            usedStorage: _totalScannedBytes,
            animationValue: _radialController.value,
            onCategoryTap: _onCategoryTap,
          ),

          // 3. Component 2: Interactive "Space Map" (Treemap Grid)
          if (_folderTiles.isNotEmpty)
            StorageTreemapWidget(
              folderTiles: _folderTiles,
            ),

          // 4. Component 3: Wavy/Animated Progress Category List
          WavyCategoryList(
            categories: _categories,
            totalStorage: _totalStorageSize,
            usedStorage: _totalScannedBytes,
            onCategoryTap: _onCategoryTap,
          ),

          // 5. Component 4: Largest Files Quick-Action List
          LargestFilesList(
            files: _largestFiles,
            onOpenFile: _openFile,
            onShareFile: _shareFile,
            onDeleteFile: _deleteFile,
            onBatchShare: _batchShareFiles,
            onBatchDelete: _batchDeleteFiles,
          ),

          const SizedBox(height: 36),
        ],
      ),
    );
  }
}

class _FolderStyle {
  final Color color;
  final IconData icon;
  const _FolderStyle(this.color, this.icon);
}

class StorageSummaryRingPainter extends CustomPainter {
  final int usedBytes;
  final int totalBytes;
  final double animationVal;
  final bool isDark;
  final Color primaryColor;

  StorageSummaryRingPainter({
    required this.usedBytes,
    required this.totalBytes,
    required this.animationVal,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final double radius = min(size.width, size.height) / 2 - 8;
    final Rect rect = Rect.fromCircle(center: Offset(center, center), radius: radius);

    final Paint trackPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    canvas.drawCircle(Offset(center, center), radius, trackPaint);

    if (totalBytes <= 0) return;

    final double ratio = (usedBytes / totalBytes).clamp(0.0, 1.0);
    final double sweepAngle = ratio * 2 * pi * animationVal;

    final Paint usedPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [
          primaryColor,
          const Color(0xFFEF4444),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -pi / 2, sweepAngle, false, usedPaint);
  }

  @override
  bool shouldRepaint(covariant StorageSummaryRingPainter oldDelegate) {
    return oldDelegate.animationVal != animationVal;
  }
}
