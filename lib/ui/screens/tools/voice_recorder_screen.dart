import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils.dart';
import '../../../services/voice_recorder_service.dart';

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen>
    with SingleTickerProviderStateMixin {
  final VoiceRecorderService _recorderService = VoiceRecorderService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Recording State
  bool _isRecording = false;
  bool _isPaused = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentDecibels = -60.0;
  String? _activeRecordingPath;

  // Settings
  RecordingQuality _quality = RecordingQuality.highAac;
  final TextEditingController _titleController = TextEditingController();

  // Playback State
  String? _lastSavedPath;
  bool _isPlaying = false;
  Duration _playPosition = Duration.zero;
  Duration _playTotalDuration = Duration.zero;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerPositionSub;
  StreamSubscription? _playerDurationSub;

  // List of recordings in current session
  final List<String> _sessionRecordings = [];

  // Waveform animation
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing &&
              state.processingState != ProcessingState.completed;
        });
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
        }
      }
    });

    _playerPositionSub = _audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _playPosition = pos);
    });

    _playerDurationSub = _audioPlayer.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _playTotalDuration = dur);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _playerDurationSub?.cancel();
    _waveController.dispose();
    _recorderService.dispose();
    _audioPlayer.dispose();
    _titleController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Recording Controls
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      final title = _titleController.text.trim();
      final path = await _recorderService.startRecording(
        quality: _quality,
        customFileName: title.isNotEmpty ? title : null,
      );

      _recordTimer?.cancel();
      _recordDurationSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && !_isPaused) {
          setState(() => _recordDurationSeconds++);
        }
      });

      _amplitudeSub?.cancel();
      _amplitudeSub = _recorderService.onAmplitudeChanged().listen((amp) {
        if (mounted) {
          setState(() => _currentDecibels = amp.current);
        }
      });

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _activeRecordingPath = path;
      });
    } catch (e) {
      _showError('Recording error: $e');
    }
  }

  Future<void> _pauseRecording() async {
    await _recorderService.pause();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    await _recorderService.resume();
    setState(() => _isPaused = false);
  }

  Future<void> _stopAndSaveRecording() async {
    _recordTimer?.cancel();
    await _amplitudeSub?.cancel();

    final savedPath = await _recorderService.stop();

    setState(() {
      _isRecording = false;
      _isPaused = false;
      if (savedPath != null) {
        _lastSavedPath = savedPath;
        _sessionRecordings.insert(0, savedPath);
      }
    });

    if (savedPath != null) {
      await _audioPlayer.setFilePath(savedPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${p.basename(savedPath)}'),
            backgroundColor: Colors.green.shade700,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(savedPath)]),
            ),
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _amplitudeSub?.cancel();
    await _recorderService.cancel(_activeRecordingPath);

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _activeRecordingPath = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording discarded')),
      );
    }
  }

  Future<void> _togglePlayback(String filePath) async {
    if (_lastSavedPath != filePath) {
      _lastSavedPath = filePath;
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
    } else {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    }
  }

  void _showError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Timer Display & Visualizer Box
            _buildVisualizerCard(theme),

            const SizedBox(height: 24),

            // Recording Controls (Record / Pause / Resume / Stop)
            _buildControlsSection(theme),

            const SizedBox(height: 28),

            // Quality & Settings (disabled during active recording)
            if (!_isRecording) _buildSettingsSection(theme),

            // Mini Player for Last Recorded / Selected Note
            if (_lastSavedPath != null && !_isRecording) ...[
              const SizedBox(height: 24),
              _buildMiniPlayerCard(theme),
            ],

            // Recent Session Recordings List
            if (_sessionRecordings.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSessionRecordingsList(theme),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Visualizer Card
  // ---------------------------------------------------------------------------

  Widget _buildVisualizerCard(ThemeData theme) {
    final timerText = VoiceRecorderService.formatDuration(_recordDurationSeconds);

    // Normalize decibels (-60 to 0) to 0.1 - 1.0 range for bar heights
    final normalizedAmp = ((_currentDecibels + 60) / 60).clamp(0.1, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Timer
          Text(
            timerText,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontFamily: 'monospace',
              color: _isRecording
                  ? (_isPaused ? Colors.orangeAccent : Colors.redAccent)
                  : theme.textTheme.headlineMedium?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isRecording
                ? (_isPaused ? 'Recording Paused' : 'Recording in Progress...')
                : 'Ready to Record',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _isRecording
                  ? (_isPaused ? Colors.orangeAccent : Colors.redAccent)
                  : Colors.grey,
            ),
          ),
          const SizedBox(height: 24),

          // Animated Waveform Bars
          SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(15, (index) {
                final barHeight = _isRecording && !_isPaused
                    ? 8.0 + (32.0 * normalizedAmp * (0.5 + 0.5 * ((index % 3 + 1) / 3)))
                    : 6.0;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 4,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? (_isPaused ? Colors.orangeAccent : Colors.redAccent)
                        : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  Widget _buildControlsSection(ThemeData theme) {
    if (!_isRecording) {
      return Center(
        child: InkWell(
          onTap: _startRecording,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.mic, size: 36, color: Colors.white),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Cancel Button
        IconButton.filledTonal(
          icon: const Icon(Icons.close, color: Colors.redAccent),
          tooltip: 'Discard',
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 24),

        // Pause / Resume Button
        IconButton.filled(
          iconSize: 32,
          padding: const EdgeInsets.all(16),
          style: IconButton.styleFrom(backgroundColor: Colors.orangeAccent),
          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
          tooltip: _isPaused ? 'Resume' : 'Pause',
          onPressed: _isPaused ? _resumeRecording : _pauseRecording,
        ),
        const SizedBox(width: 24),

        // Stop & Save Button
        IconButton.filled(
          iconSize: 32,
          padding: const EdgeInsets.all(16),
          style: IconButton.styleFrom(backgroundColor: Colors.green.shade600),
          icon: const Icon(Icons.check),
          tooltip: 'Save Recording',
          onPressed: _stopAndSaveRecording,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Settings & Title Input
  // ---------------------------------------------------------------------------

  Widget _buildSettingsSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Voice Note Title (Optional)',
              hintText: 'e.g. Meeting Note, Voice Memo',
              prefixIcon: const Icon(Icons.edit_note),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Recording Quality',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('High (M4A)'),
                  selected: _quality == RecordingQuality.highAac,
                  onSelected: (val) {
                    if (val) setState(() => _quality = RecordingQuality.highAac);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Standard'),
                  selected: _quality == RecordingQuality.standardAac,
                  onSelected: (val) {
                    if (val) setState(() => _quality = RecordingQuality.standardAac);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('WAV (PCM)'),
                  selected: _quality == RecordingQuality.uncompressedWav,
                  onSelected: (val) {
                    if (val) setState(() => _quality = RecordingQuality.uncompressedWav);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mini Player Card
  // ---------------------------------------------------------------------------

  Widget _buildMiniPlayerCard(ThemeData theme) {
    final curSec = _playPosition.inSeconds;
    final totSec = _playTotalDuration.inSeconds > 0
        ? _playTotalDuration.inSeconds
        : (_recordDurationSeconds > 0 ? _recordDurationSeconds : 1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.audiotrack, color: theme.colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(_lastSavedPath!),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${VoiceRecorderService.formatDuration(curSec)} / ${VoiceRecorderService.formatDuration(totSec)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open with Player',
                onPressed: () => OpenFilex.open(_lastSavedPath!),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share',
                onPressed: () => Share.shareXFiles([XFile(_lastSavedPath!)]),
              ),
            ],
          ),
          Slider(
            value: curSec.clamp(0, totSec).toDouble(),
            min: 0,
            max: totSec.toDouble(),
            onChanged: (val) {
              _audioPlayer.seek(Duration(seconds: val.round()));
            },
          ),
          Center(
            child: IconButton.filled(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () => _togglePlayback(_lastSavedPath!),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent Recordings
  // ---------------------------------------------------------------------------

  Widget _buildSessionRecordingsList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Session Recordings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        ..._sessionRecordings.map((path) {
          final isSelected = _lastSavedPath == path;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                isSelected && _isPlaying ? Icons.volume_up : Icons.mic_none,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
              title: Text(
                p.basename(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(isSelected && _isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () => _togglePlayback(path),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: () => Share.shareXFiles([XFile(path)]),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
