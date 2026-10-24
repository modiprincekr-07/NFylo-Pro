import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../../../../providers/file_manager_provider.dart';
import '../../directory_screen.dart';
import '../models/storage_analysis_models.dart';
import '../storage_analyzer_screen.dart';

class StorageTreemapWidget extends StatelessWidget {
  final List<FolderSpaceTile> folderTiles;
  final Function(String path)? onOpenFolder;

  const StorageTreemapWidget({
    super.key,
    required this.folderTiles,
    this.onOpenFolder,
  });

  void _handleOpenFolder(BuildContext context, String path) {
    if (onOpenFolder != null) {
      onOpenFolder!(path);
      return;
    }

    final provider = context.read<FileManagerProvider>();
    provider.loadDirectory(path);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectoryScreen(toggleTheme: () {}),
      ),
    );
  }

  void _showFolderContextSheet(BuildContext context, FolderSpaceTile tile) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Folder Header
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: tile.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(tile.icon, color: tile.color, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tile.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tile.path,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: tile.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        FileUtils.formatBytes(tile.size, 1),
                        style: TextStyle(
                          color: tile.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Actions
                ListTile(
                  leading: const Icon(Broken.folder_open, size: 22),
                  title: const Text('Open in File Browser', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Browse all files inside this directory', style: TextStyle(fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleOpenFolder(context, tile.path);
                  },
                ),
                ListTile(
                  leading: const Icon(Broken.chart, size: 22),
                  title: const Text('Analyze This Folder', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Run deep storage analysis scoped to this directory', style: TextStyle(fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StorageAnalyzerScreen(initialVolumePath: tile.path),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Broken.document_copy, size: 22),
                  title: const Text('Copy Folder Path', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tile.path, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: tile.path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Folder path copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTiles = folderTiles.where((t) => t.size > 0).toList();
    final int totalMappedSize = activeTiles.fold(0, (sum, t) => sum + t.size);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Space Map',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Visual proportional disk usage',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  FileUtils.formatBytes(totalMappedSize, 1),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Treemap Area
          if (activeTiles.isEmpty)
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Broken.folder_2,
                      size: 38,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No folders mapped',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 250,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    const height = 250.0;
                    final boxes = _computeTreemap(activeTiles, Rect.fromLTWH(0, 0, width, height));

                    return Stack(
                      children: boxes.map((item) {
                        final tile = item.tile;
                        final rect = item.rect;
                        final percent = (tile.proportion * 100).toStringAsFixed(1);
                        final isCompact = rect.width < 80 || rect.height < 60;

                        return Positioned.fromRect(
                          rect: rect,
                          child: Container(
                            margin: const EdgeInsets.all(2.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  tile.color.withOpacity(0.85),
                                  tile.color,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: tile.color.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _handleOpenFolder(context, tile.path),
                                onLongPress: () => _showFolderContextSheet(context, tile),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: isCompact
                                      ? Center(
                                          child: Text(
                                            tile.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Icon(tile.icon, color: Colors.white.withOpacity(0.9), size: 18),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '$percent%',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tile.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12.5,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  FileUtils.formatBytes(tile.size, 1),
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.85),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Binary Space Partitioning (BSP) Treemap Algorithm
  List<_TreemapNode> _computeTreemap(List<FolderSpaceTile> items, Rect rect) {
    if (items.isEmpty) return [];
    if (items.length == 1) {
      return [_TreemapNode(tile: items.first, rect: rect)];
    }

    final double totalWeight = items.fold(0.0, (sum, item) => sum + item.proportion);
    if (totalWeight <= 0) return [];

    // Find best split point where weights on both sides are closest
    double runningWeight = 0.0;
    int splitIndex = 1;
    double bestDiff = double.infinity;

    for (int i = 0; i < items.length - 1; i++) {
      runningWeight += items[i].proportion;
      final diff = (runningWeight - (totalWeight / 2)).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        splitIndex = i + 1;
      }
    }

    final listA = items.sublist(0, splitIndex);
    final listB = items.sublist(splitIndex);

    final double weightA = listA.fold(0.0, (sum, i) => sum + i.proportion);
    final double fractionA = (weightA / totalWeight).clamp(0.05, 0.95);

    Rect rectA;
    Rect rectB;

    // Split along larger dimension
    if (rect.width >= rect.height) {
      final splitWidth = rect.width * fractionA;
      rectA = Rect.fromLTWH(rect.left, rect.top, splitWidth, rect.height);
      rectB = Rect.fromLTWH(rect.left + splitWidth, rect.top, rect.width - splitWidth, rect.height);
    } else {
      final splitHeight = rect.height * fractionA;
      rectA = Rect.fromLTWH(rect.left, rect.top, rect.width, splitHeight);
      rectB = Rect.fromLTWH(rect.left, rect.top + splitHeight, rect.width, rect.height - splitHeight);
    }

    return [
      ..._computeTreemap(listA, rectA),
      ..._computeTreemap(listB, rectB),
    ];
  }
}

class _TreemapNode {
  final FolderSpaceTile tile;
  final Rect rect;

  const _TreemapNode({required this.tile, required this.rect});
}
