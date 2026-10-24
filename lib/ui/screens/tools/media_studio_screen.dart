import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/media_studio_service.dart';
import '../internal_file_picker_screen.dart';

class MediaStudioScreen extends StatefulWidget {
  final String? initialMediaPath;

  const MediaStudioScreen({super.key, this.initialMediaPath});

  @override
  State<MediaStudioScreen> createState() => _MediaStudioScreenState();
}

class _MediaStudioScreenState extends State<MediaStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected Media
  String? _selectedVideoPath;
  double _videoDurationMs = 0.0;
  int _videoSizeBytes = 0;

  String? _selectedAudioPath;
  double _audioDurationMs = 0.0;
  int _audioSizeBytes = 0;

  // Compress Settings
  VideoCompressionQuality _compressQuality = VideoCompressionQuality.balanced;

  // Trim Video Settings
  final TextEditingController _trimVideoStartController =
      TextEditingController(text: '00:00:00');
  final TextEditingController _trimVideoEndController =
      TextEditingController(text: '00:00:30');
  bool _fastTrim = true;

  // Extract Audio Settings
  String _extractTargetFormat = 'mp3';

  // Audio Convert / Trim Settings
  String _audioTargetFormat = 'mp3';
  final TextEditingController _trimAudioStartController =
      TextEditingController(text: '');
  final TextEditingController _trimAudioEndController =
      TextEditingController(text: '');

  // Progress & Execution State
  bool _isRunning = false;
  double _progress = 0.0;
  String _currentStep = '';
  final List<String> _logs = [];
  bool _showLogs = false;
  String? _lastOutputFile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.initialMediaPath != null) {
      _loadInitialMedia(widget.initialMediaPath!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _trimVideoStartController.dispose();
    _trimVideoEndController.dispose();
    _trimAudioStartController.dispose();
    _trimAudioEndController.dispose();
    super.dispose();
  }

  void _loadInitialMedia(String path) {
    final ext = p.extension(path).toLowerCase();
    if ({'.mp4', '.mkv', '.mov', '.avi', '.webm', '.3gp'}.contains(ext)) {
      _selectVideo(path);
    } else if ({'.mp3', '.m4a', '.wav', '.flac', '.ogg', '.aac'}.contains(ext)) {
      _selectAudio(path);
      _tabController.index = 3;
    }
  }

  Future<void> _selectVideo(String path) async {
    setState(() {
      _selectedVideoPath = path;
      _lastOutputFile = null;
    });

    try {
      final file = File(path);
      final size = await file.length();
      final duration = await MediaStudioService.getMediaDurationMs(path);

      if (mounted) {
        setState(() {
          _videoSizeBytes = size;
          _videoDurationMs = duration;
          _trimVideoEndController.text = _formatMsToTime(duration);
        });
      }
    } catch (_) {}
  }

  Future<void> _selectAudio(String path) async {
    setState(() {
      _selectedAudioPath = path;
      _lastOutputFile = null;
    });

    try {
      final file = File(path);
      final size = await file.length();
      final duration = await MediaStudioService.getMediaDurationMs(path);

      if (mounted) {
        setState(() {
          _audioSizeBytes = size;
          _audioDurationMs = duration;
          _trimAudioStartController.text = '00:00:00';
          _trimAudioEndController.text = _formatMsToTime(duration);
        });
      }
    } catch (_) {}
  }

  Future<String?> _pickFile({required bool isVideo}) async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      final path = picked.first;
      final ext = p.extension(path).toLowerCase();
      final videoExts = {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.3gp', '.flv'};
      final audioExts = {'.mp3', '.m4a', '.wav', '.flac', '.ogg', '.aac', '.opus', '.wma'};

      if (isVideo && !videoExts.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a video file.')),
        );
        return null;
      } else if (!isVideo && !audioExts.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an audio file.')),
        );
        return null;
      }
      return path;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Operation Execution Handlers
  // ---------------------------------------------------------------------------

  Future<void> _runCompression() async {
    if (_selectedVideoPath == null) return;

    _startTask('Compressing video...');
    try {
      final out = await MediaStudioService.compressVideo(
        inputPath: _selectedVideoPath!,
        quality: _compressQuality,
        onProgress: (p) => setState(() => _progress = p),
        onLog: (msg) => _appendLog(msg),
      );
      _finishTask(out);
    } catch (e) {
      _failTask('$e');
    }
  }

  Future<void> _runTrimVideo() async {
    if (_selectedVideoPath == null) return;

    final start = _trimVideoStartController.text.trim();
    final end = _trimVideoEndController.text.trim();

    _startTask('Trimming video timeline...');
    try {
      final out = await MediaStudioService.trimVideo(
        inputPath: _selectedVideoPath!,
        startTime: start,
        endTime: end,
        fastCopy: _fastTrim,
        onProgress: (p) => setState(() => _progress = p),
        onLog: (msg) => _appendLog(msg),
      );
      _finishTask(out);
    } catch (e) {
      _failTask('$e');
    }
  }

  Future<void> _runExtractAudio() async {
    if (_selectedVideoPath == null) return;

    _startTask('Extracting audio track...');
    try {
      final out = await MediaStudioService.extractAudio(
        inputPath: _selectedVideoPath!,
        targetFormat: _extractTargetFormat,
        onProgress: (p) => setState(() => _progress = p),
        onLog: (msg) => _appendLog(msg),
      );
      _finishTask(out);
    } catch (e) {
      _failTask('$e');
    }
  }

  Future<void> _runConvertOrTrimAudio() async {
    if (_selectedAudioPath == null) return;

    final start = _trimAudioStartController.text.trim();
    final end = _trimAudioEndController.text.trim();

    _startTask('Processing audio...');
    try {
      final out = await MediaStudioService.trimOrConvertAudio(
        inputPath: _selectedAudioPath!,
        targetFormat: _audioTargetFormat,
        startTime: start.isNotEmpty ? start : null,
        endTime: end.isNotEmpty ? end : null,
        onProgress: (p) => setState(() => _progress = p),
        onLog: (msg) => _appendLog(msg),
      );
      _finishTask(out);
    } catch (e) {
      _failTask('$e');
    }
  }

  void _startTask(String step) {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _currentStep = step;
      _logs.clear();
      _lastOutputFile = null;
    });
  }

  void _finishTask(String outputPath) {
    setState(() {
      _isRunning = false;
      _progress = 1.0;
      _lastOutputFile = outputPath;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Media saved: ${p.basename(outputPath)}'),
          backgroundColor: Colors.green.shade700,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(outputPath)]),
          ),
        ),
      );
    }
  }

  void _failTask(String error) {
    setState(() => _isRunning = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _appendLog(String line) {
    if (_logs.length > 300) _logs.removeAt(0);
    _logs.add(line);
  }

  String _formatMsToTime(double ms) {
    final totalSec = (ms / 1000).floor();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio & Video Studio'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Compress Video'),
            Tab(text: 'Trim Video'),
            Tab(text: 'Extract Audio'),
            Tab(text: 'Audio Studio'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Active Processing / Progress Banner
          if (_isRunning) _buildProgressCard(theme),

          // Result Card if completed
          if (_lastOutputFile != null && !_isRunning) _buildOutputCard(theme),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCompressTab(theme),
                _buildTrimVideoTab(theme),
                _buildExtractAudioTab(theme),
                _buildAudioStudioTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progress & Output Cards
  // ---------------------------------------------------------------------------

  Widget _buildProgressCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _currentStep,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _showLogs = !_showLogs),
                icon: Icon(
                  _showLogs ? Icons.terminal : Icons.terminal_outlined,
                  size: 16,
                ),
                label: Text(
                  _showLogs ? 'Hide FFmpeg Logs' : 'View FFmpeg Logs',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => MediaStudioService.cancelActiveOperation(),
                icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                label: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ],
          ),
          if (_showLogs) ...[
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[_logs.length - 1 - index];
                  return Text(
                    log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.greenAccent,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutputCard(ThemeData theme) {
    final size = File(_lastOutputFile!).existsSync()
        ? File(_lastOutputFile!).lengthSync()
        : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade700, width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(_lastOutputFile!),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  FileUtils.formatBytes(size, 2),
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.green),
            tooltip: 'Open',
            onPressed: () => OpenFilex.open(_lastOutputFile!),
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.green),
            tooltip: 'Share',
            onPressed: () => Share.shareXFiles([XFile(_lastOutputFile!)]),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Compress Video
  // ---------------------------------------------------------------------------

  Widget _buildCompressTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMediaPickerHeader(
            theme,
            selectedPath: _selectedVideoPath,
            sizeBytes: _videoSizeBytes,
            durationMs: _videoDurationMs,
            isVideo: true,
            onPick: () async {
              final path = await _pickFile(isVideo: true);
              if (path != null) _selectVideo(path);
            },
          ),
          if (_selectedVideoPath != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Compression Preset',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildQualityOption(
              theme,
              title: 'Balanced (Recommended)',
              subtitle: '720p resolution, CRF 26. ~50-60% size reduction with sharp quality.',
              quality: VideoCompressionQuality.balanced,
            ),
            const SizedBox(height: 8),
            _buildQualityOption(
              theme,
              title: 'High Compression',
              subtitle: '480p resolution, CRF 30. Maximum file size reduction for sharing.',
              quality: VideoCompressionQuality.highCompression,
            ),
            const SizedBox(height: 8),
            _buildQualityOption(
              theme,
              title: 'High Quality',
              subtitle: 'Original resolution, CRF 22. Preserves pristine details.',
              quality: VideoCompressionQuality.highQuality,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _runCompression,
                icon: const Icon(Icons.compress),
                label: const Text('Compress Video'),
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

  Widget _buildQualityOption(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required VideoCompressionQuality quality,
  }) {
    final isSelected = _compressQuality == quality;
    return InkWell(
      onTap: () => setState(() => _compressQuality = quality),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.04) : null,
        ),
        child: Row(
          children: [
            Radio<VideoCompressionQuality>(
              value: quality,
              groupValue: _compressQuality,
              onChanged: (val) {
                if (val != null) setState(() => _compressQuality = val);
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Trim Video
  // ---------------------------------------------------------------------------

  Widget _buildTrimVideoTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMediaPickerHeader(
            theme,
            selectedPath: _selectedVideoPath,
            sizeBytes: _videoSizeBytes,
            durationMs: _videoDurationMs,
            isVideo: true,
            onPick: () async {
              final path = await _pickFile(isVideo: true);
              if (path != null) _selectVideo(path);
            },
          ),
          if (_selectedVideoPath != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trimVideoStartController,
                    decoration: InputDecoration(
                      labelText: 'Start Time',
                      hintText: '00:00:00',
                      prefixIcon: const Icon(Icons.start),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _trimVideoEndController,
                    decoration: InputDecoration(
                      labelText: 'End Time',
                      hintText: '00:01:00',
                      prefixIcon: const Icon(Icons.timelapse),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fast Stream Copy'),
              subtitle: const Text('Lossless cut without re-encoding (instant execution)'),
              value: _fastTrim,
              onChanged: (val) => setState(() => _fastTrim = val),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _runTrimVideo,
                icon: const Icon(Icons.cut),
                label: const Text('Trim & Save Video'),
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
  // Tab 3: Extract Audio from Video
  // ---------------------------------------------------------------------------

  Widget _buildExtractAudioTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMediaPickerHeader(
            theme,
            selectedPath: _selectedVideoPath,
            sizeBytes: _videoSizeBytes,
            durationMs: _videoDurationMs,
            isVideo: true,
            onPick: () async {
              final path = await _pickFile(isVideo: true);
              if (path != null) _selectVideo(path);
            },
          ),
          if (_selectedVideoPath != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Target Audio Format',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: ['mp3', 'aac', 'wav'].map((fmt) {
                final isSelected = _extractTargetFormat == fmt;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(fmt.toUpperCase()),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _extractTargetFormat = fmt);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _runExtractAudio,
                icon: const Icon(Icons.audiotrack),
                label: Text('Extract as ${_extractTargetFormat.toUpperCase()}'),
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
  // Tab 4: Audio Studio (Trim & Convert)
  // ---------------------------------------------------------------------------

  Widget _buildAudioStudioTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMediaPickerHeader(
            theme,
            selectedPath: _selectedAudioPath,
            sizeBytes: _audioSizeBytes,
            durationMs: _audioDurationMs,
            isVideo: false,
            onPick: () async {
              final path = await _pickFile(isVideo: false);
              if (path != null) _selectAudio(path);
            },
          ),
          if (_selectedAudioPath != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Convert To Format',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['mp3', 'aac', 'wav', 'm4a', 'flac', 'ogg'].map((fmt) {
                final isSelected = _audioTargetFormat == fmt;
                return ChoiceChip(
                  label: Text(fmt.toUpperCase()),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _audioTargetFormat = fmt);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Optional Trim Range',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trimAudioStartController,
                    decoration: InputDecoration(
                      labelText: 'Start (Optional)',
                      hintText: '00:00:00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _trimAudioEndController,
                    decoration: InputDecoration(
                      labelText: 'End (Optional)',
                      hintText: '00:01:00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _runConvertOrTrimAudio,
                icon: const Icon(Icons.music_note),
                label: Text('Process Audio (${_audioTargetFormat.toUpperCase()})'),
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
  // Shared Header
  // ---------------------------------------------------------------------------

  Widget _buildMediaPickerHeader(
    ThemeData theme, {
    required String? selectedPath,
    required int sizeBytes,
    required double durationMs,
    required bool isVideo,
    required VoidCallback onPick,
  }) {
    if (selectedPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVideo ? Icons.movie_outlined : Icons.audio_file_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                isVideo ? 'Select a Video File' : 'Select an Audio File',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                isVideo
                    ? 'Choose an MP4, MKV, MOV, or WEBM file.'
                    : 'Choose an MP3, M4A, WAV, or FLAC track.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.file_open),
                label: Text(isVideo ? 'Choose Video' : 'Choose Audio'),
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
              color: isVideo ? Colors.deepPurple.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isVideo ? Icons.videocam : Icons.graphic_eq,
              color: isVideo ? Colors.deepPurple : Colors.orange,
              size: 28,
            ),
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
                Text(
                  '${_formatMsToTime(durationMs)} • ${FileUtils.formatBytes(sizeBytes, 1)}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Change File',
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}
