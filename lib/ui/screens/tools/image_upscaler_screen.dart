import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/image_suite_service.dart';
import '../internal_file_picker_screen.dart';

class ImageUpscalerScreen extends StatefulWidget {
  final String? initialImagePath;

  const ImageUpscalerScreen({super.key, this.initialImagePath});

  @override
  State<ImageUpscalerScreen> createState() => _ImageUpscalerScreenState();
}

class _ImageUpscalerScreenState extends State<ImageUpscalerScreen> {
  String? _selectedImagePath;
  Uint8List? _originalBytes;
  int _originalWidth = 0;
  int _originalHeight = 0;

  // Upscale configuration
  UpscaleFactor _scaleFactor = UpscaleFactor.x2;
  UpscaleInterpolation _interpolation = UpscaleInterpolation.bicubic;

  // Processing state
  bool _isUpscaling = false;
  Uint8List? _upscaledBytes;
  int _upscaledWidth = 0;
  int _upscaledHeight = 0;
  String? _errorMessage;
  String? _savedFilePath;

  // Preview tab: 0 = Upscaled, 1 = Original
  int _previewMode = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _loadImage(widget.initialImagePath!);
    }
  }

  Future<void> _pickImageFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      final path = picked.first;
      final ext = p.extension(path).toLowerCase();
      if (!{'.jpg', '.jpeg', '.png', '.webp', '.bmp'}.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an image file.')),
        );
        return;
      }
      _loadImage(path);
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _selectedImagePath = path;
      _upscaledBytes = null;
      _savedFilePath = null;
      _errorMessage = null;
    });

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);

      setState(() {
        _originalBytes = bytes;
        _originalWidth = decoded.width;
        _originalHeight = decoded.height;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load image: $e');
    }
  }

  Future<void> _runUpscale() async {
    if (_originalBytes == null) return;

    setState(() {
      _isUpscaling = true;
      _errorMessage = null;
      _savedFilePath = null;
    });

    try {
      final result = await ImageSuiteService.upscaleImage(
        inputBytes: _originalBytes!,
        factor: _scaleFactor,
        interpolation: _interpolation,
      );

      final multiplier = _scaleFactor == UpscaleFactor.x4 ? 4 : 2;

      setState(() {
        _upscaledBytes = result;
        _upscaledWidth = _originalWidth * multiplier;
        _upscaledHeight = _originalHeight * multiplier;
        _isUpscaling = false;
        _previewMode = 0;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Upscaling failed: $e';
        _isUpscaling = false;
      });
    }
  }

  Future<void> _saveUpscaledImage() async {
    if (_upscaledBytes == null || _selectedImagePath == null) return;

    try {
      final base = p.basenameWithoutExtension(_selectedImagePath!);
      final multiplier = _scaleFactor == UpscaleFactor.x4 ? '4x' : '2x';
      final isPng = _upscaledBytes!.length > 4 &&
          _upscaledBytes![0] == 0x89 &&
          _upscaledBytes![1] == 0x50;
      final ext = isPng ? 'png' : 'jpg';
      final outPath = await ImageSuiteService.saveImage(
        bytes: _upscaledBytes!,
        subFolder: 'NFylo_Upscaled',
        baseName: '${base}_upscaled_${multiplier}',
        extension: ext,
      );

      setState(() => _savedFilePath = outPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: ${p.basename(outPath)}'),
            backgroundColor: Colors.green.shade700,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save upscaled image: $e')),
        );
      }
    }
  }

  void _shareUpscaledImage() {
    if (_savedCleanPathOrTemp() != null) {
      Share.shareXFiles([XFile(_savedCleanPathOrTemp()!)]);
    }
  }

  String? _savedCleanPathOrTemp() {
    if (_savedFilePath != null) return _savedFilePath;
    if (_upscaledBytes != null) {
      final isPng = _upscaledBytes!.length > 4 &&
          _upscaledBytes![0] == 0x89 &&
          _upscaledBytes![1] == 0x50;
      final temp = p.join(
        Directory.systemTemp.path,
        'upscaled_preview.${isPng ? "png" : "jpg"}',
      );
      File(temp).writeAsBytesSync(_upscaledBytes!);
      return temp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _originalBytes != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Image Upscaler (2x / 4x)'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Choose Image',
            onPressed: _pickImageFile,
          ),
          if (_upscaledBytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _shareUpscaledImage,
            ),
        ],
      ),
      body: hasImage
          ? _buildActiveUpscaleView(theme)
          : _buildEmptyPickerView(theme),
      bottomNavigationBar: hasImage && _upscaledBytes != null
          ? _buildBottomActionBar(theme)
          : null,
    );
  }

  // --------------------------------------------------------------------------
  // Empty State: Select image
  // --------------------------------------------------------------------------

  Widget _buildEmptyPickerView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Broken.maximize_4,
                size: 64,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'High-Resolution Image Upscaler',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Enlarge low-resolution photos and pixel art by 2x or 4x.\nUses pure Dart bicubic and cubic polynomial interpolation for smooth, sharp results without blur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _pickImageFile,
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Choose Image to Upscale'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Active Upscaler View
  // --------------------------------------------------------------------------

  Widget _buildActiveUpscaleView(ThemeData theme) {
    final multiplier = _scaleFactor == UpscaleFactor.x4 ? 4 : 2;
    final projectedW = _originalWidth * multiplier;
    final projectedH = _originalHeight * multiplier;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zoomable Interactive Image Preview Box
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    maxScale: 6.0,
                    child: _isUpscaling
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text(
                                  'Calculating bicubic interpolation...',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : Image.memory(
                            _previewMode == 0 && _upscaledBytes != null
                                ? _upscaledBytes!
                                : _originalBytes!,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),

                // Pinch to Zoom hint badge
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Pinch to zoom',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),

                // Toggle Preview Mode Tab
                if (_upscaledBytes != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        children: [
                          _buildPreviewToggleBtn('Upscaled', _previewMode == 0, () {
                            setState(() => _previewMode = 0);
                          }),
                          _buildPreviewToggleBtn('Original', _previewMode == 1, () {
                            setState(() => _previewMode = 1);
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Upscaling Specifications Comparison Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCol(
                        title: 'Original',
                        res: '${_originalWidth}x$_originalHeight',
                        size: FileUtils.formatBytes(_originalBytes!.length, 1),
                        theme: theme,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
                    ),
                    Expanded(
                      child: _buildMetricCol(
                        title: _upscaledBytes != null ? 'Upscaled' : 'Projected',
                        res: '${_upscaledBytes != null ? _upscaledWidth : projectedW}x${_upscaledBytes != null ? _upscaledHeight : projectedH}',
                        size: _upscaledBytes != null
                            ? FileUtils.formatBytes(_upscaledBytes!.length, 1)
                            : '~${FileUtils.formatBytes(_originalBytes!.length * multiplier * 2, 1)}',
                        theme: theme,
                        isHighlight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 1. Scale Factor Selector (2x / 4x)
          _buildSectionHeader(theme, 'Upscale Scale Factor'),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildScaleOptionTab(
                    label: '2x Resolution',
                    subtitle: '${_originalWidth * 2} x ${_originalHeight * 2} px',
                    isSelected: _scaleFactor == UpscaleFactor.x2,
                    onTap: () {
                      setState(() => _scaleFactor = UpscaleFactor.x2);
                    },
                    theme: theme,
                  ),
                ),
                Expanded(
                  child: _buildScaleOptionTab(
                    label: '4x Ultra-Res',
                    subtitle: '${_originalWidth * 4} x ${_originalHeight * 4} px',
                    isSelected: _scaleFactor == UpscaleFactor.x4,
                    onTap: () {
                      setState(() => _scaleFactor = UpscaleFactor.x4);
                    },
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Interpolation Algorithm Selector
          _buildSectionHeader(theme, 'Interpolation Algorithm'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                _buildInterpRadioTile(
                  title: 'Bicubic (Cubic Spline)',
                  subtitle: 'Smooth gradients and sharp edges (Recommended for photos)',
                  value: UpscaleInterpolation.bicubic,
                ),
                const Divider(height: 12),
                _buildInterpRadioTile(
                  title: 'Bilinear (Linear)',
                  subtitle: 'Faster computation with soft pixel blending',
                  value: UpscaleInterpolation.bilinear,
                ),
                const Divider(height: 12),
                _buildInterpRadioTile(
                  title: 'Nearest Neighbor',
                  subtitle: 'Preserves sharp block pixels (Ideal for pixel art & retro graphics)',
                  value: UpscaleInterpolation.nearest,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Process Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isUpscaling ? null : _runUpscale,
              icon: _isUpscaling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_fix_high, size: 20),
              label: Text(
                _isUpscaling
                    ? 'Upscaling image in background...'
                    : _upscaledBytes != null
                        ? 'Re-Upscale Image'
                        : 'Upscale Image (${_scaleFactor == UpscaleFactor.x4 ? "4x" : "2x"})',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewToggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildScaleOptionTab({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
                color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected ? Colors.white.withOpacity(0.8) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterpRadioTile({
    required String title,
    required String subtitle,
    required UpscaleInterpolation value,
  }) {
    final isSelected = _interpolation == value;
    return InkWell(
      onTap: () => setState(() => _interpolation = value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Radio<UpscaleInterpolation>(
              value: value,
              groupValue: _interpolation,
              onChanged: (val) {
                if (val != null) setState(() => _interpolation = val);
              },
              activeColor: Colors.teal,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCol({
    required String title,
    required String res,
    required String size,
    required ThemeData theme,
    bool isHighlight = false,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          res,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isHighlight ? Colors.teal : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          size,
          style: TextStyle(
            fontSize: 11,
            color: isHighlight ? Colors.teal.shade700 : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _saveUpscaledImage,
                icon: const Icon(Icons.file_download_outlined, size: 20),
                label: Text(
                  _savedFilePath != null ? 'Saved in Downloads' : 'Save Upscaled Image',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: _shareUpscaledImage,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
            ),
          ],
        ),
      ),
    );
  }
}
