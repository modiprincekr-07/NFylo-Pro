import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/session.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import '../core/utils.dart';
import 'pdf_toolkit_service.dart';

enum ConversionState {
  idle,
  converting,
  completed,
  cancelled,
  error,
}

enum QuickConvertCategory {
  video,
  audio,
  image,
}

class QuickConvertOption {
  final String id;
  final String name;
  final String extension;
  final QuickConvertCategory category;
  final String description;

  const QuickConvertOption({
    required this.id,
    required this.name,
    required this.extension,
    required this.category,
    required this.description,
  });
}

class ConversionProgress {
  final ConversionState state;
  final double progress; // 0.0 to 1.0
  final String? outputPath;
  final String? error;
  final String message;

  const ConversionProgress({
    required this.state,
    this.progress = 0.0,
    this.outputPath,
    this.error,
    this.message = '',
  });
}

class FileConversionService {
  FileConversionService._();
  static final FileConversionService instance = FileConversionService._();

  Session? _currentSession;
  final StreamController<ConversionProgress> _streamController =
      StreamController<ConversionProgress>.broadcast();

  /// Stream of conversion progress updates.
  Stream<ConversionProgress> get progressStream => _streamController.stream;

  /// Returns available quick conversion options for the given file.
  List<QuickConvertOption> getAvailableOptions(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    final mime = lookupMimeType(filePath) ?? '';
    final isVid = FileUtils.isVideo(filePath) || mime.startsWith('video/');
    final isAud = FileUtils.isAudio(filePath) || mime.startsWith('audio/');
    final isImg = FileUtils.isImage(filePath) || mime.startsWith('image/');

    final List<QuickConvertOption> options = [];

    if (isVid) {
      if (ext != 'mp4') {
        options.add(const QuickConvertOption(
          id: 'to_mp4',
          name: 'MP4 Video',
          extension: 'mp4',
          category: QuickConvertCategory.video,
          description: 'H.264 video (Universal)',
        ));
      }
      if (ext != 'mkv') {
        options.add(const QuickConvertOption(
          id: 'to_mkv',
          name: 'MKV Video',
          extension: 'mkv',
          category: QuickConvertCategory.video,
          description: 'Matroska container',
        ));
      }
      options.add(const QuickConvertOption(
        id: 'to_gif',
        name: 'Animated GIF',
        extension: 'gif',
        category: QuickConvertCategory.video,
        description: 'Looping animated GIF',
      ));
      options.add(const QuickConvertOption(
        id: 'extract_mp3',
        name: 'Extract MP3',
        extension: 'mp3',
        category: QuickConvertCategory.audio,
        description: 'Audio track in 192kbps MP3',
      ));
      options.add(const QuickConvertOption(
        id: 'extract_m4a',
        name: 'Extract M4A',
        extension: 'm4a',
        category: QuickConvertCategory.audio,
        description: 'High-quality AAC audio',
      ));
      options.add(const QuickConvertOption(
        id: 'extract_wav',
        name: 'Extract WAV',
        extension: 'wav',
        category: QuickConvertCategory.audio,
        description: 'Lossless PCM audio',
      ));
    } else if (isAud) {
      if (ext != 'mp3') {
        options.add(const QuickConvertOption(
          id: 'to_mp3',
          name: 'MP3 Audio',
          extension: 'mp3',
          category: QuickConvertCategory.audio,
          description: 'Universal MP3 (192kbps)',
        ));
      }
      if (ext != 'm4a') {
        options.add(const QuickConvertOption(
          id: 'to_m4a',
          name: 'M4A Audio',
          extension: 'm4a',
          category: QuickConvertCategory.audio,
          description: 'Apple AAC audio',
        ));
      }
      if (ext != 'wav') {
        options.add(const QuickConvertOption(
          id: 'to_wav',
          name: 'WAV Audio',
          extension: 'wav',
          category: QuickConvertCategory.audio,
          description: 'Uncompressed PCM audio',
        ));
      }
      if (ext != 'flac') {
        options.add(const QuickConvertOption(
          id: 'to_flac',
          name: 'FLAC Audio',
          extension: 'flac',
          category: QuickConvertCategory.audio,
          description: 'Lossless audio container',
        ));
      }
    } else if (isImg) {
      if (ext != 'webp') {
        options.add(const QuickConvertOption(
          id: 'to_webp',
          name: 'WebP Image',
          extension: 'webp',
          category: QuickConvertCategory.image,
          description: 'Modern high-efficiency WebP',
        ));
      }
      if (ext != 'png') {
        options.add(const QuickConvertOption(
          id: 'to_png',
          name: 'PNG Image',
          extension: 'png',
          category: QuickConvertCategory.image,
          description: 'Lossless transparent image',
        ));
      }
      if (ext != 'jpg' && ext != 'jpeg') {
        options.add(const QuickConvertOption(
          id: 'to_jpg',
          name: 'JPG Image',
          extension: 'jpg',
          category: QuickConvertCategory.image,
          description: 'Standard JPEG photo',
        ));
      }
    } else if (ext == 'pdf') {
      options.add(const QuickConvertOption(
        id: 'to_txt',
        name: 'Plain Text',
        extension: 'txt',
        category: QuickConvertCategory.image,
        description: 'Extract text to .txt',
      ));
      options.add(const QuickConvertOption(
        id: 'to_epub',
        name: 'EPUB eBook',
        extension: 'epub',
        category: QuickConvertCategory.video,
        description: 'Reflowable EPUB 3 document',
      ));
    }

    return options;
  }

