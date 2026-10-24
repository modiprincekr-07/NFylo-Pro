import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/file_manager_provider.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../core/utils.dart';
import 'nfile_icon.dart';

class FolderCustomizationDialog extends StatefulWidget {
  final String folderPath;

  const FolderCustomizationDialog({
    super.key,
    required this.folderPath,
  });

  static Future<void> show(BuildContext context, String folderPath) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FolderCustomizationDialog(folderPath: folderPath),
    );
  }

  @override
  State<FolderCustomizationDialog> createState() => _FolderCustomizationDialogState();
}

class _FolderCustomizationDialogState extends State<FolderCustomizationDialog> {
  Color? _selectedColor;
  String? _selectedIconKey;
  bool _initialized = false;

  static const List<Map<String, dynamic>> _colors = [
    {'name': 'Default', 'color': null},
    {'name': 'Blue', 'color': Color(0xFF2196F3)},
    {'name': 'Cyan', 'color': Color(0xFF00BCD4)},
    {'name': 'Teal', 'color': Color(0xFF009688)},
    {'name': 'Green', 'color': Color(0xFF4CAF50)},
    {'name': 'Orange', 'color': Color(0xFFFF9800)},
    {'name': 'Deep Orange', 'color': Color(0xFFFF5722)},
    {'name': 'Red', 'color': Color(0xFFE53935)},
    {'name': 'Pink', 'color': Color(0xFFE91E63)},
    {'name': 'Purple', 'color': Color(0xFF9C27B0)},
    {'name': 'Deep Purple', 'color': Color(0xFF673AB7)},
    {'name': 'Indigo', 'color': Color(0xFF3F51B5)},
    {'name': 'Brown', 'color': Color(0xFF795548)},
    {'name': 'Blue Grey', 'color': Color(0xFF607D8B)},
  ];

  static const List<Map<String, dynamic>> _icons = [
    {'key': null, 'name': 'Default', 'icon': Broken.folder},
    {'key': 'music', 'name': 'Music', 'icon': Broken.music},
    {'key': 'camera', 'name': 'Camera', 'icon': Broken.camera},
    {'key': 'video', 'name': 'Video', 'icon': Broken.video},
    {'key': 'code', 'name': 'Code', 'icon': Broken.code},
    {'key': 'document', 'name': 'Document', 'icon': Broken.document},
    {'key': 'archive', 'name': 'Archive', 'icon': Broken.archive},
    {'key': 'download', 'name': 'Download', 'icon': Broken.document_download},
    {'key': 'game', 'name': 'Game', 'icon': Broken.gameboy},
    {'key': 'star', 'name': 'Star', 'icon': Broken.star},
    {'key': 'lock', 'name': 'Lock', 'icon': Broken.lock},
    {'key': 'work', 'name': 'Work', 'icon': Broken.briefcase},
    {'key': 'heart', 'name': 'Heart', 'icon': Broken.heart},
    {'key': 'cloud', 'name': 'Cloud', 'icon': Broken.cloud},
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final provider = context.read<FileManagerProvider>();
      _selectedColor = provider.getFolderColor(widget.folderPath);
      _selectedIconKey = provider.getFolderCustomIcon(widget.folderPath);
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folderName = p.basename(widget.folderPath);
    final effectiveColor = _selectedColor ?? theme.colorScheme.primary;
    final displayIcon = FileUtils.getNamedFolderIcon(_selectedIconKey) ?? Broken.folder;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
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

            // Header with Preview
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: effectiveColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: NfileIcon(displayIcon, color: effectiveColor, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customize Folder',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        folderName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedColor = null;
                      _selectedIconKey = null;
                    });
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Color Picker section
            Text(
              'Folder Color',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = _colors[index];
                  final Color? color = entry['color'] as Color?;
                  final isSelected = (_selectedColor == null && color == null) ||
                      (_selectedColor != null && color != null && _selectedColor!.value == color.value);

                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color ?? theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: (color ?? theme.colorScheme.primary).withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : (color == null
                              ? const Center(
                                  child: Icon(Icons.palette_outlined, color: Colors.white, size: 18),
                                )
                              : null),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Custom Icon section
            Text(
              'Folder Icon',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: _icons.length,
              itemBuilder: (context, index) {
                final entry = _icons[index];
                final String? key = entry['key'] as String?;
                final IconData icon = entry['icon'] as IconData;
                final isSelected = _selectedIconKey == key;

                return GestureDetector(
                  onTap: () => setState(() => _selectedIconKey = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? effectiveColor.withOpacity(0.2)
                          : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? effectiveColor : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: NfileIcon(
                        icon,
                        color: isSelected ? effectiveColor : theme.colorScheme.onSurface.withOpacity(0.7),
                        size: 22,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final provider = context.read<FileManagerProvider>();
                      provider.setFolderColor(widget.folderPath, _selectedColor);
                      provider.setFolderCustomIcon(widget.folderPath, _selectedIconKey);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Updated customization for $folderName'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
