import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/image_suite_service.dart';
import '../internal_file_picker_screen.dart';

class ExifRemoverScreen extends StatefulWidget {
  final String? initialImagePath;

  const ExifRemoverScreen({super.key, this.initialImagePath});

  @override
  State<ExifRemoverScreen> createState() => _ExifRemoverScreenState();
}

class _ExifRemoverScreenState extends State<ExifRemoverScreen> {
  String? _selectedImagePath;
  Uint8List? _imageBytes;
  ParsedExifData? _exifData;
  bool _isLoading = false;
  String? _errorMessage;

  // Metadata stripping state
  bool _isStripping = false;
  Uint8List? _cleanImageBytes;
  String? _savedCleanPath;

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
      if (!{'.jpg', '.jpeg', '.png', '.webp', '.tiff', '.heic', '.raw'}.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a photo file.')),
        );
        return;
      }
      _loadImage(path);
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _selectedImagePath = path;
      _isLoading = true;
      _errorMessage = null;
      _cleanImageBytes = null;
      _savedCleanPath = null;
    });

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final parsed = await ImageSuiteService.parseExifMetadata(bytes);

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _exifData = parsed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to read photo EXIF: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _stripMetadataAndSave() async {
    if (_imageBytes == null || _selectedImagePath == null) return;

    setState(() => _isStripping = true);

    try {
      final ext = p.extension(_selectedImagePath!);
      final cleanBytes = await ImageSuiteService.stripExifMetadata(
        inputBytes: _imageBytes!,
        fileExtension: ext,
      );

      final base = p.basenameWithoutExtension(_selectedImagePath!);
      final outPath = await ImageSuiteService.saveImage(
        bytes: cleanBytes,
        subFolder: 'NFylo_Clean',
        baseName: '${base}_sanitized',
        extension: ext.isEmpty ? 'jpg' : ext,
      );

      if (mounted) {
        setState(() {
          _cleanImageBytes = cleanBytes;
          _savedCleanPath = outPath;
          _isStripping = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved clean photo: ${p.basename(outPath)}'),
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
        setState(() => _isStripping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to strip metadata: $e')),
        );
      }
    }
  }

  void _shareCleanPhoto() {
    if (_savedCleanPath != null) {
      Share.shareXFiles([XFile(_savedCleanPath!)]);
    } else if (_cleanImageBytes != null) {
      final temp = p.join(Directory.systemTemp.path, 'clean_photo.jpg');
      File(temp).writeAsBytesSync(_cleanImageBytes!);
      Share.shareXFiles([XFile(temp)]);
    }
  }

  void _openGpsInMaps(GpsCoordinates gps) async {
    final uri = Uri.parse(gps.mapsUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      Clipboard.setData(ClipboardData(text: gps.coordinatesString));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Coordinates copied: ${gps.coordinatesString}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _imageBytes != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('EXIF Remover (Privacy)'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Select Photo',
            onPressed: _pickImageFile,
          ),
          if (_cleanImageBytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Clean Photo',
              onPressed: _shareCleanPhoto,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing EXIF & GPS metadata...'),
                ],
              ),
            )
          : hasImage
              ? _buildActiveExifView(theme)
              : _buildEmptyPickerView(theme),
      bottomNavigationBar: hasImage && _savedCleanPath == null
          ? _buildBottomActionBar(theme)
          : null,
    );
  }

  // --------------------------------------------------------------------------
  // Empty State: Select photo
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
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Broken.shield_slash,
                size: 64,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'EXIF Metadata Remover',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Photos taken with phones often contain sensitive private tags including your GPS location, camera serial numbers, and exact timestamps.\n\nInspect metadata and generate a clean, untraceable copy.',
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
              label: const Text('Select Photo to Inspect'),
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
  // Active EXIF View
  // --------------------------------------------------------------------------

  Widget _buildActiveExifView(ThemeData theme) {
    final exif = _exifData!;
    final origSize = _imageBytes?.length ?? 0;
    final totalTags = exif.tags.length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo Header Preview Card
          Container(
            padding: const EdgeInsets.all(12),
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
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.basename(_selectedImagePath!),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        FileUtils.formatBytes(origSize, 2),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _buildBadge(
                            totalTags > 0 ? '$totalTags EXIF Tags' : 'No EXIF Tags',
                            totalTags > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                            totalTags > 0 ? Colors.orange.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                          ),
                          if (exif.hasSensitiveGps)
                            _buildBadge(
                              'GPS Location Leaked',
                              Colors.redAccent,
                              Colors.red.withOpacity(0.15),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sanitized Success Banner
          if (_savedCleanPath != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade700, width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Metadata Completely Removed!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Clean file saved: ${p.basename(_savedCleanPath!)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.green),
                    tooltip: 'Share Clean Photo',
                    onPressed: _shareCleanPhoto,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // GPS Sensitive Alert Card
          if (exif.gps != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Sensitive GPS Location Detected',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Exact Coordinates: ${exif.gps!.coordinatesString}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  if (exif.gps!.altitude != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Altitude: ${exif.gps!.altitude!.toStringAsFixed(1)} meters',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _openGpsInMaps(exif.gps!),
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('View Coordinates on Map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Camera & Quick Info Card
          if (exif.cameraMake != null || exif.cameraModel != null || exif.dateTimeOriginal != null) ...[
            _buildSectionHeader(theme, 'Key Metadata Found'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
              ),
              child: Column(
                children: [
                  if (exif.cameraMake != null || exif.cameraModel != null)
                    _buildInfoRow('Camera Device', '${exif.cameraMake ?? ""} ${exif.cameraModel ?? ""}'.trim()),
                  if (exif.dateTimeOriginal != null) ...[
                    const Divider(height: 14),
                    _buildInfoRow('Capture Date', exif.dateTimeOriginal!),
                  ],
                  if (exif.software != null) ...[
                    const Divider(height: 14),
                    _buildInfoRow('Software / App', exif.software!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Detailed Tags List
          _buildSectionHeader(theme, 'All Extracted Tags (${exif.tags.length})'),
          if (exif.tags.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'No EXIF metadata found in this photo.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            ...exif.tags.map((tag) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: tag.isSensitive
                        ? Colors.redAccent.withOpacity(0.3)
                        : theme.dividerColor.withOpacity(0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        tag.key,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: tag.isSensitive ? Colors.redAccent : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Text(
                        tag.value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
      ],
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
        child: FilledButton.icon(
          onPressed: _isStripping ? null : _stripMetadataAndSave,
          icon: _isStripping
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.shield_outlined, size: 20),
          label: const Text('Strip All Metadata & Save Clean Photo'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
