import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/icon_fonts/broken_icons.dart';
import '../../core/icon_fonts/nfile_icons.dart';
import '../../core/utils.dart';
import '../../providers/file_manager_provider.dart';
import '../../services/folder_share_service.dart';
import '../../services/pdf_toolkit_service.dart';
import '../screens/internal_file_picker_screen.dart';
import '../screens/pdf_viewer_screen.dart';

class PdfToolsBottomSheet extends StatefulWidget {
  final File file;

  const PdfToolsBottomSheet({
    super.key,
    required this.file,
  });

  static Future<void> show(BuildContext context, File file) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => PdfToolsBottomSheet(file: file),
    );
  }

  @override
  State<PdfToolsBottomSheet> createState() => _PdfToolsBottomSheetState();
}

class _PdfToolsBottomSheetState extends State<PdfToolsBottomSheet> {
  PdfInfo? _info;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadPdfInfo();
  }

  Future<void> _loadPdfInfo() async {
    try {
      final info = await PdfToolkitService.getPdfInfo(widget.file.path);
      if (mounted) {
        setState(() {
          _info = info;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSplit() async {
    if (_info == null || _info!.pageCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot split a PDF with fewer than 2 pages.')),
      );
      return;
    }

    int splitPage = (_info!.pageCount / 2).ceil();
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Split PDF', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Split into Part 1 (Pages 1 to $splitPage) and Part 2 (Pages ${splitPage + 1} to ${_info!.pageCount}):',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: splitPage.toDouble(),
                  min: 1,
                  max: (_info!.pageCount - 1).toDouble(),
                  divisions: _info!.pageCount - 1,
                  label: '$splitPage',
                  onChanged: (val) {
                    setDialogState(() {
                      splitPage = val.toInt();
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, splitPage),
                child: const Text('Split Now'),
              ),
            ],
          );
        },
      ),
    );

    if (res != null) {
      HapticFeedback.lightImpact();
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Splitting PDF in isolate...';
      });

      try {
        final resultPaths = await PdfToolkitService.splitPdfAtPage(widget.file, res);
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          _notifyDirectoryChange();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Split complete into 2 files!'),
              action: SnackBarAction(
                label: 'View Part 1',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfViewerScreen(filePath: resultPaths[0]),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Split failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleMerge() async {
    final pickedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const InternalFilePickerScreen(
          filterType: 'pdf',
        ),
      ),
    );

    if (pickedPath != null && pickedPath.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Merging PDFs in isolate...';
      });

      try {
        final mergedPath = await PdfToolkitService.mergePdfFiles([
          widget.file,
          File(pickedPath),
        ]);
        HapticFeedback.heavyImpact();

        if (mounted) {
          setState(() => _isProcessing = false);
          _notifyDirectoryChange();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('PDFs merged successfully!'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfViewerScreen(filePath: mergedPath),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Merge failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleExtractText() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Extracting document text in isolate...';
    });

    try {
      final text = await PdfToolkitService.extractText(widget.file);
      HapticFeedback.heavyImpact();

      if (mounted) {
        setState(() => _isProcessing = false);

        if (text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No plain text could be extracted (may be a scanned image PDF).')),
          );
          return;
        }

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Extracted Text',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy All'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save as .txt'),
                        onPressed: () async {
                          final dir = p.dirname(widget.file.path);
                          final base = p.basenameWithoutExtension(widget.file.path);
                          final outPath = p.join(dir, '${base}_extracted.txt');
                          await File(outPath).writeAsString(text);
                          _notifyDirectoryChange();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved to ${p.basename(outPath)}')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text extraction failed: $e')),
        );
      }
    }
  }

  void _notifyDirectoryChange() {
    try {
      final provider = context.read<FileManagerProvider>();
      provider.loadDirectory(provider.currentPath, showLoading: false, clearCache: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fileName = p.basename(widget.file.path);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF161622).withOpacity(0.92)
                : Colors.white.withOpacity(0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                width: 1.0,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag pill
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PDF Document Suite',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Meta badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'PDF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isLoading
                            ? 'Reading pages...'
                            : '${_info?.pageCount ?? 0} pages • ${FileUtils.formatBytes(_info?.fileSizeBytes ?? 0, 1)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (_isProcessing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 3),
                      const SizedBox(height: 14),
                      Text(
                        _statusMessage ?? 'Processing PDF in isolate...',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              else ...[
                // Action Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.3,
                  children: [
                    _buildActionCard(
                      icon: Icons.chrome_reader_mode_rounded,
                      color: const Color(0xFF6C63FF),
                      label: 'Read PDF',
                      subtitle: 'iOS-style reader',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfViewerScreen(filePath: widget.file.path),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(
                      icon: Icons.call_split_rounded,
                      color: const Color(0xFFFF9F43),
                      label: 'Split PDF',
                      subtitle: 'Separate pages',
                      onTap: _handleSplit,
                    ),
                    _buildActionCard(
                      icon: Icons.merge_type_rounded,
                      color: const Color(0xFF00D2D3),
                      label: 'Merge PDFs',
                      subtitle: 'Combine documents',
                      onTap: _handleMerge,
                    ),
                    _buildActionCard(
                      icon: Broken.text,
                      color: const Color(0xFF10AC84),
                      label: 'Extract Text',
                      subtitle: 'Isolate text extractor',
                      onTap: _handleExtractText,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
