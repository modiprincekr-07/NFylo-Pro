import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

enum RecordingQuality {
  highAac, // M4A (192 kbps, 48kHz)
  standardAac, // M4A (128 kbps, 44.1kHz)
  uncompressedWav, // WAV (PCM 16-bit)
}

class VoiceRecorderService {
  static const String _defaultNotesFolder =
      '/storage/emulated/0/Download/NFylo_Voice_Notes';

  final AudioRecorder _audioRecorder = AudioRecorder();

  static Directory _getOutputDir() {
    final dir = Directory(_defaultNotesFolder);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Checks if microphone permission has been granted.
  Future<bool> hasPermission() async {
    return _audioRecorder.hasPermission();
  }

  /// Returns whether a recording session is currently active.
  Future<bool> isRecording() async {
    return _audioRecorder.isRecording();
  }

  /// Returns whether the current recording is paused.
  Future<bool> isPaused() async {
    return _audioRecorder.isPaused();
  }

  /// Stream of real-time audio amplitude (decibels) sampled at given interval.
  Stream<Amplitude> onAmplitudeChanged({
    Duration interval = const Duration(milliseconds: 100),
  }) {
    return _audioRecorder.onAmplitudeChanged(interval);
  }

  /// Starts recording with the desired quality configuration.
  Future<String> startRecording({
    RecordingQuality quality = RecordingQuality.highAac,
    String? customFileName,
  }) async {
    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted.');
    }

    final outDir = _getOutputDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    String ext = 'm4a';
    RecordConfig config;

    switch (quality) {
      case RecordingQuality.uncompressedWav:
        ext = 'wav';
        config = const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        );
        break;
      case RecordingQuality.standardAac:
        ext = 'm4a';
        config = const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        );
        break;
      case RecordingQuality.highAac:
      default:
        ext = 'm4a';
        config = const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 192000,
          sampleRate: 48000,
          numChannels: 2,
        );
        break;
    }

    final safeName = (customFileName == null || customFileName.trim().isEmpty)
        ? 'voice_note_$timestamp.$ext'
        : '${customFileName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.$ext';

    final filePath = p.join(outDir.path, safeName);
    await _audioRecorder.start(config, path: filePath);
    return filePath;
  }

  /// Pauses the active recording session.
  Future<void> pause() async {
    await _audioRecorder.pause();
  }

  /// Resumes recording if paused.
  Future<void> resume() async {
    await _audioRecorder.resume();
  }

  /// Stops recording and returns the saved file path.
  Future<String?> stop() async {
    return _audioRecorder.stop();
  }

  /// Cancels and deletes the in-progress recording.
  Future<void> cancel(String? activeFilePath) async {
    await _audioRecorder.stop();
    if (activeFilePath != null) {
      final file = File(activeFilePath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Disposes recorder resources.
  void dispose() {
    _audioRecorder.dispose();
  }

  /// Helper to format duration in seconds into `00:00:00` or `00:00`.
  static String formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hStr = hours.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }
}
