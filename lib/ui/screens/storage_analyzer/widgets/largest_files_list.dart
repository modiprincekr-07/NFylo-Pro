import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../models/storage_analysis_models.dart';

class LargestFilesList extends StatefulWidget {
  final List<LargestFileItem> files;
  final void Function(LargestFileItem) onOpenFile;
  final void Function(LargestFileItem) onShareFile;
  final void Function(LargestFileItem) onDeleteFile;
  final void Function(List<LargestFileItem>)? onBatchShare;
  final void Function(List<LargestFileItem>)? onBatchDelete;

  const LargestFilesList({
    super.key,
    required this.files,
    required this.onOpenFile,
    required this.onShareFile,
    required this.onDeleteFile,
    this.onBatchShare,
    this.onBatchDelete,
  });

  @override
  State<LargestFilesList> createState() => _LargestFilesListState();
}

class _LargestFilesListState extends State<LargestFilesList> {
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = <String>{};
  bool _isExpanded = false;
  static const int _previewLimit = 6;

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedPaths.length == widget.files.length) {
        _selectedPaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedPaths.addAll(widget.files.map((e) => e.path));
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPaths.clear();
    });
  }

  List<LargestFileItem> get _selectedItems {
    return widget.files.where((f) => _selectedPaths.contains(f.path)).toList();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _getDisplayFolder(String fullPath) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.files.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayedFiles = _isExpanded
        ? widget.files
        : widget.files.take(_previewLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header / Batch Actions Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: _isSelectionMode
              ? _buildSelectionToolbar(theme)
              : _buildStandardHeader(theme),
        ),

        // List of largest files
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: displayedFiles.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = displayedFiles[index];
            final isSelected = _selectedPaths.contains(item.path);
            return _buildFileCard(context, item, isSelected, theme, isDark);
          },
        ),

        // Expand / Collapse button
        if (widget.files.length > _previewLimit)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isExpanded
                          ? 'Show Less'
                          : 'Show All ${widget.files.length} Large Files',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStandardHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Broken.document_upload,
                size: 18,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Largest Files',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Top ${widget.files.length} heavy items consuming disk',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
            });
          },
          icon: const Icon(Broken.tick_circle, size: 16),
          label: const Text('Select', style: TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionToolbar(ThemeData theme) {
    final allSelected = _selectedPaths.length == widget.files.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: _exitSelectionMode,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Cancel',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_selectedPaths.length} selected',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            onPressed: _selectAll,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(),
            tooltip: allSelected ? 'Deselect All' : 'Select All',
          ),
          if (_selectedPaths.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Broken.share, size: 20),
              color: theme.colorScheme.primary,
              onPressed: () {
                final items = _selectedItems;
                if (widget.onBatchShare != null) {
                  widget.onBatchShare!(items);
                } else {
                  for (final it in items) {
                    widget.onShareFile(it);
                  }
                }
              },
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(),
              tooltip: 'Share',
            ),
            IconButton(
              icon: const Icon(Broken.trash, size: 20, color: Color(0xFFEF4444)),
              onPressed: () {
                final items = _selectedItems;
                if (widget.onBatchDelete != null) {
                  widget.onBatchDelete!(items);
                } else {
                  for (final it in items) {
                    widget.onDeleteFile(it);
                  }
                }
              },
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(),
              tooltip: 'Delete',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileCard(
    BuildContext context,
    LargestFileItem item,
    bool isSelected,
    ThemeData theme,
    bool isDark,
  ) {
    final folderName = _getDisplayFolder(item.path);

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.dividerColor.withOpacity(0.07),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(item.path);
            } else {
              widget.onOpenFile(item);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                _selectedPaths.add(item.path);
              });
            } else {
              _toggleSelection(item.path);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Leading Icon or Checkbox
                if (_isSelectionMode)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.dividerColor.withOpacity(0.6),
                      size: 22,
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 20),
                  ),

                // File Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (folderName.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                folderName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.55),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.4),
                              ),
                            ),
                          ],
                          Text(
                            _formatDate(item.modified),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Size Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    FileUtils.formatBytes(item.size, 1),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: item.color,
                    ),
                  ),
                ),

                // Actions Popup (only if not in selection mode)
                if (!_isSelectionMode) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'open':
                          widget.onOpenFile(item);
                          break;
                        case 'share':
                          widget.onShareFile(item);
                          break;
                        case 'delete':
                          widget.onDeleteFile(item);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'open',
                        child: Row(
                          children: [
                            Icon(Broken.eye, size: 18),
                            SizedBox(width: 10),
                            Text('Open', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Broken.share, size: 18),
                            SizedBox(width: 10),
                            Text('Share', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Broken.trash, size: 18, color: Color(0xFFEF4444)),
                            SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
