import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service managing the system-wide DocumentsUI picker interceptor mode.
/// Allows NFylo-Pro to act as a system-default file picker intercepting
/// ACTION_GET_CONTENT and ACTION_PICK intents and returning content:// URIs natively.
class PickerModeService {
  static const MethodChannel _channel =
      MethodChannel('com.modiprincekr.nfylo/picker');

  static bool isPickerMode = false;
  static String? pickerMimeType;
  static String? pickerAction;

  /// Checks if the application was launched via an explicit system picker intent.
  static Future<bool> checkPickerMode() async {
    try {
      final res = await _channel.invokeMethod<Map>('isPickerMode');
      if (res != null && res['isPicker'] == true) {
        isPickerMode = true;
        pickerMimeType = res['mimeType']?.toString();
        pickerAction = res['action']?.toString();
        return true;
      }
    } catch (e) {
      debugPrint('[PickerModeService] checkPickerMode error: $e');
    }
    isPickerMode = false;
    return false;
  }

  /// Sends the selected file back to the requesting Android activity as a content:// URI and exits.
  static Future<void> finishWithResult(String filePath) async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    try {
      await _channel.invokeMethod('finishWithResult', {'path': filePath});
    } catch (e) {
      debugPrint('[PickerModeService] finishWithResult error: $e');
    }
  }

  /// Cancels picker operation and closes the activity with RESULT_CANCELED.
  static Future<void> cancelPicker() async {
    try {
      await _channel.invokeMethod('cancelPicker');
    } catch (e) {
      debugPrint('[PickerModeService] cancelPicker error: $e');
    }
  }
}

/// Animated pulsing title widget for the document picker AppBar.
/// Features a subtle glowing dot and breathing typography to clearly indicate file selection mode.
class PulsingPickerTitle extends StatefulWidget {
  final String title;
  final String? subtitle;

  const PulsingPickerTitle({
    super.key,
    this.title = 'Select a file...',
    this.subtitle,
  });

  @override
  State<PulsingPickerTitle> createState() => _PulsingPickerTitleState();
}

class _PulsingPickerTitleState extends State<PulsingPickerTitle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primary.withOpacity(_pulseAnimation.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary
                        .withOpacity(_pulseAnimation.value * 0.7),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
