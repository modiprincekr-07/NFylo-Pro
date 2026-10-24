import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../services/ai_vision_service.dart';

class AiImageCutoutScreen extends StatefulWidget {
  final String? initialImagePath;

  const AiImageCutoutScreen({super.key, this.initialImagePath});

  @override
  State<AiImageCutoutScreen> createState() => _AiImageCutoutScreenState();
}

class _AiImageCutoutScreenState extends State<AiImageCutoutScreen> {
  final AiVisionService _visionService = AiVisionService();
  final ImagePicker _picker = ImagePicker();

  String? _selectedImagePath;
  CutoutResult? _cutoutResult;
  double _sensitivity = 0.5;
  double _feathering = 2.0;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    _visionService.addListener(_onServiceUpdate);
    if (widget.initialImagePath != null) {
      _selectedImagePath = widget.initialImagePath;
    }
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _visionService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source);
    if (xFile != null) {
      setState(() {
        _selectedImagePath = xFile.path;
        _cutoutResult = null;
      });
    }
  }

  Future<void> _loadSampleImage() async {
    final tempDir = await getTemporaryDirectory();
    final sampleFile = File('${tempDir.path}/sample_portrait.png');

    // Create a 300x300 sample image with circular subject and distinct background
    final sample = img.Image(width: 300, height: 300);
    img.fill(sample, color: img.ColorRgb8(240, 240, 245)); // Soft white background
    img.fillCircle(sample, x: 150, y: 150, radius: 80, color: img.ColorRgb8(30, 136, 229)); // Blue circle subject

    await sampleFile.writeAsBytes(img.encodePng(sample));

    setState(() {
      _selectedImagePath = sampleFile.path;
      _cutoutResult = null;
    });
  }

  Future<void> _runCutout() async {
    if (_selectedImagePath == null) return;
    try {
      final res = await _visionService.removeBackground(
        imagePath: _selectedImagePath!,
        sensitivity: _sensitivity,
        feathering: _feathering,
      );
      setState(() {
        _cutoutResult = res;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cutout error: $e')),
      );
    }
  }

  void _shareResult() {
    if (_cutoutResult != null) {
      Share.shareXFiles([XFile(_cutoutResult!.outputPath)], text: 'Cutout PNG from NFylo AI Lab');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI Image Cutout (FastSAM)'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_cutoutResult != null)
            IconButton(
              icon: const Icon(Broken.share),
              tooltip: 'Share PNG',
              onPressed: _shareResult,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImagePickerCard(theme, isDark),
            const SizedBox(height: 16),
            if (_selectedImagePath != null) ...[
              _buildControlsCard(theme, isDark),
              const SizedBox(height: 16),
              _buildPreviewArea(theme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Broken.gallery, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Source Photo',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Broken.gallery),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Broken.camera),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Broken.magicpen),
                  label: const Text('Sample'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loadSampleImage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cutout Sensitivity: ${(_sensitivity * 100).toInt()}%'),
              Text(_sensitivity > 0.6 ? 'Aggressive' : (_sensitivity < 0.4 ? 'Conservative' : 'Balanced')),
            ],
          ),
          Slider(
            value: _sensitivity,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            label: '${(_sensitivity * 100).toInt()}%',
            onChanged: (v) => setState(() => _sensitivity = v),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Boundary Feathering: ${_feathering.toStringAsFixed(1)} px'),
              Text(_feathering == 0 ? 'Hard Edge' : 'Soft Edge'),
            ],
          ),
          Slider(
            value: _feathering,
            min: 0.0,
            max: 6.0,
            divisions: 6,
            label: '${_feathering.toStringAsFixed(1)} px',
            onChanged: (v) => setState(() => _feathering = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _visionService.isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Broken.scissor),
              label: Text(_visionService.isProcessing ? 'Segmenting Foreground...' : 'Remove Background'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _visionService.isProcessing ? null : _runCutout,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  _cutoutResult != null
                      ? (_showOriginal ? 'Original Image' : 'Transparent Cutout PNG')
                      : 'Source Preview',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_cutoutResult != null)
                  TextButton.icon(
                    icon: Icon(_showOriginal ? Broken.eye : Broken.eye_slash, size: 16),
                    label: Text(_showOriginal ? 'Show Cutout' : 'Show Original'),
                    onPressed: () => setState(() => _showOriginal = !_showOriginal),
                  ),
              ],
            ),
          ),
          Container(
            height: 280,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              // Checkerboard pattern for transparent PNG background
              color: isDark ? const Color(0xFF2C2C34) : const Color(0xFFE0E0E0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cutoutResult != null && !_showOriginal) ...[
                  // Checkerboard background
                  CustomPaint(painter: _CheckerboardPainter()),
                  Image.file(File(_cutoutResult!.outputPath), fit: BoxFit.contain),
                ] else if (_selectedImagePath != null) ...[
                  Image.file(File(_selectedImagePath!), fit: BoxFit.contain),
                ],
              ],
            ),
          ),
          if (_cutoutResult != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Time: ${_cutoutResult!.processingTimeMs} ms',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  Text(
                    'Size: ${(_cutoutResult!.fileSize / 1024).toStringAsFixed(1)} KB (Lossless PNG)',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 16.0;
    final paint1 = Paint()..color = const Color(0xFFEEEEEE);
    final paint2 = Paint()..color = const Color(0xFFD6D6D6);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isEven = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
