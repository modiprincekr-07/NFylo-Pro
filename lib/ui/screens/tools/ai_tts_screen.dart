import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../services/ai_speech_service.dart';

class AiTtsScreen extends StatefulWidget {
  const AiTtsScreen({super.key});

  @override
  State<AiTtsScreen> createState() => _AiTtsScreenState();
}

class _AiTtsScreenState extends State<AiTtsScreen> {
  final AiSpeechService _speechService = AiSpeechService();
  final TextEditingController _textCtrl = TextEditingController(
    text: "Welcome to NFylo-Pro. All neural speech models run completely on-device with zero latency and complete privacy.",
  );

  String _selectedVoice = 'Nova';
  double _speechRate = 1.0;
  double _pitch = 1.0;

  AudioPlayer? _audioPlayer;
  String? _generatedAudioPath;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  final List<Map<String, String>> _voices = [
    {'name': 'Nova', 'desc': 'Energetic & bright', 'tag': 'Female'},
    {'name': 'Echo', 'desc': 'Warm & conversational', 'tag': 'Male'},
    {'name': 'Alloy', 'desc': 'Neutral & balanced', 'tag': 'Adaptive'},
    {'name': 'Shimmer', 'desc': 'Crisp & expressive', 'tag': 'Female'},
    {'name': 'Onyx', 'desc': 'Deep & authoritative', 'tag': 'Male'},
  ];

  @override
  void initState() {
    super.initState();
    _speechService.addListener(_onServiceUpdate);
    _initAudioPlayer();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer!.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _currentPosition = Duration.zero;
          }
        });
      }
    });

    _audioPlayer!.positionStream.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });

    _audioPlayer!.durationStream.listen((dur) {
      if (mounted) setState(() => _totalDuration = dur ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    _speechService.removeListener(_onServiceUpdate);
    _audioPlayer?.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateSpeech() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    try {
      final path = await _speechService.synthesizeNeuralTts(
        text: text,
        voiceName: _selectedVoice,
        speechRate: _speechRate,
        pitch: _pitch,
      );

      setState(() {
        _generatedAudioPath = path;
      });

      await _audioPlayer?.setFilePath(path);
      await _audioPlayer?.play();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TTS error: $e')),
      );
    }
  }

  void _togglePlayback() {
    if (_audioPlayer == null || _generatedAudioPath == null) return;
    if (_isPlaying) {
      _audioPlayer!.pause();
    } else {
      _audioPlayer!.play();
    }
  }

  void _shareAudio() {
    if (_generatedAudioPath != null) {
      Share.shareXFiles([XFile(_generatedAudioPath!)], text: 'Generated with NFylo Neural TTS');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Neural Voice Generator (TTS)'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextInputCard(theme, isDark),
            const SizedBox(height: 16),
            _buildVoiceSelectionCard(theme, isDark),
            const SizedBox(height: 16),
            _buildModulationCard(theme, isDark),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _speechService.isSynthesizing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Broken.music_filter),
                label: Text(_speechService.isSynthesizing ? 'Synthesizing...' : 'Generate Voice Audio'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _speechService.isSynthesizing ? null : _generateSpeech,
              ),
            ),
            if (_generatedAudioPath != null) ...[
              const SizedBox(height: 20),
              _buildPlayerCard(theme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.document_text, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Text to Synthesize',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_textCtrl.text.length} chars',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Enter text to speak...',
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sampleChip('Welcome greeting', "Hello and welcome! Your on-device neural voice assistant is ready."),
                const SizedBox(width: 8),
                _sampleChip('System alert', "Warning: Low disk space detected on primary storage partition."),
                const SizedBox(width: 8),
                _sampleChip('Audiobook quote', "The stars shone brightly in the velvet quiet of the midnight sky."),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleChip(String label, String fullText) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => setState(() => _textCtrl.text = fullText),
    );
  }

  Widget _buildVoiceSelectionCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.profile_2user, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Speaker Persona',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._voices.map((v) {
            final isSelected = _selectedVoice == v['name'];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                ),
              ),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: isSelected ? theme.colorScheme.primary : theme.hintColor.withOpacity(0.2),
                  child: Text(
                    v['name']![0],
                    style: TextStyle(
                      color: isSelected ? Colors.white : null,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                title: Text(v['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(v['desc']!, style: const TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(v['tag']!, style: const TextStyle(fontSize: 10)),
                ),
                onTap: () => setState(() => _selectedVoice = v['name']!),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModulationCard(ThemeData theme, bool isDark) {
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
              Icon(Broken.audio_square, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Voice Modulation',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Speech Rate: ${_speechRate.toStringAsFixed(1)}x'),
              Text(_speechRate > 1.0 ? 'Faster' : (_speechRate < 1.0 ? 'Slower' : 'Normal')),
            ],
          ),
          Slider(
            value: _speechRate,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            label: '${_speechRate.toStringAsFixed(1)}x',
            onChanged: (v) => setState(() => _speechRate = v),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pitch Shift: ${_pitch.toStringAsFixed(1)}x'),
              Text(_pitch > 1.0 ? 'Higher' : (_pitch < 1.0 ? 'Deeper' : 'Default')),
            ],
          ),
          Slider(
            value: _pitch,
            min: 0.6,
            max: 1.4,
            divisions: 8,
            label: '${_pitch.toStringAsFixed(1)}x',
            onChanged: (v) => setState(() => _pitch = v),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filled(
                icon: Icon(_isPlaying ? Icons.pause : Broken.play),
                onPressed: _togglePlayback,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Preview ($_selectedVoice)',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '16kHz Mono PCM • Waveform rendered',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Broken.share),
                tooltip: 'Share Audio File',
                onPressed: _shareAudio,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: _currentPosition.inMilliseconds.toDouble().clamp(0.0, _totalDuration.inMilliseconds.toDouble()),
            min: 0.0,
            max: _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0,
            onChanged: (v) {
              _audioPlayer?.seek(Duration(milliseconds: v.toInt()));
            },
          ),
        ],
      ),
    );
  }
}
