import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/utils.dart';
import '../../../services/document_scanner_service.dart';

class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<ScannedPage> _pages = [];

  ScannerFilter _defaultFilter = ScannerFilter.blackAndWhite;
  int _selectedPageIndex = 0;
  bool _isProcessing = false;
  String? _statusMessage;
  String? _exportedPdfPath;

  final TextEditingController _titleController =
      TextEditingController(text: 'Scanned Document');

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );

      if (photo != null) {
        await _addPhoto(photo.path);
      }
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> photos = await _picker.pickMultiImage(
        imageQuality: 95,
      );

      for (final photo in photos) {
        await _addPhoto(photo.path);
      }
    } catch (e) {
      _showError('Gallery picker error: $e');
    }
  }

  Future<void> _addPhoto(String imagePath) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Enhancing scanned page...';
    });

    try {
      final rawBytes = await File(imagePath).readAsBytes();
      final decoded = await decodeImageFromList(rawBytes);

      final processed = await DocumentScannerService.processPage(
        bytes: rawBytes,
        filter: _defaultFilter,
        rotationDegrees: 0,
      );

      final page = ScannedPage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        originalBytes: rawBytes,
        processedBytes: processed,
        filter: _defaultFilter,
        rotationDegrees: 0,
        width: decoded.width,
        height: decoded.height,
      );

      setState(() {
        _pages.add(page);
        _selectedPageIndex = _pages.length - 1;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Failed to process image: $e');
    }
  }

  Future<void> _updatePageFilter(int index, ScannerFilter filter) async {
    final page = _pages[index];
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Applying filter...';
    });

    try {
      final processed = await DocumentScannerService.processPage(
        bytes: page.originalBytes,
        filter: filter,
        rotationDegrees: page.rotationDegrees,
      );

      setState(() {
        _pages[index] = page.copyWith(
          processedBytes: processed,
          filter: filter,
        );
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Filter error: $e');
    }
  }

  Future<void> _rotatePage(int index) async {
    final page = _pages[index];
    final nextRot = (page.rotationDegrees + 90) % 360;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Rotating page...';
    });

    try {
      final processed = await DocumentScannerService.processPage(
        bytes: page.originalBytes,
        filter: page.filter,
        rotationDegrees: nextRot,
      );

      setState(() {
        _pages[index] = page.copyWith(
          processedBytes: processed,
          rotationDegrees: nextRot,
        );
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Rotation error: $e');
    }
  }

  Future<void> _exportAsPdf() async {
    if (_pages.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Generating consolidated PDF document...';
    });

    try {
      final processedBytesList = _pages.map((p) => p.processedBytes).toList();
      final outPath = await DocumentScannerService.generatePdf(
        pages: processedBytesList,
        documentTitle: _titleController.text.trim(),
      );

      setState(() {
        _exportedPdfPath = outPath;
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved PDF: ${p.basename(outPath)}'),
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
      setState(() => _isProcessing = false);
      _showError('Failed to generate PDF: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Scanner'),
        actions: [
          if (_pages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Export & Share PDF',
              onPressed: _exportAsPdf,
            ),
        ],
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage ?? 'Processing...'),
                ],
              ),
            )
          : _pages.isEmpty
              ? _buildEmptyState(theme)
              : _buildScannerWorkspace(theme),
      bottomNavigationBar: _pages.isNotEmpty ? _buildBottomControls(theme) : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.document_scanner,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Document Scanner',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Snap clear pictures of paper documents, receipts, or notes.\nApplies contrast enhancement, binarization, and groups pages into a clean PDF.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _captureFromCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(width: 14),
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Active Scanner Workspace
  // ---------------------------------------------------------------------------

  Widget _buildScannerWorkspace(ThemeData theme) {
    final activePage = _pages[_selectedPageIndex];

    return Column(
      children: [
        // Top Toolbar: Page counter & individual page actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${_selectedPageIndex + 1} of ${_pages.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.rotate_right),
                    tooltip: 'Rotate 90°',
                    onPressed: () => _rotatePage(_selectedPageIndex),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Delete Page',
                    onPressed: () {
                      setState(() {
                        _pages.removeAt(_selectedPageIndex);
                        if (_selectedPageIndex >= _pages.length) {
                          _selectedPageIndex = (_pages.length - 1).clamp(0, 999);
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Main Page Image Preview
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: Image.memory(
                activePage.processedBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // Filter Selection Chips for current page
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ScannerFilter.values.map((filter) {
              final isSelected = activePage.filter == filter;
              String label = 'Original';
              IconData icon = Icons.photo;
              if (filter == ScannerFilter.blackAndWhite) {
                label = 'B&W Scan';
                icon = Icons.contrast;
              } else if (filter == ScannerFilter.grayscale) {
                label = 'Grayscale';
                icon = Icons.filter_b_and_w;
              } else if (filter == ScannerFilter.enhancedColor) {
                label = 'Enhanced';
                icon = Icons.auto_awesome;
              }

              return ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                selected: isSelected,
                onSelected: (val) {
                  if (val) _updatePageFilter(_selectedPageIndex, filter);
                },
              );
            }).toList(),
          ),
        ),

        // Horizontal Page Strip / Reordering Thumbnails
        Container(
          height: 80,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _pages.length + 1,
            itemBuilder: (context, index) {
              if (index == _pages.length) {
                // Add Page Button
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      tooltip: 'Snap Next Page',
                      onPressed: _captureFromCamera,
                    ),
                  ),
                );
              }

              final page = _pages[index];
              final isSelected = _selectedPageIndex == index;

              return GestureDetector(
                onTap: () => setState(() => _selectedPageIndex = index),
                child: Container(
                  width: 55,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(page.processedBytes, fit: BoxFit.cover),
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom Save & Action Sheet
  // ---------------------------------------------------------------------------

  Widget _buildBottomControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                onPressed: _exportAsPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                label: Text(
                  _exportedPdfPath != null
                      ? 'Saved (${_pages.length} Pages)'
                      : 'Save as PDF (${_pages.length} Pages)',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Snap Another Page',
              onPressed: _captureFromCamera,
            ),
          ],
        ),
      ),
    );
  }
}
