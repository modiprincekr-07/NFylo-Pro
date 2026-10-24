import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../services/ai_vision_service.dart';

class AiImageRestorationScreen extends StatefulWidget {
  final String? initialImagePath;

  const AiImageRestorationScreen({super.key, this.initialImagePath});

  @override
  State<AiImageRestorationScreen> createState() => _AiImageRestorationScreenState();
}

class _AiImageRestorationScreenState extends State<AiImageRestorationScreen> {
  final AiVisionService _visionService = AiVisionService();
  final ImagePicker _picker = ImagePicker();

  String? _selectedImagePath;
  RestorationResult? _restorationResult;
  String _selectedModel = 'gfpgan';
  double _sharpness = 1.4;
  double _splitRatio = 0.5; // For Before/After comparison slider (0.0 to 1.0)

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
        _restorationResult = null;
      });
    }
  }

  Future<void> _loadSampleImage() async {
    final tempDir = await getTemporaryDirectory();
    final sampleFile = File('${tempDir.path}/sample_vintage_photo.jpg');

    // Create a 240x240 sample image
    final sample = img.Image(width: 240, height: 240);
    img.fill(sample, color: img.ColorRgb8(190, 175, 160)); // Sepia tone background
    img.fillCircle(sample, x: 120, y: 120, radius: 60, color: img.ColorRgb8(120, 80, 50));
    img.fillCircle(sample, x: 100, y: 100, radius: 8, color: img.ColorRgb8(40, 20, 10)); // eye left
    img.fillCircle(sample, x: 140, y: 100, radius: 8, color: img.ColorRgb8(40, 20, 10)); // eye right

    // Add noise to simulate vintage / blurry photo
    img.noise(sample, 25);

    await sampleFile.writeAsBytes(img.encodeJpg(sample, quality: 70));

    setState(() {
      _selectedImagePath = sampleFile.path;
      _restorationResult = null;
    });
  }

  Future<void> _runRestoration() async {
    if (_selectedImagePath == null) return;
    try {
      final res = await _visionService.restoreImage(
        imagePath: _selectedImagePath!,
        model: _selectedModel,
        sharpness: _sharpness,
      );
      setState(() {
        _restorationResult = res;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restoration error: $e')),
      );
    }
  }

  void _shareResult() {
    if (_restorationResult != null) {
      Share.shareXFiles([XFile(_restorationResult!.outputPath)], text: 'Restored photo via NFylo AI Lab');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI Photo & Face Restoration'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_restorationResult != null)
            IconButton(
              icon: const Icon(Broken.share),
              tooltip: 'Share Restored Photo',
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
              _buildModelConfigCard(theme, isDark),
              const SizedBox(height: 16),
              _buildComparisonArea(theme, isDark),
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

  Widget _buildModelConfigCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.magicpen, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Enhancement Model',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 'gfpgan', child: Text('GFPGAN (Facial Clarity & Super Resolution 2x)')),
              DropdownMenuItem(value: 'esrgan_2x', child: Text('Real-ESRGAN (General 2x Super Resolution)')),
              DropdownMenuItem(value: 'esrgan_4x', child: Text('Real-ESRGAN (General 4x Ultra HD)')),
              DropdownMenuItem(value: 'denoise', child: Text('Low Light Denoise & Smoothing')),
            ],
            onChanged: (v) => setState(() => _selectedModel = v!),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sharpening Strength: ${_sharpness.toStringAsFixed(1)}x'),
              Text(_sharpness > 1.5 ? 'Intense' : (_sharpness < 1.0 ? 'Subtle' : 'Standard')),
            ],
          ),
          Slider(
            value: _sharpness,
            min: 0.5,
            max: 2.5,
            divisions: 8,
            label: '${_sharpness.toStringAsFixed(1)}x',
            onChanged: (v) => setState(() => _sharpness = v),
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
                  : const Icon(Broken.magicpen),
              label: Text(_visionService.isProcessing ? 'Enhancing Photo Details...' : 'Restore & Upscale Photo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _visionService.isProcessing ? null : _runRestoration,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonArea(ThemeData theme, bool isDark) {
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
                  _restorationResult != null
                      ? 'Interactive Split Comparison'
                      : 'Source Preview',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_restorationResult != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_restorationResult!.originalWidth}x${_restorationResult!.originalHeight} ➔ ${_restorationResult!.restoredWidth}x${_restorationResult!.restoredHeight}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 300,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark ? Colors.black : const Color(0xFFEEEEEE),
            ),
            clipBehavior: Clip.antiAlias,
            child: _restorationResult == null
                ? Image.file(File(_selectedImagePath!), fit: BoxFit.contain)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final splitX = width * _splitRatio;

                      return GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _splitRatio = (details.localPosition.dx / width).clamp(0.05, 0.95);
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Right side: Restored image
                            Image.file(File(_restorationResult!.outputPath), fit: BoxFit.contain),

                            // Left side: Original image clipped
                            ClipRect(
                              clipper: _HorizontalSplitClipper(splitX),
                              child: Image.file(File(_selectedImagePath!), fit: BoxFit.contain),
                            ),

                            // Vertical divider bar
                            Positioned(
                              left: splitX - 1.5,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 3,
                                color: Colors.white,
                              ),
                            ),

                            // Draggable Handle
                            Positioned(
                              left: splitX - 16,
                              top: constraints.maxHeight / 2 - 16,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black38, blurRadius: 4),
                                  ],
                                ),
                                child: const Icon(Broken.arrow_swap_horizontal, size: 16, color: Colors.white),
                              ),
                            ),

                            // Badges: "Original" and "Restored"
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Original', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Restored', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_restorationResult != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Time: ${_restorationResult!.processingTimeMs} ms',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  Text(
                    'Size: ${(_restorationResult!.fileSize / 1024).toStringAsFixed(1)} KB (High Quality JPEG)',
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

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  final double splitX;
  _HorizontalSplitClipper(this.splitX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, splitX, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalSplitClipper oldClipper) => oldClipper.splitX != splitX;
}
