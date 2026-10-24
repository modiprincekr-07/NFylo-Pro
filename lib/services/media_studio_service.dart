import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/session.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum VideoCompressionQuality {
  highCompression, // 480p / crf 30 - smallest size
  balanced, // 720p / crf 26 - standard
  highQuality, // crf 22 - preserving fine detail
}

class MediaStudioService {
  static const String _defaultMediaFolder =
      '/storage/emulated/0/Download/NFylo_MediaStudio';

  static Session? _currentActiveSession;

  static Directory _getOutputDir() {
    final dir = Directory(_defaultMediaFolder);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Cancels the currently active FFmpeg operation if running.
  static Future<void> cancelActiveOperation() async {
    if (_currentActiveSession != null) {
      await _currentActiveSession!.cancel();
      _currentActiveSession = null;
    } else {
      await FFmpegKit.cancel();
    }
  }

  /// Probes duration of media file in milliseconds.
  static Future<double> getMediaDurationMs(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final mediaInfo = session.getMediaInformation();
      if (mediaInfo != null) {
        final durStr = mediaInfo.getDuration();
        if (durStr != null) {
          final secs = double.tryParse(durStr) ?? 0.0;
          return secs * 1000.0;
        }
      }
    } catch (_) {}
    return 0.0;
  }

  /// Compresses a video file with specified quality preset asynchronously.
  static Future<String> compressVideo({
    required String inputPath,
    VideoCompressionQuality quality = VideoCompressionQuality.balanced,
    String? outputName,
    void Function(double progress)? onProgress,
    void Function(String logMessage)? onLog,
  }) async {
    final outDir = _getOutputDir();
    final base = p.basenameWithoutExtension(inputPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_compressed_$timestamp.mp4'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.mp4';

    final outPath = p.join(outDir.path, safeName);
    final totalDurationMs = await getMediaDurationMs(inputPath);

    int crf = 26;
    String scaleFilter = '';
    switch (quality) {
      case VideoCompressionQuality.highCompression:
        crf = 30;
        scaleFilter = '-vf "scale=-2:480"';
        break;
      case VideoCompressionQuality.highQuality:
        crf = 22;
        break;
      case VideoCompressionQuality.balanced:
      default:
        crf = 26;
        scaleFilter = '-vf "scale=-2:720"';
        break;
    }

    final command =
        '-y -i "$inputPath" $scaleFilter -c:v libx264 -crf $crf -preset veryfast -c:a aac -b:a 128k "$outPath"';

    await _executeCommand(
      command: command,
      totalDurationMs: totalDurationMs,
      onProgress: onProgress,
      onLog: onLog,
    );

    return outPath;
  }

  /// Trims or cuts video between startTime ("hh:mm:ss") and endTime ("hh:mm:ss").
  static Future<String> trimVideo({
    required String inputPath,
    required String startTime,
    required String endTime,
    bool fastCopy = true,
    String? outputName,
    void Function(double progress)? onProgress,
    void Function(String logMessage)? onLog,
  }) async {
    final outDir = _getOutputDir();
    final base = p.basenameWithoutExtension(inputPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_trimmed_$timestamp.mp4'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.mp4';

    final outPath = p.join(outDir.path, safeName);

    // Calculate duration between start and end
    final startMs = _parseTimeToMs(startTime);
    final endMs = _parseTimeToMs(endTime);
    final clipDurationMs = (endMs > startMs) ? (endMs - startMs) : 0.0;

    final codecFlag = fastCopy ? '-c copy' : '-c:v libx264 -preset veryfast -c:a aac';
    final command =
        '-y -ss $startTime -to $endTime -i "$inputPath" $codecFlag "$outPath"';

    await _executeCommand(
      command: command,
      totalDurationMs: clipDurationMs,
      onProgress: onProgress,
      onLog: onLog,
    );

    return outPath;
  }

  /// Extracts audio track from video file (MP4 to MP3 or AAC).
  static Future<String> extractAudio({
    required String inputPath,
    String targetFormat = 'mp3', // 'mp3' or 'aac'
    String? outputName,
    void Function(double progress)? onProgress,
    void Function(String logMessage)? onLog,
  }) async {
    final outDir = _getOutputDir();
    final base = p.basenameWithoutExtension(inputPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanExt = targetFormat.toLowerCase().replaceAll('.', '');
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_audio_$timestamp.$cleanExt'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.$cleanExt';

    final outPath = p.join(outDir.path, safeName);
    final totalDurationMs = await getMediaDurationMs(inputPath);

    String audioCodecFlag = '-c:a libmp3lame -q:a 2';
    if (cleanExt == 'aac' || cleanExt == 'm4a') {
      audioCodecFlag = '-c:a aac -b:a 192k';
    } else if (cleanExt == 'wav') {
      audioCodecFlag = '-c:a pcm_s16le';
    }

    final command = '-y -i "$inputPath" -vn $audioCodecFlag "$outPath"';

    await _executeCommand(
      command: command,
      totalDurationMs: totalDurationMs,
      onProgress: onProgress,
      onLog: onLog,
    );

    return outPath;
  }

  /// Trims or converts audio files across various formats (MP3, AAC, WAV, M4A, OGG, FLAC).
  static Future<String> trimOrConvertAudio({
    required String inputPath,
    required String targetFormat,
    String? startTime,
    String? endTime,
    String? outputName,
    void Function(double progress)? onProgress,
    void Function(String logMessage)? onLog,
  }) async {
    final outDir = _getOutputDir();
    final base = p.basenameWithoutExtension(inputPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanExt = targetFormat.toLowerCase().replaceAll('.', '');
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_converted_$timestamp.$cleanExt'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.$cleanExt';

    final outPath = p.join(outDir.path, safeName);

    String timeFlags = '';
    double totalDurationMs = await getMediaDurationMs(inputPath);

    if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
      timeFlags = '-ss $startTime -to $endTime ';
      final sMs = _parseTimeToMs(startTime);
      final eMs = _parseTimeToMs(endTime);
      if (eMs > sMs) totalDurationMs = eMs - sMs;
    }

    String codec = 'copy';
    if (cleanExt == 'mp3') {
      codec = 'libmp3lame -q:a 2';
    } else if (cleanExt == 'aac' || cleanExt == 'm4a') {
      codec = 'aac -b:a 192k';
    } else if (cleanExt == 'wav') {
      codec = 'pcm_s16le';
    } else if (cleanExt == 'flac') {
      codec = 'flac';
    } else if (cleanExt == 'ogg') {
      codec = 'libvorbis -q:a 4';
    }

    final command = '-y $timeFlags-i "$inputPath" -c:a $codec "$outPath"';

    await _executeCommand(
      command: command,
      totalDurationMs: totalDurationMs,
      onProgress: onProgress,
      onLog: onLog,
    );

    return outPath;
  }

  static Future<void> _executeCommand({
    required String command,
    required double totalDurationMs,
    void Function(double progress)? onProgress,
    void Function(String logMessage)? onLog,
  }) async {
    final completer = Completer<void>();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        _currentActiveSession = null;
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          if (onProgress != null) onProgress(1.0);
          completer.complete();
        } else if (ReturnCode.isCancel(returnCode)) {
          completer.completeError('Operation was cancelled.');
        } else {
          final failStackTrace = await session.getFailStackTrace();
          completer.completeError(
            'FFmpeg operation failed with code: ${returnCode?.getValue()}.\n$failStackTrace',
          );
        }
      },
      (log) {
        if (onLog != null) {
          onLog(log.getMessage());
        }
      },
      (statistics) {
        if (onProgress != null && totalDurationMs > 0) {
          final timeMs = statistics.getTime();
          if (timeMs > 0) {
            final progress = (timeMs / totalDurationMs).clamp(0.0, 0.99);
            onProgress(progress);
          }
        }
      },
    );

    _currentActiveSession = session;
    return completer.future;
  }

  static double _parseTimeToMs(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length == 3) {
        final hours = double.parse(parts[0]);
        final minutes = double.parse(parts[1]);
        final seconds = double.parse(parts[2]);
        return (hours * 3600 + minutes * 60 + seconds) * 1000.0;
      } else if (parts.length == 2) {
        final minutes = double.parse(parts[0]);
        final seconds = double.parse(parts[1]);
        return (minutes * 60 + seconds) * 1000.0;
      } else if (parts.length == 1) {
        return (double.parse(parts[0])) * 1000.0;
      }
    } catch (_) {}
    return 0.0;
  }
}
