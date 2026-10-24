import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../models/storage_cleanup_models.dart';

class LargeFilesCleanupTab extends StatefulWidget {
  final List<LargeFileCleanupItem> largeFiles;
  final VoidCallback onSelectionChanged;
  final void Function(LargeFileCleanupItem) onOpenFile;

  const LargeFilesCleanupTab({
    super.key,
    required this.largeFiles,
    required this.onSelectionChanged,
    required this.onOpenFile,
  });

  @override
  State<LargeFilesCleanupTab> createState() => _LargeFilesCleanupTabState();
}

class _LargeFilesCleanupTabState extends State<LargeFilesCleanupTab> {
  int _minSizeBytes = 25 * 1024 * 1024; // Default 25 MB

  String _formatDisplayFolder(String fullPath) {
    try {
      final parent = File(fullPath).parent.path;
      if (parent.startsWith('/storage/emulated/0')) {
        final rel = parent.substring('/storage/emulated/0'.length);
        return rel.isEmpty ? 'Internal Storage' : rel.replaceFirst('/', '');
      }
      return parent;
    } catch (_) {
      return '';
    }
  }

  IconData _getFileIcon(String ext) {
    final lower = ext.toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(lower)) return Broken.image;
    if (['.mp4', '.mkv', '.avi', '.mov'].contains(lower)) return Broken.video;
    if (['.mp3', '.m4a', '.flac', '.wav'].contains(lower)) return Broken.music;
    if (lower == '.pdf') return Broken.document;
    if (lower == '.apk') return Broken.box;
    if (['.zip', '.rar', '.7z'].contains(lower)) return Broken.archive;
    return Broken.document_text;
  }

  Color _getFileColor(String ext) {
    final lower = ext.toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.webp'].contains(lower)) return const Color(0xFF8B5CF6);
    if (['.mp4', '.mkv', '.avi', '.mov'].contains(lower)) return const Color(0xFFEF4444);
    if (['.mp3', '.m4a', '.flac'].contains(lower)) return const Color(0xFFF97316);
    if (lower == '.pdf') return const Color(0xFFEC4899);
    if (lower == '.apk') return const Color(0xFF10B981);
    if (['.zip', '.rar', '.7z'].contains(lower)) return const Color(0xFFF59E0B);
    return const Color(0xFF3B82F6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.largeFiles.where((f) => f.size >= _minSizeBytes).toList();
    final allSelected = filtered.isNotEmpty && filtered.every((f) => f.isSelected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter bar & Select All
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              // Filter chips
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildFilterChip('All > 25MB', 25 * 1024 * 1024),
                      const SizedBox(width: 6),
                      _buildFilterChip('> 50MB', 50 * 1024 * 1024),
                      const SizedBox(width: 6),
                      _buildFilterChip('> 100MB', 100 * 1024 * 1024),
                      const SizedBox(width: 6),
                      _buildFilterChip('> 500MB', 500 * 1024 * 1024),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    final newState = !allSelected;
                    for (final f in filtered) {
                      f.isSelected = newState;
                    }
                  });
                  widget.onSelectionChanged();
                },
                icon: Icon(
                  allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                  size: 16,
                ),
                label: Text(
                  allSelected ? 'Deselect' : 'Select All',
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),

        if (filtered.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Broken.tick_circle,
                    size: 48,
                    color: theme.colorScheme.primary.withOpacity(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No large files matching this filter',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = filtered[index];
              final fileColor = _getFileColor(item.extension);
              final icon = _getFileIcon(item.extension);
              final folder = _formatDisplayFolder(item.path);

              return Container(
                decoration: BoxDecoration(
                  color: item.isSelected
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: item.isSelected
                        ? theme.colorScheme.primary.withOpacity(0.4)
                        : theme.dividerColor.withOpacity(0.07),
                    width: item.isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        item.isSelected = !item.isSelected;
                      });
                      widget.onSelectionChanged();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          // Checkbox
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: item.isSelected,
                              onChanged: (val) {
                                setState(() {
                                  item.isSelected = val ?? false;
                                });
                                widget.onSelectionChanged();
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Icon Badge
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: fileColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: fileColor, size: 20),
                          ),
                          const SizedBox(width: 12),

                          // Name & details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  folder,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Size Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: fileColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              FileUtils.formatBytes(item.size, 1),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: fileColor,
                              ),
                            ),
                          ),

                          // Preview Button
                          IconButton(
                            icon: const Icon(Broken.eye, size: 18),
                            onPressed: () => widget.onOpenFile(item),
                            tooltip: 'Preview',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int bytes) {
    final theme = Theme.of(context);
    final isSelected = _minSizeBytes == bytes;

    return InkWell(
      onTap: () {
        setState(() {
          _minSizeBytes = bytes;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }
}
