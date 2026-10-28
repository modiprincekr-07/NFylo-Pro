import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../core/utils.dart';
import '../../providers/file_manager_provider.dart';
import '../../services/file_conversion_service.dart';
import '../../services/folder_share_service.dart';
import 'nfile_icon.dart';

enum _SheetPhase {
  select,
  converting,
  success,
  error,
}

class QuickConvertBottomSheet extends StatefulWidget {
  final File file;

  const QuickConvertBottomSheet({
    super.key,
    required this.file,
  });

  /// Opens the Quick Convert bottom sheet with glassmorphism blur and smooth transitions.
  static Future<void> show(BuildContext context, File file) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => QuickConvertBottomSheet(file: file),
    );
  }

  @override
  State<QuickConvertBottomSheet> createState() => _QuickConvertBottomSheetState();
}

class _QuickConvertBottomSheetState extends State<QuickConvertBottomSheet>
    with SingleTickerProviderStateMixin {
  _SheetPhase _phase = _SheetPhase.select;
  QuickConvertOption? _selectedOption;
  double _progress = 0.0;
  String _statusMessage = '';
  String? _resultPath;
  String? _errorMessage;
  late final List<QuickConvertOption> _options;
  late final String _mimeType;
  late final String _fileExt;
  late final int _fileSize;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _fileExt = p.extension(widget.file.path).toLowerCase().replaceFirst('.', '');
    _mimeType = lookupMimeType(widget.file.path) ?? 'application/octet-stream';
    _options = FileConversionService.instance.getAvailableOptions(widget.file.path);

    try {
      _fileSize = widget.file.existsSync() ? widget.file.lengthSync() : 0;
    } catch (_) {
      _fileSize = 0;
    }

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _startConversion(QuickConvertOption option) async {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedOption = option;
      _phase = _SheetPhase.converting;
      _progress = 0.0;
      _statusMessage = 'Converting to ${option.name}...';
      _errorMessage = null;
    });

    try {
      final outPath = await FileConversionService.instance.convertFile(
        inputPath: widget.file.path,
        targetOption: option,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
            });
          }
        },
        onStatus: (msg) {
          if (mounted) {
            setState(() {
              _statusMessage = msg;
            });
          }
        },
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _resultPath = outPath;
          _phase = _SheetPhase.success;
        });

        // Silently reload current folder so the converted file appears immediately
        try {
          final provider = context.read<FileManagerProvider>();
          provider.loadDirectory(provider.currentPath, showLoading: false, clearCache: true);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _phase = _SheetPhase.error;
        });
      }
    }
  }

  Future<void> _cancelConversion() async {
    await FileConversionService.instance.cancelActiveConversion();
    if (mounted) {
      setState(() {
        _phase = _SheetPhase.select;
        _progress = 0.0;
        _selectedOption = null;
      });
    }
  }

  IconData _getCategoryIcon(QuickConvertCategory cat) {
    switch (cat) {
      case QuickConvertCategory.video:
        return Broken.video_play;
      case QuickConvertCategory.audio:
        return Broken.music;
      case QuickConvertCategory.image:
        return Broken.gallery;
    }
  }

  Color _getCategoryColor(QuickConvertCategory cat) {
    switch (cat) {
      case QuickConvertCategory.video:
        return const Color(0xFF6C63FF);
      case QuickConvertCategory.audio:
        return const Color(0xFFFF9F43);
      case QuickConvertCategory.image:
        return const Color(0xFF00D2D3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

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

              // Header bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quick Convert',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          p.basename(widget.file.path),
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
                    onPressed: () {
                      if (_phase == _SheetPhase.converting) {
                        _cancelConversion();
                      }
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // File summary badge
              _buildFileMetaCard(isDark, theme),
              const SizedBox(height: 16),

              // Content according to phase
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildPhaseContent(isDark, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileMetaCard(bool isDark, ThemeData theme) {
    return Container(
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
              color: theme.colorScheme.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _fileExt.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _mimeType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
              ),
            ),
          ),
          Text(
            FileUtils.formatBytes(_fileSize, 1),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseContent(bool isDark, ThemeData theme) {
    switch (_phase) {
      case _SheetPhase.select:
        return _buildSelectionGrid(isDark, theme);
      case _SheetPhase.converting:
        return _buildConvertingView(isDark, theme);
      case _SheetPhase.success:
        return _buildSuccessView(isDark, theme);
      case _SheetPhase.error:
        return _buildErrorView(isDark, theme);
    }
  }

  Widget _buildSelectionGrid(bool isDark, ThemeData theme) {
    if (_options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Broken.info_circle,
              size: 40,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(height: 12),
            Text(
              'No conversion options available for .$_fileExt',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              'Quick Convert supports video, audio, and image files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('selection_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Convert to:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.9),
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final option = _options[index];
            final catColor = _getCategoryColor(option.category);
            final catIcon = _getCategoryIcon(option.category);

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _startConversion(option),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.035),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.06),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: catColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: NfileIcon(
                          catIcon,
                          color: catColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.description,
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
          },
        ),
      ],
    );
  }

  Widget _buildConvertingView(bool isDark, ThemeData theme) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          key: const ValueKey('converting_view'),
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing animated circular progress indicator
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(_glowAnimation.value),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    ),
                    Text(
                      _progress > 0 ? '${(_progress * 100).toInt()}%' : '...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Converting to ${_selectedOption?.name ?? 'selected format'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _statusMessage.isNotEmpty
                    ? _statusMessage
                    : 'Encoding frames asynchronously...',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _cancelConversion,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuccessView(bool isDark, ThemeData theme) {
    final resultFile = _resultPath != null ? File(_resultPath!) : null;
    final resultSize = (resultFile != null && resultFile.existsSync())
        ? resultFile.lengthSync()
        : 0;

    return Container(
      key: const ValueKey('success_view'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.greenAccent.withOpacity(0.18),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 42,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Conversion Complete!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Result file card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.file_present_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resultPath != null ? p.basename(_resultPath!) : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        FileUtils.formatBytes(resultSize, 1),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (_resultPath != null) {
                      context.read<FileManagerProvider>().openFile(context, _resultPath!);
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Open'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (_resultPath != null) {
                      FolderShareService.sharePaths(context, [_resultPath!]);
                    }
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(bool isDark, ThemeData theme) {
    return Container(
      key: const ValueKey('error_view'),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withOpacity(0.18),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Conversion Failed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _errorMessage ?? 'An error occurred during FFmpeg execution.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _phase = _SheetPhase.select;
                    _errorMessage = null;
                  });
                },
                child: const Text('Try Again'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
