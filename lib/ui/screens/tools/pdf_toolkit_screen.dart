import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/pdf_toolkit_service.dart';
import '../internal_file_picker_screen.dart';

class PdfToolkitScreen extends StatefulWidget {
  final String? initialPdfPath;

  const PdfToolkitScreen({super.key, this.initialPdfPath});

  @override
  State<PdfToolkitScreen> createState() => _PdfToolkitScreenState();
}

class _PdfToolkitScreenState extends State<PdfToolkitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 1. Merge State
  final List<String> _mergeFiles = [];

  // 2. Split State
  String? _splitFile;
  PdfInfo? _splitInfo;
  final TextEditingController _splitPagesController = TextEditingController();

  // 3. Rotate State
  String? _rotateFile;
  PdfInfo? _rotateInfo;
  int _rotateDegrees = 90;
  bool _rotateAllPages = true;
  final TextEditingController _rotatePagesController = TextEditingController();

  // 4. Watermark State
  String? _watermarkFile;
  PdfInfo? _watermarkInfo;
  final TextEditingController _watermarkTextController =
      TextEditingController(text: 'CONFIDENTIAL');
  double _watermarkOpacity = 0.25;
  double _watermarkFontSize = 42;
  double _watermarkAngle = -40;

  // 5. EPUB State
  String? _epubFile;
  PdfInfo? _epubInfo;
  final TextEditingController _epubTitleController = TextEditingController();
  final TextEditingController _epubAuthorController = TextEditingController();

  bool _isProcessing = false;
  String? _statusMessage;
  String? _lastExportedPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    if (widget.initialPdfPath != null) {
      _loadInitialFile(widget.initialPdfPath!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _splitPagesController.dispose();
    _rotatePagesController.dispose();
    _watermarkTextController.dispose();
    _epubTitleController.dispose();
    _epubAuthorController.dispose();
    super.dispose();
  }

  void _loadInitialFile(String path) {
    setState(() {
      _splitFile = path;
      _rotateFile = path;
      _watermarkFile = path;
      _epubFile = path;
    });
    _loadPdfInfo(path, 1);
    _loadPdfInfo(path, 2);
    _loadPdfInfo(path, 3);
    _loadPdfInfo(path, 4);
  }

  Future<void> _loadPdfInfo(String path, int targetTab) async {
    try {
      final info = await PdfToolkitService.getPdfInfo(path);
      if (mounted) {
        setState(() {
          if (targetTab == 1) _splitInfo = info;
          if (targetTab == 2) _rotateInfo = info;
          if (targetTab == 3) _watermarkInfo = info;
          if (targetTab == 4) {
            _epubInfo = info;
            _epubTitleController.text = info.title;
            _epubAuthorController.text = info.author;
          }
        });
      }
    } catch (_) {}
  }

  Future<List<String>?> _pickPdfFiles({bool allowMultiple = false}) async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      final valid = picked.where((pPath) => p.extension(pPath).toLowerCase() == '.pdf').toList();
      if (valid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select PDF file(s).')),
          );
        }
        return null;
      }
      return allowMultiple ? valid : [valid.first];
    }
    return null;
  }

  void _showSuccessSnackbar(String outPath) {
    setState(() => _lastExportedPath = outPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: ${p.basename(outPath)}'),
          backgroundColor: Colors.green.shade700,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(outPath)]),
          ),
        ),
      );
    }
  }

  void _showErrorSnackbar(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  Future<void> _runMerge() async {
    if (_mergeFiles.length < 2) {
      _showErrorSnackbar('Add at least 2 PDF files to merge.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Merging ${_mergeFiles.length} PDF files...';
    });

    try {
      final outPath = await PdfToolkitService.mergePdfs(pdfPaths: _mergeFiles);
      _showSuccessSnackbar(outPath);
    } catch (e) {
      _showErrorSnackbar('Merge failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runSplit() async {
    if (_splitFile == null || _splitInfo == null) return;

    final input = _splitPagesController.text.trim();
    if (input.isEmpty) {
      _showErrorSnackbar('Specify page numbers to extract (e.g. 1-3, 5).');
      return;
    }

    final indices = _parsePageIndices(input, _splitInfo!.pageCount);
    if (indices.isEmpty) {
      _showErrorSnackbar('Invalid page range entered.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Extracting ${indices.length} pages...';
    });

    try {
      final outPath = await PdfToolkitService.splitPdf(
        inputPath: _splitFile!,
        pageIndices: indices,
      );
      _showSuccessSnackbar(outPath);
    } catch (e) {
      _showErrorSnackbar('Split failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runRotate() async {
    if (_rotateFile == null || _rotateInfo == null) return;

    List<int> indices;
    if (_rotateAllPages) {
      indices = List.generate(_rotateInfo!.pageCount, (i) => i);
    } else {
      indices = _parsePageIndices(
        _rotatePagesController.text.trim(),
        _rotateInfo!.pageCount,
      );
      if (indices.isEmpty) {
        _showErrorSnackbar('Enter valid pages to rotate.');
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Rotating pages by $_rotateDegrees°...';
    });

    try {
      final outPath = await PdfToolkitService.rotatePdfPages(
        inputPath: _rotateFile!,
        pageIndices: indices,
        degrees: _rotateDegrees,
      );
      _showSuccessSnackbar(outPath);
    } catch (e) {
      _showErrorSnackbar('Rotate failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runWatermark() async {
    if (_watermarkFile == null) return;
    final text = _watermarkTextController.text.trim();
    if (text.isEmpty) {
      _showErrorSnackbar('Please enter watermark text.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Applying diagonal text watermark...';
    });

    try {
      final outPath = await PdfToolkitService.addTextWatermark(
        inputPath: _watermarkFile!,
        watermarkText: text,
        opacity: _watermarkOpacity,
        fontSize: _watermarkFontSize,
        rotationDegrees: _watermarkAngle,
      );
      _showSuccessSnackbar(outPath);
    } catch (e) {
      _showErrorSnackbar('Watermark failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runEpubConversion() async {
    if (_epubFile == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Extracting text and building reflowable EPUB...';
    });

    try {
      final outPath = await PdfToolkitService.convertPdfToEpub(
        inputPath: _epubFile!,
        bookTitle: _epubTitleController.text.trim(),
        author: _epubAuthorController.text.trim(),
      );
      _showSuccessSnackbar(outPath);
    } catch (e) {
      _showErrorSnackbar('EPUB conversion failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<int> _parsePageIndices(String text, int maxPages) {
    final result = <int>{};
    final parts = text.split(RegExp(r'[,; ]+'));

    for (final part in parts) {
      if (part.contains('-')) {
        final range = part.split('-');
        if (range.length == 2) {
          final start = int.tryParse(range[0].trim());
          final end = int.tryParse(range[1].trim());
          if (start != null && end != null) {
            for (int i = start; i <= end; i++) {
              if (i >= 1 && i <= maxPages) {
                result.add(i - 1); // 0-indexed
              }
            }
          }
        }
      } else {
        final pNum = int.tryParse(part.trim());
        if (pNum != null && pNum >= 1 && pNum <= maxPages) {
          result.add(pNum - 1);
        }
      }
    }

    final sorted = result.toList()..sort();
    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Build UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Toolkit & EPUB Converter'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Merge PDFs'),
            Tab(text: 'Split / Extract'),
            Tab(text: 'Rotate Pages'),
            Tab(text: 'Watermark'),
            Tab(text: 'PDF to EPUB'),
          ],
        ),
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage ?? 'Processing PDF...'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMergeTab(theme),
                _buildSplitTab(theme),
                _buildRotateTab(theme),
                _buildWatermarkTab(theme),
                _buildEpubTab(theme),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Merge PDFs
  // ---------------------------------------------------------------------------

  Widget _buildMergeTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Documents to Merge (${_mergeFiles.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final picked = await _pickPdfFiles(allowMultiple: true);
                  if (picked != null) {
                    setState(() {
                      for (final p in picked) {
                        if (!_mergeFiles.contains(p)) _mergeFiles.add(p);
                      }
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mergeFiles.isEmpty)
            _buildEmptyPlaceholder(
              theme,
              icon: Icons.picture_as_pdf_outlined,
              title: 'No PDFs Selected',
              subtitle: 'Select 2 or more PDF documents to merge them into a single consolidated file.',
            )
          else ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mergeFiles.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) newIndex -= 1;
                  final item = _mergeFiles.removeAt(oldIndex);
                  _mergeFiles.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final filePath = _mergeFiles[index];
                return Card(
                  key: ValueKey(filePath),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      p.basename(filePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(filePath, style: const TextStyle(fontSize: 11)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                          onPressed: () {
                            setState(() => _mergeFiles.removeAt(index));
                          },
                        ),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runMerge,
                icon: const Icon(Icons.call_merge),
                label: const Text('Merge into Single PDF'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Split / Extract Pages
  // ---------------------------------------------------------------------------

  Widget _buildSplitTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceFilePicker(
            theme,
            selectedPath: _splitFile,
            info: _splitInfo,
            onPick: () async {
              final picked = await _pickPdfFiles();
              if (picked != null) {
                setState(() {
                  _splitFile = picked.first;
                  _splitInfo = null;
                });
                _loadPdfInfo(picked.first, 1);
              }
            },
          ),
          if (_splitInfo != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Pages to Extract',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _splitPagesController,
              decoration: InputDecoration(
                hintText: 'e.g. 1-3, 5, 8-10',
                helperText: 'Available pages: 1 to ${_splitInfo!.pageCount}',
                prefixIcon: const Icon(Icons.format_list_numbered),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('First Page (1)'),
                  onPressed: () => _splitPagesController.text = '1',
                ),
                if (_splitInfo!.pageCount > 1)
                  ActionChip(
                    label: Text('First 3 Pages (1-3)'),
                    onPressed: () => _splitPagesController.text = '1-3',
                  ),
                ActionChip(
                  label: Text('Last Page (${_splitInfo!.pageCount})'),
                  onPressed: () => _splitPagesController.text = '${_splitInfo!.pageCount}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runSplit,
                icon: const Icon(Icons.call_split),
                label: const Text('Extract Selected Pages'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Rotate Pages
  // ---------------------------------------------------------------------------

  Widget _buildRotateTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceFilePicker(
            theme,
            selectedPath: _rotateFile,
            info: _rotateInfo,
            onPick: () async {
              final picked = await _pickPdfFiles();
              if (picked != null) {
                setState(() {
                  _rotateFile = picked.first;
                  _rotateInfo = null;
                });
                _loadPdfInfo(picked.first, 2);
              }
            },
          ),
          if (_rotateInfo != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Rotation Angle',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [90, 180, 270].map((deg) {
                final isSelected = _rotateDegrees == deg;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('$deg°'),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _rotateDegrees = deg);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rotate All Pages'),
              subtitle: Text('Apply rotation to all ${_rotateInfo!.pageCount} pages'),
              value: _rotateAllPages,
              onChanged: (val) => setState(() => _rotateAllPages = val),
            ),
            if (!_rotateAllPages) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _rotatePagesController,
                decoration: InputDecoration(
                  labelText: 'Specific Pages',
                  hintText: 'e.g. 1, 3, 5-7',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runRotate,
                icon: const Icon(Icons.rotate_right),
                label: Text('Rotate Pages ($_rotateDegrees°)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Add Text Watermark
  // ---------------------------------------------------------------------------

  Widget _buildWatermarkTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceFilePicker(
            theme,
            selectedPath: _watermarkFile,
            info: _watermarkInfo,
            onPick: () async {
              final picked = await _pickPdfFiles();
              if (picked != null) {
                setState(() {
                  _watermarkFile = picked.first;
                  _watermarkInfo = null;
                });
                _loadPdfInfo(picked.first, 3);
              }
            },
          ),
          if (_watermarkInfo != null) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _watermarkTextController,
              decoration: InputDecoration(
                labelText: 'Watermark Text',
                hintText: 'CONFIDENTIAL, DRAFT, DO NOT COPY',
                prefixIcon: const Icon(Icons.text_fields),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Opacity: ${(_watermarkOpacity * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Slider(
              value: _watermarkOpacity,
              min: 0.1,
              max: 0.8,
              divisions: 14,
              onChanged: (val) => setState(() => _watermarkOpacity = val),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Font Size: ${_watermarkFontSize.round()} pt',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Angle: ${_watermarkAngle.round()}°',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _watermarkFontSize,
                    min: 20,
                    max: 72,
                    divisions: 13,
                    onChanged: (val) => setState(() => _watermarkFontSize = val),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _watermarkAngle,
                    min: -90,
                    max: 90,
                    divisions: 18,
                    onChanged: (val) => setState(() => _watermarkAngle = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runWatermark,
                icon: const Icon(Icons.branding_watermark_outlined),
                label: const Text('Apply Text Watermark'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 5: PDF to EPUB Converter
  // ---------------------------------------------------------------------------

  Widget _buildEpubTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceFilePicker(
            theme,
            selectedPath: _epubFile,
            info: _epubInfo,
            onPick: () async {
              final picked = await _pickPdfFiles();
              if (picked != null) {
                setState(() {
                  _epubFile = picked.first;
                  _epubInfo = null;
                });
                _loadPdfInfo(picked.first, 4);
              }
            },
          ),
          if (_epubInfo != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_stories, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Extracts text from PDF pages and packages it into a standard, reflowable EPUB book for e-readers.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _epubTitleController,
              decoration: InputDecoration(
                labelText: 'Book Title',
                prefixIcon: const Icon(Icons.book_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _epubAuthorController,
              decoration: InputDecoration(
                labelText: 'Author Name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runEpubConversion,
                icon: const Icon(Icons.book),
                label: const Text('Convert to Reflowable .EPUB'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Components
  // ---------------------------------------------------------------------------

  Widget _buildSourceFilePicker(
    ThemeData theme, {
    required String? selectedPath,
    required PdfInfo? info,
    required VoidCallback onPick,
  }) {
    if (selectedPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Select a PDF Document',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a PDF from your device storage to process.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose PDF'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(selectedPath),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (info != null)
                  Text(
                    '${info.pageCount} Pages • ${FileUtils.formatBytes(info.fileSizeBytes, 1)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  )
                else
                  const Text('Analyzing document...', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Change PDF',
            onPressed: onPick,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
