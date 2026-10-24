import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../widgets/file_action_dialogs.dart';
import 'models/storage_cleanup_models.dart';
import 'services/storage_cleanup_service.dart';
import 'widgets/cleanup_overview_card.dart';
import 'widgets/duplicate_group_card.dart';
import 'widgets/large_files_cleanup_tab.dart';
import 'widgets/old_files_cleanup_tab.dart';

class StorageCleanupScreen extends StatefulWidget {
  final String? initialPath;
  const StorageCleanupScreen({super.key, this.initialPath});

  @override
  State<StorageCleanupScreen> createState() => _StorageCleanupScreenState();
}

class _StorageCleanupScreenState extends State<StorageCleanupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isScanning = true;
  bool _isCancelled = false;
  CleanupScanProgress _progress = const CleanupScanProgress(
    phase: 'Initializing...',
    currentItem: 'Starting cleanup scan...',
    progress: 0.0,
    scannedCount: 0,
  );

  StorageCleanupResult _result = const StorageCleanupResult(
    duplicateGroups: [],
    largeFiles: [],
    oldFiles: [],
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _startScan();
  }

  @override
  void dispose() {
    _isCancelled = true;
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _isCancelled = false;
      _progress = const CleanupScanProgress(
        phase: 'Scanning storage...',
        currentItem: 'Reading directories...',
        progress: 0.05,
        scannedCount: 0,
      );
    });

    final targetPath = widget.initialPath ?? '/storage/emulated/0';
    final result = await StorageCleanupService.performFullScan(
      rootPath: targetPath,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
      isCancelled: () => _isCancelled,
    );

    if (mounted && !_isCancelled) {
      setState(() {
        _result = result;
        _isScanning = false;
      });
    }
  }

  // Calculate selected files across all categories
  List<String> get _selectedPaths {
    final paths = <String>[];
    // Duplicates
    for (final group in _result.duplicateGroups) {
      for (final f in group.files) {
        if (f.isSelected) paths.add(f.path);
      }
    }
    // Large Files
    for (final f in _result.largeFiles) {
      if (f.isSelected) paths.add(f.path);
    }
    // Old Files
    for (final f in _result.oldFiles) {
      if (f.isSelected) paths.add(f.path);
    }
    return paths;
  }

  int get _selectedBytes {
    int bytes = 0;
    for (final group in _result.duplicateGroups) {
      for (final f in group.files) {
        if (f.isSelected) bytes += f.size;
      }
    }
    for (final f in _result.largeFiles) {
      if (f.isSelected) bytes += f.size;
    }
    for (final f in _result.oldFiles) {
      if (f.isSelected) bytes += f.size;
    }
    return bytes;
  }

  Future<void> _openFile(String path) async {
    try {
      final provider = context.read<FileManagerProvider>();
      await provider.openFile(context, path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  Future<void> _cleanSelectedFiles() async {
    final paths = _selectedPaths;
    if (paths.isEmpty) return;

    final bytesFormatted = FileUtils.formatBytes(_selectedBytes, 1);
    final confirm = await FileActionDialogs.showConfirmDialog(
      context,
      title: 'Clean Up ${paths.length} Files',
      content:
          'Are you sure you want to permanently delete these ${paths.length} files ($bytesFormatted)? This action cannot be undone.',
    );

    if (confirm && mounted) {
      final deleted = await StorageCleanupService.deleteFiles(paths);
      final deletedSet = paths.toSet();

      setState(() {
        // Remove from duplicate groups
        for (final group in _result.duplicateGroups) {
          group.files.removeWhere((f) => deletedSet.contains(f.path));
        }
        _result.duplicateGroups.removeWhere((g) => g.files.length < 2);

        // Remove from large files
        _result.largeFiles.removeWhere((f) => deletedSet.contains(f.path));

        // Remove from old files
        _result.oldFiles.removeWhere((f) => deletedSet.contains(f.path));
      });

      if (mounted) {
        context.read<FileManagerProvider>().updateStorageSpace();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully removed $deleted files ($bytesFormatted freed)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedCount = _selectedPaths.length;

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
          'Storage Cleanup',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _startScan,
            tooltip: 'Rescan',
          ),
        ],
      ),
      body: _isScanning
          ? _buildScanningView(theme)
          : _buildCleanupDashboard(theme, isDark),
      bottomNavigationBar: (!_isScanning && selectedCount > 0)
          ? _buildBottomCleanBar(theme)
          : null,
    );
  }

  Widget _buildScanningView(ThemeData theme) {
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
                    value: _progress.progress > 0 ? _progress.progress : null,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
                Container(
                  width: 95,
                  height: 95,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Broken.brush_2,
                    size: 42,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              _progress.phase,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Running multi-pass duplicate finder and locating heavy/stale files...',
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
                      _progress.currentItem,
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
            const SizedBox(height: 14),
            Text(
              '${_progress.scannedCount} files indexed • ${(_progress.progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanupDashboard(ThemeData theme, bool isDark) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: CleanupOverviewCard(
              result: _result,
              selectedCategoryIndex: _tabController.index,
              onSelectCategory: (idx) {
                _tabController.animateTo(idx);
              },
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                indicatorColor: theme.colorScheme.primary,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    text: 'Duplicates (${_result.duplicateGroups.length})',
                  ),
                  Tab(
                    text: 'Large Files (${_result.largeFiles.length})',
                  ),
                  Tab(
                    text: 'Old Files (${_result.oldFiles.length})',
                  ),
                ],
              ),
              theme.colorScheme.surface,
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 0: Duplicates
          _buildDuplicatesTab(theme),
          // Tab 1: Large Files
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: LargeFilesCleanupTab(
              largeFiles: _result.largeFiles,
              onSelectionChanged: () => setState(() {}),
              onOpenFile: (f) => _openFile(f.path),
            ),
          ),
          // Tab 2: Old Files
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: OldFilesCleanupTab(
              oldFiles: _result.oldFiles,
              onSelectionChanged: () => setState(() {}),
              onOpenFile: (f) => _openFile(f.path),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicatesTab(ThemeData theme) {
    if (_result.duplicateGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Broken.tick_circle,
                size: 54,
                color: const Color(0xFF10B981).withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No Duplicate Files Found',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Your device storage is clean and deduplicated.',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _result.duplicateGroups.length,
      itemBuilder: (context, index) {
        final group = _result.duplicateGroups[index];
        return DuplicateGroupCard(
          group: group,
          onSelectionChanged: () => setState(() {}),
          onOpenFile: (item) => _openFile(item.path),
        );
      },
    );
  }

  Widget _buildBottomCleanBar(ThemeData theme) {
    final count = _selectedPaths.length;
    final bytesFormatted = FileUtils.formatBytes(_selectedBytes, 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.08))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count files selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reclaims $bytesFormatted',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _cleanSelectedFiles,
              icon: const Icon(Broken.trash, size: 18),
              label: const Text('Clean Now'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