  /// Cancels currently running conversion if any.
  Future<void> cancelActiveConversion() async {
    if (_currentSession != null) {
      await _currentSession!.cancel();
      _currentSession = null;
    } else {
      await FFmpegKit.cancel();
    }
    _streamController.add(const ConversionProgress(
      state: ConversionState.cancelled,
      message: 'Conversion cancelled',
    ));
  }

  /// Probes duration of media file in milliseconds.
  Future<double> getMediaDurationMs(String filePath) async {
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

  /// Generates safe, non-colliding destination path.
  static String resolveOutputPath(String inputPath, String targetExt) {
    final dir = p.dirname(inputPath);
    final baseName = p.basenameWithoutExtension(inputPath);

    bool isWritable = false;
    try {
      final testFile = File(p.join(dir, '.nfylo_perm_test_${DateTime.now().millisecondsSinceEpoch}'));
      testFile.writeAsStringSync('ok');
      testFile.deleteSync();
      isWritable = true;
    } catch (_) {
      isWritable = false;
    }

    final targetDir = isWritable ? dir : '/storage/emulated/0/Download/NFylo_Conversions';
    final dirEntity = Directory(targetDir);
    if (!dirEntity.existsSync()) {
      try {
        dirEntity.createSync(recursive: true);
      } catch (_) {}
    }

    String candidate = p.join(targetDir, '$baseName.$targetExt');
    if (File(candidate).existsSync()) {
      candidate = p.join(targetDir, '${baseName}_converted.$targetExt');
      int counter = 1;
      while (File(candidate).existsSync()) {
        candidate = p.join(targetDir, '${baseName}_converted_$counter.$targetExt');
        counter++;
      }
    }
    return candidate;
  }

  /// Utility: Extract MP3 from Video.
  Future<String> extractAudioToMp3(
    String inputPath, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final targetPath = outputPath ?? resolveOutputPath(inputPath, 'mp3');
    final command = '-y -i "$inputPath" -vn -c:a libmp3lame -b:a 192k "$targetPath"';
    await _execute(
      command: command,
      inputPath: inputPath,
      outputPath: targetPath,
      onProgress: onProgress,
    );
    return targetPath;
  }

  /// Utility: Convert M4A/WAV/Audio to MP3.
  Future<String> convertAudioToMp3(
    String inputPath, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    return extractAudioToMp3(inputPath, outputPath: outputPath, onProgress: onProgress);
  }

  /// Utility: Convert MKV/MOV/Video to MP4.
  Future<String> convertVideoToMp4(
    String inputPath, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final targetPath = outputPath ?? resolveOutputPath(inputPath, 'mp4');
    final command = '-y -i "$inputPath" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k -movflags +faststart "$targetPath"';
    await _execute(
      command: command,
      inputPath: inputPath,
      outputPath: targetPath,
      onProgress: onProgress,
    );
    return targetPath;
  }

  /// Utility: Convert PNG/JPG to WebP.
  Future<String> convertImageToWebp(
    String inputPath, {
    String? outputPath,
    int quality = 85,
    void Function(double progress)? onProgress,
  }) async {
    final targetPath = outputPath ?? resolveOutputPath(inputPath, 'webp');
    final command = '-y -i "$inputPath" -c:v libwebp -quality $quality "$targetPath"';
    await _execute(
      command: command,
      inputPath: inputPath,
      outputPath: targetPath,
      onProgress: onProgress,
    );
    return targetPath;
  }

  /// Generic conversion method for any supported target option.
  Future<String> convertFile({
    required String inputPath,
    required QuickConvertOption targetOption,
    String? outputPath,
    void Function(double progress)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    final targetExt = targetOption.extension.toLowerCase();
    final targetPath = outputPath ?? resolveOutputPath(inputPath, targetExt);

    if (targetExt == 'txt') {
      if (onStatus != null) onStatus('Extracting text in isolate...');
      final text = await PdfToolkitService.extractText(File(inputPath));
      await File(targetPath).writeAsString(text);
      if (onProgress != null) onProgress(1.0);
      return targetPath;
    } else if (targetExt == 'epub') {
      if (onStatus != null) onStatus('Converting PDF to EPUB...');
      final epubPath = await PdfToolkitService.convertPdfToEpub(
        inputPath: inputPath,
        outputName: p.basenameWithoutExtension(targetPath),
      );
      if (onProgress != null) onProgress(1.0);
      return epubPath;
    }

    final command = _buildCommand(inputPath, targetPath, targetExt);

    if (onStatus != null) {
      onStatus('Converting to ${targetOption.name}...');
    }

    await _execute(
      command: command,
      inputPath: inputPath,
      outputPath: targetPath,
      onProgress: onProgress,
      onStatus: onStatus,
    );

    return targetPath;
  }

  String _buildCommand(String inputPath, String outputPath, String targetExt) {
    switch (targetExt) {
      case 'mp4':
        return '-y -i "$inputPath" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k -movflags +faststart "$outputPath"';
      case 'mkv':
        return '-y -i "$inputPath" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k "$outputPath"';
      case 'gif':
        return '-y -i "$inputPath" -vf "fps=12,scale=480:-1:flags=lanczos" "$outputPath"';
      case 'mp3':
        return '-y -i "$inputPath" -vn -c:a libmp3lame -b:a 192k "$outputPath"';
      case 'm4a':
        return '-y -i "$inputPath" -vn -c:a aac -b:a 192k "$outputPath"';
      case 'wav':
        return '-y -i "$inputPath" -vn -c:a pcm_s16le "$outputPath"';
      case 'flac':
        return '-y -i "$inputPath" -vn -c:a flac "$outputPath"';
      case 'webp':
        return '-y -i "$inputPath" -c:v libwebp -quality 85 "$outputPath"';
      case 'png':
        return '-y -i "$inputPath" "$outputPath"';
      case 'jpg':
      case 'jpeg':
        return '-y -i "$inputPath" -q:v 2 "$outputPath"';
      default:
        return '-y -i "$inputPath" "$outputPath"';
    }
  }

  Future<void> _execute({
    required String command,
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    _streamController.add(const ConversionProgress(
      state: ConversionState.converting,
      progress: 0.0,
      message: 'Preparing conversion...',
    ));

    final totalDurationMs = await getMediaDurationMs(inputPath);
    final completer = Completer<void>();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        _currentSession = null;
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          if (onProgress != null) onProgress(1.0);
          _streamController.add(ConversionProgress(
            state: ConversionState.completed,
            progress: 1.0,
            outputPath: outputPath,
            message: 'Conversion completed successfully',
          ));
          completer.complete();
        } else if (ReturnCode.isCancel(returnCode)) {
          _streamController.add(const ConversionProgress(
            state: ConversionState.cancelled,
            message: 'Conversion cancelled',
          ));
          completer.completeError('Conversion cancelled');
        } else {
          final failStackTrace = await session.getFailStackTrace();
          final errorMsg =
              'Conversion failed (Code: ${returnCode?.getValue()}). $failStackTrace';
          _streamController.add(ConversionProgress(
            state: ConversionState.error,
            error: errorMsg,
            message: 'Conversion failed',
          ));
          completer.completeError(errorMsg);
        }
      },
      (log) {
        if (onStatus != null) {
          final msg = log.getMessage();
          if (msg.isNotEmpty) onStatus(msg);
        }
      },
      (statistics) {
        if (totalDurationMs > 0) {
          final timeMs = statistics.getTime();
          if (timeMs > 0) {
            final progress = (timeMs / totalDurationMs).clamp(0.0, 0.99);
            if (onProgress != null) onProgress(progress);
            _streamController.add(ConversionProgress(
              state: ConversionState.converting,
              progress: progress,
              message: 'Converting... ${(progress * 100).toInt()}%',
            ));
          }
        }
      },
    );

    _currentSession = session;
    return completer.future;
  }
}
