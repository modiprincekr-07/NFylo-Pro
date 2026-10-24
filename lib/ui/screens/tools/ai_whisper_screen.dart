import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../services/ai_speech_service.dart';

class AiWhisperScreen extends StatefulWidget {
  final String? initialAudioPath;

  const AiWhisperScreen({super.key, this.initialAudioPath});

  @override
  State<AiWhisperScreen> createState() => _AiWhisperScreenState();
}

class _AiWhisperScreenState extends State<AiWhisperScreen> with SingleTickerProviderStateMixin {
  final AiSpeechService _speechService = AiSpeechService();
  late TabController _tabController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  String? _selectedAudioPath;
  String? _selectedAudioName;
  bool _isRecording = false;
  String? _recordedFilePath;

  String _selectedModelTier = 'tiny';
  String _selectedLanguage = 'auto';

  TranscriptionResult? _transcriptionResult;
  bool _showSrtTimeline = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _speechService.addListener(_onServiceUpdate);
    if (widget.initialAudioPath != null) {
      _selectedAudioPath = widget.initialAudioPath;
      _selectedAudioName = _selectedAudioPath!.split(Platform.pathSeparator).last;
    }
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speechService.removeListener(_onServiceUpdate);
    _tabController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadSampleAudio() async {
    final tempDir = await getTemporaryDirectory();
    final sampleFile = File('${tempDir.path}/sample_voice_memo.wav');
    if (!await sampleFile.exists()) {
      // Create small placeholder audio file
      await sampleFile.writeAsBytes(List<int>.filled(1024, 0));
    }

    setState(() {
      _selectedAudioPath = sampleFile.path;
      _selectedAudioName = 'sample_voice_memo.wav';
    });
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      final recordPath = '${tempDir.path}/live_dictation_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: recordPath,
      );

      setState(() {
        _isRecording = true;
        _recordedFilePath = recordPath;
      });
    }
  }

  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      if (path != null) {
        _selectedAudioPath = path;
        _selectedAudioName = 'Live Recording (${path.split(Platform.pathSeparator).last})';
      }
    });

    if (path != null) {
      _runTranscription(path);
    }
  }

  Future<void> _runTranscription(String path) async {
    try {
      final res = await _speechService.transcribeAudio(
        audioPath: path,
        modelTier: _selectedModelTier,
        language: _selectedLanguage,
      );
      setState(() {
        _transcriptionResult = res;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transcription error: $e')),
      );
    }
  }

  Future<void> _exportSrt() async {
    if (_transcriptionResult == null) return;
    final tempDir = await getTemporaryDirectory();
    final srtFile = File('${tempDir.path}/subtitles_${DateTime.now().millisecondsSinceEpoch}.srt');
    await srtFile.writeAsString(_transcriptionResult!.toSrtString());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported SRT to ${srtFile.path}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Whisper Speech-to-Text'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.hintColor,
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Broken.document_upload, size: 18), text: 'Audio File'),
            Tab(icon: Icon(Broken.microphone_2, size: 18), text: 'Live Dictate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFileTab(theme, isDark),
          _buildLiveRecordTab(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildFileTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelSettingsCard(theme, isDark),
          const SizedBox(height: 16),
          _buildAudioSelectorCard(theme, isDark),
          const SizedBox(height: 16),
          if (_speechService.isTranscribing) ...[
            _buildProgressCard(theme, isDark),
            const SizedBox(height: 16),
          ],
          if (_transcriptionResult != null) ...[
            _buildResultCard(theme, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveRecordTab(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isRecording ? 120 : 100,
              height: _isRecording ? 120 : 100,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.redAccent.withOpacity(0.2) : theme.colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isRecording ? Colors.redAccent : theme.colorScheme.primary,
                  width: 3,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  _isRecording ? Icons.stop : Broken.microphone_2,
                  size: 48,
                  color: _isRecording ? Colors.redAccent : theme.colorScheme.primary,
                ),
                onPressed: () {
                  if (_isRecording) {
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isRecording ? 'Listening & Recording...' : 'Tap to Start Voice Dictation',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _isRecording ? Colors.redAccent : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? 'Speak clearly into your microphone. Tap stop when finished.'
                  : 'Whisper will transcribe your speech completely offline on your device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            if (_transcriptionResult != null && !_isRecording) ...[
              const SizedBox(height: 24),
              _buildResultCard(theme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelSettingsCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.setting_2, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Transcription Engine',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedModelTier,
                  decoration: InputDecoration(
                    labelText: 'Acoustic Model',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'tiny', child: Text('Whisper Tiny (39 MB)')),
                    DropdownMenuItem(value: 'base', child: Text('Whisper Base (74 MB)')),
                    DropdownMenuItem(value: 'small', child: Text('Whisper Small (244 MB)')),
                  ],
                  onChanged: (v) => setState(() => _selectedModelTier = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedLanguage,
                  decoration: InputDecoration(
                    labelText: 'Language',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto-Detect')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Spanish')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                    DropdownMenuItem(value: 'de', child: Text('German')),
                    DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                  ],
                  onChanged: (v) => setState(() => _selectedLanguage = v!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSelectorCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.music_filter, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Audio Source',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_selectedAudioName != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Broken.music, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedAudioName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() {
                      _selectedAudioPath = null;
                      _selectedAudioName = null;
                      _transcriptionResult = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Broken.play, size: 18),
                label: const Text('Start Offline Transcription'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _speechService.isTranscribing
                    ? null
                    : () => _runTranscription(_selectedAudioPath!),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Broken.music_filter),
                    label: const Text('Load Sample Audio'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _loadSampleAudio,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Analyzing spectrogram & decoding tokens...',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${(_speechService.transcriptionProgress * 100).toInt()}%',
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _speechService.transcriptionProgress,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, bool isDark) {
    final res = _transcriptionResult!;

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
              Text(
                'Transcription (${res.detectedLanguage})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Broken.copy, size: 18),
                tooltip: 'Copy Full Text',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: res.fullText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied text to clipboard')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Broken.share, size: 18),
                tooltip: 'Share',
                onPressed: () => Share.share(res.fullText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('SRT Timeline'),
                selected: _showSrtTimeline,
                onSelected: (v) => setState(() => _showSrtTimeline = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Plain Text'),
                selected: !_showSrtTimeline,
                onSelected: (v) => setState(() => _showSrtTimeline = false),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Broken.document_download, size: 16),
                label: const Text('Export .SRT', style: TextStyle(fontSize: 12)),
                onPressed: _exportSrt,
              ),
            ],
          ),
          const Divider(height: 20),
          if (_showSrtTimeline) ...[
            ...res.segments.map((seg) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        seg.formattedTimestamp,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(seg.text, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            SelectableText(
              res.fullText,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
