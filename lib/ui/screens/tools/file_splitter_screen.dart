import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/folder_share_service.dart';
import '../internal_file_picker_screen.dart';

class FileSplitterScreen extends StatefulWidget {
  final String? initialFilePath;
  const FileSplitterScreen({super.key, this.initialFilePath});

  @override
  State<FileSplitterScreen> createState() => _FileSplitterScreenState();
}

class _FileSplitterScreenState extends State<FileSplitterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Split state
  String? _splitFilePath;
  int _selectedChunkSizeMB = 50;
  final TextEditingController _customSizeController = TextEditingController();
  bool _isCustomSize = false;
  bool _deleteSourceAfterSplit = false;
  bool _isSplitting = false;
  double _splitProgress = 0.0;
  int _currentPartSplitting = 0;
  int _totalPartsToSplit = 0;
  String? _splitSuccessMessage;

  // Join state
  String? _joinFirstPartPath;
  List<File> _detectedParts = [];
  int _totalJoinBytes = 0;
  String _joinedOutputFilename = '';
  bool _deleteChunksAfterJoin = false;
  bool _isJoining = false;
  double _joinProgress = 0.0;
  int _currentPartJoining = 0;
  String? _joinedResultPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialFilePath != null) {
      final ext = p.extension(widget.initialFilePath!).toLowerCase();
      if (RegExp(r'^\.\d{3}$').hasMatch(ext)) {
        _tabController.index = 1;
        _analyzeJoinParts(widget.initialFilePath!);
      } else {
        _splitFilePath = widget.initialFilePath;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customSizeController.dispose();
    super.dispose();
  }

  Future<void> _pickSplitFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _splitFilePath = picked.first;
        _splitSuccessMessage = null;
      });
    }
  }

  Future<void> _pickJoinFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );
    if (picked != null && picked.isNotEmpty) {
      _analyzeJoinParts(picked.first);
    }
  }

  void _analyzeJoinParts(String pickedPath) {
    final file = File(pickedPath);
    if (!file.existsSync()) return;

    final dir = file.parent;
    final ext = p.extension(pickedPath);
    String baseName;
    if (RegExp(r'^\.\d{3}$').hasMatch(ext)) {
      baseName = pickedPath.substring(0, pickedPath.length - 4);
    } else {
      baseName = pickedPath;
    }

    final parts = <File>[];
    int partIndex = 1;
    int totalBytes = 0;

    while (true) {
      final partExt = partIndex.toString().padLeft(3, '0');
      final candidate = File('$baseName.$partExt');
      if (candidate.existsSync()) {
        parts.add(candidate);
        totalBytes += candidate.lengthSync();
        partIndex++;
      } else {
        break;
      }
    }

    setState(() {
      _joinFirstPartPath = pickedPath;
      _detectedParts = parts;
      _totalJoinBytes = totalBytes;
      _joinedOutputFilename = p.basename(baseName);
      _joinedResultPath = null;
    });
  }

  int get _effectiveChunkSizeMB {
    if (_isCustomSize) {
      return int.tryParse(_customSizeController.text) ?? 50;
    }
    return _selectedChunkSizeMB;
  }

  Future<void> _startSplitting() async {
    if (_splitFilePath == null) return;
    final file = File(_splitFilePath!);
    if (!file.existsSync()) return;

    final chunkMB = _effectiveChunkSizeMB;
    if (chunkMB <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chunk size must be greater than 0 MB')),
      );
      return;
    }

    final chunkBytes = chunkMB * 1024 * 1024;
    final totalBytes = file.lengthSync();
    final totalParts = (totalBytes / chunkBytes).ceil();

    if (totalParts <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is smaller than the chosen chunk size')),
      );
      return;
    }

    setState(() {
      _isSplitting = true;
      _splitProgress = 0.0;
      _totalPartsToSplit = totalParts;
      _currentPartSplitting = 1;
      _splitSuccessMessage = null;
    });

    try {
      final inRaf = await file.open(mode: FileMode.read);
      const bufferSize = 64 * 1024; // 64 KB buffer
      int bytesReadTotal = 0;

      for (int part = 1; part <= totalParts; part++) {
        if (!mounted) break;
        setState(() => _currentPartSplitting = part);

        final partExt = part.toString().padLeft(3, '0');
        final partFile = File('${file.path}.$partExt');
        final outRaf = await partFile.open(mode: FileMode.write);

        int bytesWrittenForChunk = 0;

        while (bytesWrittenForChunk < chunkBytes && bytesReadTotal < totalBytes) {
          final toRead = (chunkBytes - bytesWrittenForChunk) < bufferSize
              ? (chunkBytes - bytesWrittenForChunk)
              : bufferSize;

          final buf = await inRaf.read(toRead);
          if (buf.isEmpty) break;

          await outRaf.writeFrom(buf);
          bytesWrittenForChunk += buf.length;
          bytesReadTotal += buf.length;

          if (mounted) {
            setState(() {
              _splitProgress = bytesReadTotal / totalBytes;
            });
          }
        }

        await outRaf.close();
      }

      await inRaf.close();

      if (_deleteSourceAfterSplit) {
        await file.delete();
      }

      context.read<FileManagerProvider>().updateStorageSpace();

      if (mounted) {
        setState(() {
          _isSplitting = false;
          _splitSuccessMessage = 'Successfully split into $totalParts parts!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSplitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error splitting file: $e')),
        );
      }
    }
  }

  Future<void> _startJoining() async {
    if (_detectedParts.isEmpty) return;

    final parentDir = _detectedParts.first.parent;
    String outPath = p.join(parentDir.path, _joinedOutputFilename);

    if (File(outPath).existsSync()) {
      final base = p.basenameWithoutExtension(_joinedOutputFilename);
      final ext = p.extension(_joinedOutputFilename);
      outPath = p.join(parentDir.path, '${base}_merged$ext');
    }

    setState(() {
      _isJoining = true;
      _joinProgress = 0.0;
      _currentPartJoining = 1;
      _joinedResultPath = null;
    });

    try {
      final outFile = File(outPath);
      final outRaf = await outFile.open(mode: FileMode.write);
      int bytesWrittenTotal = 0;
      const bufferSize = 64 * 1024;

      for (int i = 0; i < _detectedParts.length; i++) {
        if (!mounted) break;
        setState(() => _currentPartJoining = i + 1);

        final partFile = _detectedParts[i];
        final inRaf = await partFile.open(mode: FileMode.read);

        while (true) {
          final buf = await inRaf.read(bufferSize);
          if (buf.isEmpty) break;
          await outRaf.writeFrom(buf);
          bytesWrittenTotal += buf.length;

          if (mounted && _totalJoinBytes > 0) {
            setState(() {
              _joinProgress = bytesWrittenTotal / _totalJoinBytes;
            });
          }
        }
        await inRaf.close();
      }

      await outRaf.close();

      if (_deleteChunksAfterJoin) {
        for (final pFile in _detectedParts) {
          try {
            await pFile.delete();
          } catch (_) {}
        }
      }

      context.read<FileManagerProvider>().updateStorageSpace();

      if (mounted) {
        setState(() {
          _isJoining = false;
          _joinedResultPath = outPath;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining chunks: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('File Splitter & Joiner'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Broken.scissor), text: 'Split File'),
            Tab(icon: Icon(Broken.add_circle), text: 'Join Chunks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSplitTab(theme),
          _buildJoinTab(theme),
        ],
      ),
    );
  }

  Widget _buildSplitTab(ThemeData theme) {
    final hasFile = _splitFilePath != null && File(_splitFilePath!).existsSync();
    final fileSize = hasFile ? File(_splitFilePath!).lengthSync() : 0;
    final chunkBytes = _effectiveChunkSizeMB * 1024 * 1024;
    final estimatedParts = hasFile && chunkBytes > 0 ? (fileSize / chunkBytes).ceil() : 0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Select File Card
          _buildFilePickerCard(
            theme: theme,
            title: 'File to Split',
            filePath: _splitFilePath,
            onPick: _pickSplitFile,
            icon: Broken.scissor,
            accentColor: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),

          // Chunk Size Selector
          Text(
            'Chunk Size',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildSizeChip(10, '10 MB'),
                const SizedBox(width: 8),
                _buildSizeChip(25, '25 MB'),
                const SizedBox(width: 8),
                _buildSizeChip(50, '50 MB'),
                const SizedBox(width: 8),
                _buildSizeChip(100, '100 MB'),
                const SizedBox(width: 8),
                _buildCustomSizeChip(),
              ],
            ),
          ),

          if (_isCustomSize) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customSizeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter chunk size in MB (e.g. 75)',
                suffixText: 'MB',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],

          const SizedBox(height: 16),

          // Estimated parts preview
          if (hasFile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Broken.info_circle, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Will produce $estimatedParts parts (~${FileUtils.formatBytes(chunkBytes, 0)} each)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Delete Source Switch
          SwitchListTile(
            value: _deleteSourceAfterSplit,
            onChanged: (val) => setState(() => _deleteSourceAfterSplit = val),
            title: const Text('Delete original file after splitting', style: TextStyle(fontSize: 13.5)),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),

          // Progress
          if (_isSplitting) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _splitProgress > 0 ? _splitProgress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Writing part $_currentPartSplitting of $_totalPartsToSplit... ${(_splitProgress * 100).toInt()}%',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
          ],

          // Split Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: (!hasFile || _isSplitting) ? null : _startSplitting,
              icon: const Icon(Broken.scissor, size: 20),
              label: const Text('Split File Now', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // Success banner
          if (_splitSuccessMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _splitSuccessMessage!,
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJoinTab(ThemeData theme) {
    final hasParts = _detectedParts.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Select Chunks Card
          _buildFilePickerCard(
            theme: theme,
            title: 'Select First Part (.001)',
            filePath: _joinFirstPartPath,
            onPick: _pickJoinFile,
            icon: Broken.add_circle,
            accentColor: const Color(0xFF10B981),
          ),
          const SizedBox(height: 20),

          // Detected Parts Overview
          if (hasParts) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Output: $_joinedOutputFilename',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          FileUtils.formatBytes(_totalJoinBytes, 1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Found ${_detectedParts.length} consecutive parts:',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _detectedParts.map((f) {
                      return Chip(
                        label: Text(p.extension(f.path), style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Delete Chunks switch
            SwitchListTile(
              value: _deleteChunksAfterJoin,
              onChanged: (val) => setState(() => _deleteChunksAfterJoin = val),
              title: const Text('Delete chunk files after successful merge', style: TextStyle(fontSize: 13.5)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
          ],

          // Join Progress
          if (_isJoining) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _joinProgress > 0 ? _joinProgress : null,
                minHeight: 8,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Merging part $_currentPartJoining of ${_detectedParts.length}... ${(_joinProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 16),
          ],

          // Join Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: (!hasParts || _isJoining) ? null : _startJoining,
              icon: const Icon(Broken.add_circle, size: 20),
              label: const Text('Join Chunks into Original File', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // Success result card
          if (_joinedResultPath != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Text('Chunks Merged Successfully!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_joinedResultPath!, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => context.read<FileManagerProvider>().openFile(context, _joinedResultPath!),
                        icon: const Icon(Broken.eye, size: 16),
                        label: const Text('Open File'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => FolderShareService.sharePaths(context, [_joinedResultPath!]),
                        icon: const Icon(Broken.share, size: 16),
                        label: const Text('Share'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSizeChip(int sizeMB, String label) {
    final isSelected = !_isCustomSize && _selectedChunkSizeMB == sizeMB;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _isCustomSize = false;
            _selectedChunkSizeMB = sizeMB;
          });
        }
      },
    );
  }

  Widget _buildCustomSizeChip() {
    return ChoiceChip(
      label: const Text('Custom'),
      selected: _isCustomSize,
      onSelected: (val) {
        setState(() {
          _isCustomSize = val;
        });
      },
    );
  }

  Widget _buildFilePickerCard({
    required ThemeData theme,
    required String title,
    required String? filePath,
    required VoidCallback onPick,
    required IconData icon,
    required Color accentColor,
  }) {
    final hasFile = filePath != null && File(filePath).existsSync();
    final fileName = hasFile ? p.basename(filePath) : 'No file selected';
    final fileSize = hasFile ? FileUtils.formatBytes(File(filePath).lengthSync(), 1) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasFile) ...[
                  const SizedBox(height: 2),
                  Text(
                    fileSize,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onPick,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(hasFile ? 'Change' : 'Select'),
          ),
        ],
      ),
    );
  }
}
