import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/session.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/file_manager_provider.dart';
import '../internal_file_picker_screen.dart';

/// Native Video Trimmer Screen inspired by LibreCuts.
/// Built with a sleek dark aesthetic, neon red accents, dual-thumb RangeSlider,
/// real-time video preview loop, and high-efficiency lossless FFmpeg trimming.
class VideoTrimmerScreen extends StatefulWidget {
  final String? videoPath;

  const VideoTrimmerScreen({
    super.key,
    this.videoPath,
  });

  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen>
    with SingleTickerProviderStateMixin {
  static const Color _neonRed = Color(0xFFFF2A55);
  static const Color _darkBg = Color(0xFF0D0E15);
  static const Color _darkCardBg = Color(0xFF161822);

  String? _activeVideoPath;
  VideoPlayerController? _videoController;
  bool _isControllerInitialized = false;
  bool _isPlaying = false;
  String? _initError;

  // Trim range in seconds
  double _totalDurationSec = 0.0;
  RangeValues _trimRange = const RangeValues(0.0, 1.0);
  double _lastHapticStart = 0.0;
  double _lastHapticEnd = 0.0;

  // Trimming operation state
  bool _isTrimming = false;
  double _trimProgress = 0.0;
  String _trimStatus = 'Initializing stream copy...';
  Session? _activeSession;
  String? _trimmedOutputPath;

  // Glow animation for progress indicator (from Phase 2)
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.25, end: 0.70).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
      _loadVideo(widget.videoPath!);
    }
  }

  Future<void> _loadVideo(String path) async {
    try {
      if (_isControllerInitialized && _videoController != null) {
        _videoController!.removeListener(_videoPlayerListener);
        await _videoController!.dispose();
        _isControllerInitialized = false;
      }

      final file = File(path);
      if (!await file.exists()) {
        setState(() {
          _initError = 'Video file does not exist.';
        });
        return;
      }

      _activeVideoPath = path;
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();

      final durSec = _videoController!.value.duration.inMilliseconds / 1000.0;
      if (durSec <= 0) {
        setState(() {
          _initError = 'Unable to determine video duration.';
        });
        return;
      }

      _totalDurationSec = durSec;
      _trimRange = RangeValues(0.0, durSec);
      _lastHapticStart = 0.0;
      _lastHapticEnd = durSec;
      _isControllerInitialized = true;
      _initError = null;

      _videoController!.addListener(_videoPlayerListener);

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = 'Failed to load video: $e';
        });
      }
    }
  }

  Future<void> _pickVideoFile() async {
    try {
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

        if (!videoExts.contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a valid video file (.mp4, .mkv, .mov, etc.)'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        await _loadVideo(path);
      }
    } catch (_) {}
  }

  void _videoPlayerListener() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;

    final currentSec = _videoController!.value.position.inMilliseconds / 1000.0;

    // Loop playback within trimmed range
    if (_videoController!.value.isPlaying && currentSec >= _trimRange.end) {
      _videoController!.seekTo(Duration(milliseconds: (_trimRange.start * 1000).toInt()));
    }

    if (mounted) {
      final isPlaying = _videoController!.value.isPlaying;
      if (isPlaying != _isPlaying) {
        setState(() {
          _isPlaying = isPlaying;
        });
      } else {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    if (_isControllerInitialized && _videoController != null) {
      _videoController!.removeListener(_videoPlayerListener);
      _videoController!.dispose();
    }
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isControllerInitialized || _videoController == null) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}

    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      final currentSec = _videoController!.value.position.inMilliseconds / 1000.0;
      if (currentSec >= _trimRange.end || currentSec < _trimRange.start) {
        _videoController!.seekTo(Duration(milliseconds: (_trimRange.start * 1000).toInt()));
      }
      _videoController!.play();
    }
  }

  void _onRangeChanged(RangeValues values) {
    // Dynamic haptic trigger when user drags slider thumbs
    if ((values.start - _lastHapticStart).abs() > 0.08 ||
        (values.end - _lastHapticEnd).abs() > 0.08) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
      _lastHapticStart = values.start;
      _lastHapticEnd = values.end;
    }

    final bool startChanged = (values.start - _trimRange.start).abs() > 0.01;
    final bool endChanged = (values.end - _trimRange.end).abs() > 0.01;

    setState(() {
      _trimRange = values;
    });

    // Provide real-time visual frame feedback
    if (_isControllerInitialized && _videoController != null) {
      if (startChanged) {
        _videoController!.seekTo(Duration(milliseconds: (values.start * 1000).toInt()));
      } else if (endChanged) {
        _videoController!.seekTo(Duration(milliseconds: (values.end * 1000).toInt()));
      }
    }
  }

  void _adjustStart(double delta) {
    final newStart = (_trimRange.start + delta).clamp(0.0, _trimRange.end - 0.2);
    _onRangeChanged(RangeValues(newStart, _trimRange.end));
  }

  void _adjustEnd(double delta) {
    final newEnd = (_trimRange.end + delta).clamp(_trimRange.start + 0.2, _totalDurationSec);
    _onRangeChanged(RangeValues(_trimRange.start, newEnd));
  }

  String _formatSeconds(double seconds) {
    final totalMs = (seconds * 1000).toInt();
    final d = Duration(milliseconds: totalMs);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 100).toString();

    if (hours > 0) {
      return '$hours:$minutes:$secs.$ms';
    }
    return '$minutes:$secs.$ms';
  }

  String _formatTimestampForFFmpeg(double seconds) {
    final totalMs = (seconds * 1000).toInt();
    final d = Duration(milliseconds: totalMs);
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$secs.$ms';
  }

  Future<void> _startTrimming() async {
    if (_isTrimming) return;

    // Pause video playback
    if (_isControllerInitialized && _videoController != null && _videoController!.value.isPlaying) {
      await _videoController!.pause();
    }

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    setState(() {
      _isTrimming = true;
      _trimProgress = 0.0;
      _trimStatus = 'Starting fast stream copy...';
    });

    // Prepare output directory and filename
    final baseDir = Directory('/storage/emulated/0/Download/NFylo_MediaStudio');
    if (!baseDir.existsSync()) {
      try {
        baseDir.createSync(recursive: true);
      } catch (_) {}
    }

    final outDir = baseDir.existsSync() ? baseDir.path : File(_activeVideoPath!).parent.path;
    final baseName = p.basenameWithoutExtension(_activeVideoPath!);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = p.join(outDir, '${baseName}_trimmed_$timestamp.mp4');

    final startStr = _formatTimestampForFFmpeg(_trimRange.start);
    final endStr = _formatTimestampForFFmpeg(_trimRange.end);
    final clipDurationMs = (_trimRange.end - _trimRange.start) * 1000.0;

    // Prompt logic: "-ss {start} -i {input} -to {end} -c copy {output}"
    final command =
        '-y -ss $startStr -i "$_activeVideoPath" -to $endStr -c copy "$outputPath"';

    try {
      final session = await FFmpegKit.executeAsync(
        command,
        (session) async {
          _activeSession = null;
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            if (mounted) {
              setState(() {
                _trimProgress = 1.0;
                _isTrimming = false;
                _trimmedOutputPath = outputPath;
              });

              try {
                HapticFeedback.heavyImpact();
              } catch (_) {}

              // Refresh directory in file manager provider
              try {
                final provider = context.read<FileManagerProvider>();
                provider.loadDirectory(provider.currentPath, showLoading: false, clearCache: true);
                provider.updateStorageSpace();
              } catch (_) {}

              _showSuccessDialog(outputPath);
            }
          } else if (ReturnCode.isCancel(returnCode)) {
            if (mounted) {
              setState(() {
                _isTrimming = false;
                _trimStatus = 'Trimming cancelled.';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Video trimming was cancelled.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            final failStack = await session.getFailStackTrace();
            if (mounted) {
              setState(() {
                _isTrimming = false;
              });
              _showErrorDialog(
                'FFmpeg trimming failed (Code: ${returnCode?.getValue()}).\n$failStack',
              );
            }
          }
        },
        (log) {
          final msg = log.getMessage();
          if (mounted && msg.isNotEmpty) {
            setState(() {
              _trimStatus = msg;
            });
          }
        },
        (statistics) {
          if (clipDurationMs > 0) {
            final timeMs = statistics.getTime();
            if (timeMs > 0 && mounted) {
              final progress = (timeMs / clipDurationMs).clamp(0.0, 0.99);
              setState(() {
                _trimProgress = progress;
              });
            }
          }
        },
      );

      _activeSession = session;
    } catch (e) {
      setState(() {
        _isTrimming = false;
      });
      _showErrorDialog('Failed to execute trimming: $e');
    }
  }

  Future<void> _cancelTrimming() async {
    if (_activeSession != null) {
      await _activeSession!.cancel();
      _activeSession = null;
    } else {
      await FFmpegKit.cancel();
    }
  }

  void _showSuccessDialog(String outputPath) {
    final fileName = p.basename(outputPath);
    final sizeStr = File(outputPath).existsSync()
        ? '${(File(outputPath).lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB'
        : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E26),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _neonRed.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: _neonRed,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Video Trimmed Successfully!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$fileName ${sizeStr.isNotEmpty ? "($sizeStr)" : ""}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Share.shareXFiles([XFile(outputPath)]);
                        },
                        icon: const Icon(Icons.share_rounded, size: 18, color: Colors.white),
                        label: const Text('Share', style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          OpenFilex.open(outputPath);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Open'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _neonRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Back to Files',
                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Trimming Error', style: TextStyle(color: Colors.white)),
        content: Text(
          error,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: _neonRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: _darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LibreCuts Video Trimmer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              _activeVideoPath != null ? p.basename(_activeVideoPath!) : 'Choose a video to start',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isTrimming && _activeVideoPath != null)
            IconButton(
              icon: const Icon(Icons.file_upload_outlined, color: Colors.white70),
              tooltip: 'Choose another video',
              onPressed: _pickVideoFile,
            ),
          if (!_isTrimming && _isControllerInitialized)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: _startTrimming,
                icon: const Icon(Icons.content_cut_rounded, size: 16),
                label: const Text('Trim'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _neonRed,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: _neonRed.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _activeVideoPath == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _neonRed.withOpacity(0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: _neonRed.withOpacity(0.35), width: 1.5),
                        ),
                        child: const Icon(
                          Icons.video_library_rounded,
                          color: _neonRed,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Select a Video to Trim',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lossless stream copy cutting without re-encoding',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _pickVideoFile,
                        icon: const Icon(Icons.file_upload_outlined, size: 20),
                        label: const Text('Choose Video File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _neonRed,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor: _neonRed.withOpacity(0.4),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _initError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _initError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _pickVideoFile,
                            style: ElevatedButton.styleFrom(backgroundColor: _neonRed),
                            child: const Text('Select another video'),
                          ),
                        ],
                      ),
                    ),
                  )
                : !_isControllerInitialized
                    ? const Center(
                        child: CircularProgressIndicator(color: _neonRed),
                      )
                    : Stack(
                        children: [
                          Column(
                            children: [
                              // Video Preview Area
                              Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: _videoController!.value.aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                        if (!_isPlaying)
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.55),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: _neonRed.withOpacity(0.6),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 36,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom Timeline & Controls
                              _buildTimelineControls(),
                            ],
                          ),

                          // Phase 2 Glowing Progress Indicator Overlay
                          if (_isTrimming)
                            Container(
                              color: Colors.black.withOpacity(0.85),
                              child: Center(
                                child: _buildGlowingProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildTimelineControls() {
    final clipDurationSec = (_trimRange.end - _trimRange.start).clamp(0.0, _totalDurationSec);
    final currentPosSec = _isControllerInitialized
        ? (_videoController!.value.position.inMilliseconds / 1000.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        color: _darkCardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle indicator
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Playhead position & Duration badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Current: ${_formatSeconds(currentPosSec)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _neonRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _neonRed.withOpacity(0.4), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.av_timer_rounded, color: _neonRed, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Clip: ${_formatSeconds(clipDurationSec)}',
                      style: const TextStyle(
                        color: _neonRed,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Timeline Slider with Neon Red Aesthetic
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _neonRed,
              inactiveTrackColor: Colors.white.withOpacity(0.15),
              thumbColor: _neonRed,
              overlayColor: _neonRed.withOpacity(0.25),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 10,
                elevation: 4,
                pressedElevation: 8,
              ),
              trackHeight: 6.0,
              rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            ),
            child: RangeSlider(
              values: _trimRange,
              min: 0.0,
              max: _totalDurationSec > 0 ? _totalDurationSec : 1.0,
              onChanged: _onRangeChanged,
            ),
          ),

          const SizedBox(height: 8),

          // Precision Start and End Cards with Micro-Stepping
          Row(
            children: [
              // Start Card
              Expanded(
                child: _buildTimeAdjustCard(
                  label: 'Start Time',
                  timeStr: _formatSeconds(_trimRange.start),
                  onMinus: () => _adjustStart(-0.1),
                  onPlus: () => _adjustStart(0.1),
                ),
              ),
              const SizedBox(width: 12),
              // End Card
              Expanded(
                child: _buildTimeAdjustCard(
                  label: 'End Time',
                  timeStr: _formatSeconds(_trimRange.end),
                  onMinus: () => _adjustEnd(-0.1),
                  onPlus: () => _adjustEnd(0.1),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Mode chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flash_on_rounded, color: Colors.amberAccent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Lossless Stream Copy (Instant trimming, zero quality loss)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeAdjustCard({
    required String label,
    required String timeStr,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              Row(
                children: [
                  _buildMicroStepButton(icon: Icons.remove, onTap: onMinus),
                  const SizedBox(width: 4),
                  _buildMicroStepButton(icon: Icons.add, onTap: onPlus),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMicroStepButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () {
          try {
            HapticFeedback.selectionClick();
          } catch (_) {}
          onTap();
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: Colors.white70, size: 14),
        ),
      ),
    );
  }

  /// Glowing animated circular progress indicator (Phase 2 aesthetic)
  Widget _buildGlowingProgressIndicator() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _neonRed.withOpacity(0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _neonRed.withOpacity(_glowAnimation.value),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _neonRed.withOpacity(_glowAnimation.value),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(
                        value: _trimProgress > 0 ? _trimProgress : null,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(_neonRed),
                      ),
                    ),
                    Text(
                      _trimProgress > 0 ? '${(_trimProgress * 100).toInt()}%' : '...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Lossless Video Trimming',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _trimStatus,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _cancelTrimming,
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
