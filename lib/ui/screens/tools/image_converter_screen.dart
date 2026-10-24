import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/image_suite_service.dart';
import '../internal_file_picker_screen.dart';

class ImageConverterScreen extends StatefulWidget {
  final String? initialImagePath;

  const ImageConverterScreen({super.key, this.initialImagePath});

  @override
  State<ImageConverterScreen> createState() => _ImageConverterScreenState();
}

class _ImageConverterScreenState extends State<ImageConverterScreen> {
  String? _selectedImagePath;
  Uint8List? _originalBytes;
  int _originalWidth = 0;
  int _originalHeight = 0;

  // Conversion parameters
  OutputImageFormat _targetFormat = OutputImageFormat.jpg;
  double _quality = 85.0; // 1 - 100
  int _scalePercent = 100; // 100, 75, 50, 25, custom
  bool _maintainAspectRatio = true;
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  // Converted result
  bool _isProcessing = false;
  Uint8List? _convertedBytes;
  String? _errorMessage;
  String? _savedFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _loadImage(widget.initialImagePath!);
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
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
      if (!{'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif', '.ico'}.contains(ext)) {
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
      _convertedBytes = null;
      _savedFilePath = null;
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();

      // Read image dimensions using Flutter's Image.memory decoder
      final decoded = await decodeImageFromList(bytes);

      setState(() {
        _originalBytes = bytes;
        _originalWidth = decoded.width;
        _originalHeight = decoded.height;
        _widthController.text = decoded.width.toString();
        _heightController.text = decoded.height.toString();
        _scalePercent = 100;
        _isProcessing = false;
      });

      _runConversion();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load image: $e';
        _isProcessing = false;
      });
    }
  }

  void _onScalePercentChanged(int percent) {
    setState(() {
      _scalePercent = percent;
      final targetW = (_originalWidth * (percent / 100)).round();
      final targetH = (_originalHeight * (percent / 100)).round();
      _widthController.text = targetW.toString();
      _heightController.text = targetH.toString();
    });
    _runConversion();
  }

  void _onWidthChanged(String val) {
    final w = int.tryParse(val);
    if (w != null && _maintainAspectRatio && _originalWidth > 0) {
      final ratio = _originalHeight / _originalWidth;
      final newH = (w * ratio).round();
      _heightController.text = newH.toString();
    }
    _scalePercent = 0; // custom
    _runConversion();
  }

  void _onHeightChanged(String val) {
    final h = int.tryParse(val);
    if (h != null && _maintainAspectRatio && _originalHeight > 0) {
      final ratio = _originalWidth / _originalHeight;
      final newW = (h * ratio).round();
      _widthController.text = newW.toString();
    }
    _scalePercent = 0; // custom
    _runConversion();
  }

  Future<void> _runConversion() async {
    if (_originalBytes == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final targetW = int.tryParse(_widthController.text);
      final targetH = int.tryParse(_heightController.text);

      final result = await ImageSuiteService.convertAndCompress(
        inputBytes: _originalBytes!,
        targetFormat: _targetFormat,
        quality: _quality.round(),
        targetWidth: targetW != _originalWidth ? targetW : null,
        targetHeight: targetH != _originalHeight ? targetH : null,
        maintainAspectRatio: _maintainAspectRatio,
      );

      if (mounted) {
        setState(() {
          _convertedBytes = result;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Conversion error: $e';
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _saveConvertedImage() async {
    if (_convertedBytes == null || _selectedImagePath == null) return;

    try {
      final base = p.basenameWithoutExtension(_selectedImagePath!);
      final outPath = await ImageSuiteService.saveImage(
        bytes: _convertedBytes!,
        subFolder: 'NFylo_Converted',
        baseName: '${base}_converted',
        extension: _targetFormat.name,
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
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    }
  }

  void _shareConvertedImage() {
    if (_convertedBytes == null) return;
    final tempPath = p.join(
      Directory.systemTemp.path,
      'converted_preview.${_targetFormat.name}',
    );
    File(tempPath).writeAsBytesSync(_convertedBytes!);
    Share.shareXFiles([XFile(tempPath)]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _originalBytes != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Format Converter & Compressor'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Select Image',
            onPressed: _pickImageFile,
          ),
          if (_convertedBytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Converted Image',
              onPressed: _shareConvertedImage,
            ),
        ],
      ),
      body: hasImage
          ? _buildActiveConverterBody(theme)
          : _buildEmptyPickerView(theme),
      bottomNavigationBar: hasImage && _convertedBytes != null
          ? _buildBottomActionSheet(theme)
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
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Broken.gallery_edit,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Image Converter & Compressor',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Convert images to JPG, PNG, WEBP, or ICO.\nAdjust compression quality, customize dimensions, and reduce file size effortlessly.',
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
              label: const Text('Choose Image'),
              style: FilledButton.styleFrom(
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
  // Active Converter View
  // --------------------------------------------------------------------------

  Widget _buildActiveConverterBody(ThemeData theme) {
    final origSize = _originalBytes?.length ?? 0;
    final convSize = _convertedBytes?.length ?? 0;
    final sizeReductionPercent = origSize > 0 && convSize > 0
        ? (((origSize - convSize) / origSize) * 100).round()
        : 0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Before / After Comparison Cards
          Row(
            children: [
              // Original Preview
              Expanded(
                child: _buildImagePreviewCard(
                  theme,
                  title: 'Original (${p.extension(_selectedImagePath!).toUpperCase().replaceAll('.', '')})',
                  imageBytes: _originalBytes!,
                  sizeBytes: origSize,
                  width: _originalWidth,
                  height: _originalHeight,
                ),
              ),
              const SizedBox(width: 12),
              // Converted Preview
              Expanded(
                child: _convertedBytes != null
                    ? _buildImagePreviewCard(
                        theme,
                        title: 'Output (${_targetFormat.name.toUpperCase()})',
                        imageBytes: _convertedBytes!,
                        sizeBytes: convSize,
                        width: int.tryParse(_widthController.text) ?? _originalWidth,
                        height: int.tryParse(_heightController.text) ?? _originalHeight,
                        reductionPercent: sizeReductionPercent,
                      )
                    : Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 1. Target Format Selection
          _buildSectionHeader(theme, 'Target Format'),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: OutputImageFormat.values.map((fmt) {
                final isSelected = _targetFormat == fmt;
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _targetFormat = fmt);
                      _runConversion();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fmt.name.toUpperCase(),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // 2. Compression Quality Slider
          _buildSectionHeader(
            theme,
            _targetFormat == OutputImageFormat.png
                ? 'PNG Compression Level'
                : 'Compression Quality: ${_quality.round()}%',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _targetFormat == OutputImageFormat.png
                          ? 'Lossless compression level'
                          : _quality > 80
                              ? 'High Quality (Light Compression)'
                              : _quality > 50
                                  ? 'Balanced Quality & Size'
                                  : 'Smallest File Size',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      '${_quality.round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _quality,
                  min: 5,
                  max: 100,
                  divisions: 19,
                  label: '${_quality.round()}%',
                  onChanged: (val) {
                    setState(() => _quality = val);
                  },
                  onChangeEnd: (_) => _runConversion(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 3. Resize & Resolution Controls
          _buildSectionHeader(theme, 'Dimensions & Resize'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preset Chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [100, 75, 50, 25].map((pct) {
                    final isSelected = _scalePercent == pct;
                    return ChoiceChip(
                      label: Text('$pct%'),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) _onScalePercentChanged(pct);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Width & Height text fields
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _widthController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Width (px)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: _onWidthChanged,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _maintainAspectRatio ? Icons.link : Icons.link_off,
                        color: _maintainAspectRatio ? theme.colorScheme.primary : Colors.grey,
                      ),
                      tooltip: _maintainAspectRatio
                          ? 'Aspect Ratio Locked'
                          : 'Aspect Ratio Unlocked',
                      onPressed: () {
                        setState(() => _maintainAspectRatio = !_maintainAspectRatio);
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Height (px)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: _onHeightChanged,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
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

  Widget _buildImagePreviewCard(
    ThemeData theme, {
    required String title,
    required Uint8List imageBytes,
    required int sizeBytes,
    required int width,
    required int height,
    int? reductionPercent,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (reductionPercent != null && reductionPercent > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$reductionPercent%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.zero, bottom: Radius.circular(0)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 36, color: Colors.grey),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FileUtils.formatBytes(sizeBytes, 2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: reductionPercent != null && reductionPercent > 0
                        ? Colors.green.shade800
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${width}x$height px',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildBottomActionSheet(ThemeData theme) {
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
                onPressed: _isProcessing ? null : _saveConvertedImage,
                icon: const Icon(Icons.file_download_outlined, size: 20),
                label: Text(
                  _savedFilePath != null ? 'Saved in Downloads' : 'Save Image',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: _isProcessing ? null : _shareConvertedImage,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
            ),
          ],
        ),
      ),
    );
  }
}
