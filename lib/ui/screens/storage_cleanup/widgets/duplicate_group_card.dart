import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../models/storage_cleanup_models.dart';

class DuplicateGroupCard extends StatelessWidget {
  final DuplicateGroup group;
  final VoidCallback onSelectionChanged;
  final void Function(DuplicateFileItem) onOpenFile;

  const DuplicateGroupCard({
    super.key,
    required this.group,
    required this.onSelectionChanged,
    required this.onOpenFile,
  });

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

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

  IconData _getFileIcon(String name) {
    final lower = name.toLowerCase();
    if (FileUtils.isImage(lower)) return Broken.image;
    if (FileUtils.isVideo(lower)) return Broken.video;
    if (FileUtils.isAudio(lower)) return Broken.music;
    if (lower.endsWith('.pdf')) return Broken.document;
    if (lower.endsWith('.apk')) return Broken.box;
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return Broken.archive;
    return Broken.document_text;
  }

  Color _getFileColor(String name) {
    final lower = name.toLowerCase();
    if (FileUtils.isImage(lower)) return const Color(0xFF8B5CF6);
    if (FileUtils.isVideo(lower)) return const Color(0xFFEF4444);
    if (FileUtils.isAudio(lower)) return const Color(0xFFF97316);
    if (lower.endsWith('.pdf')) return const Color(0xFFEC4899);
    if (lower.endsWith('.apk')) return const Color(0xFF10B981);
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) return const Color(0xFFF59E0B);
    return const Color(0xFF3B82F6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileColor = _getFileColor(group.fileName);
    final icon = _getFileIcon(group.fileName);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Header
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // File Type Badge
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: fileColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group.fileName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (group.isSimilarImage) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Similar Photo',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${group.files.length} copies • ${FileUtils.formatBytes(group.fileSize, 1)} each • Saves ${FileUtils.formatBytes(group.totalWastedBytes, 1)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Auto "Keep Original" Button
                TextButton.icon(
                  onPressed: () {
                    group.selectDuplicatesOnly();
                    onSelectionChanged();
                  },
                  icon: const Icon(Broken.tick_circle, size: 15),
                  label: const Text('Keep Original', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // File copies list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: group.files.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 52,
              color: theme.dividerColor.withOpacity(0.06),
            ),
            itemBuilder: (context, index) {
              final fileItem = group.files[index];
              final folderName = _formatDisplayFolder(fileItem.path);

              return InkWell(
                onTap: () {
                  fileItem.isSelected = !fileItem.isSelected;
                  onSelectionChanged();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Checkbox
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: fileItem.isSelected,
                          onChanged: (val) {
                            fileItem.isSelected = val ?? false;
                            onSelectionChanged();
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Badge: Original vs Duplicate
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: fileItem.isOriginal
                              ? const Color(0xFF10B981).withOpacity(0.12)
                              : const Color(0xFFF59E0B).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          fileItem.isOriginal ? 'Original' : 'Duplicate',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: fileItem.isOriginal
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Folder path & Date
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              folderName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Modified: ${_formatDate(fileItem.modified)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // View / Open button
                      IconButton(
                        icon: const Icon(Broken.eye, size: 18),
                        onPressed: () => onOpenFile(fileItem),
                        tooltip: 'Preview File',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
