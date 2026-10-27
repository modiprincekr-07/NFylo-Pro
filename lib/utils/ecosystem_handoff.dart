import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';

/// Ecosystem Handoff utility for seamless bridging with external heavy media editors.
/// Features explicit intent targeting for ImageToolbox (com.t8rin.imagetoolbox)
/// and a cinema-grade butter-smooth fade transition overlay.
class EcosystemHandoff {
  static const String imageToolboxPackage = 'com.t8rin.imagetoolbox';
  static const String imageToolboxFossPackage = 'com.t8rin.imagetoolbox.foss';

  /// Launches ImageToolbox (or a system-wide image editor fallback) for the specified [imageFile].
  /// If [context] is provided, executes a butter-smooth fade-out transition to make
  /// the external app switch feel completely native.
  static Future<bool> launchImageToolbox(
    File imageFile, {
    BuildContext? context,
  }) async {
    if (!await imageFile.exists()) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image file does not exist.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    // Trigger dynamic haptic feedback
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Show smooth fade-out transition if context is mounted
    OverlayEntry? fadeOverlay;
    if (context != null && context.mounted) {
      fadeOverlay = OverlayEntry(
        builder: (ctx) => const _HandoffFadeTransitionOverlay(),
      );
      try {
        Overlay.of(context).insert(fadeOverlay);
        // Allow fade-out animation to render cleanly
        await Future.delayed(const Duration(milliseconds: 260));
      } catch (_) {}
    }

    bool success = false;
    try {
      if (Platform.isAndroid) {
        success = await _launchAndroidImageToolbox(imageFile);
      } else {
        // Fallback for non-Android environments
        final result = await OpenFilex.open(imageFile.path);
        success = result.type == ResultType.done;
      }
    } catch (e) {
      debugPrint('EcosystemHandoff error: $e');
      try {
        final result = await OpenFilex.open(imageFile.path);
        success = result.type == ResultType.done;
      } catch (_) {
        success = false;
      }
    } finally {
      if (fadeOverlay != null) {
        // Brief delay before cleaning up overlay so the handoff feels fluid
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          if (fadeOverlay.mounted) {
            fadeOverlay.remove();
          }
        } catch (_) {}
      }
    }

    if (!success && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ImageToolbox not found. Please install ImageToolbox from GitHub or F-Droid.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return success;
  }

  /// Internal Android intent dispatcher targeting ImageToolbox explicitly with robust fallbacks.
  static Future<bool> _launchAndroidImageToolbox(File imageFile) async {
    final mimeType = lookupMimeType(imageFile.path) ?? 'image/*';
    final fileUri = Uri.file(imageFile.path).toString();

    // 1. Try explicit ACTION_EDIT targeting standard ImageToolbox package
    final explicitEditIntent = AndroidIntent(
      action: 'android.intent.action.EDIT',
      package: imageToolboxPackage,
      data: fileUri,
      type: mimeType,
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
        Flag.FLAG_GRANT_WRITE_URI_PERMISSION,
      ],
    );

    try {
      if (await explicitEditIntent.canResolveActivity()) {
        await explicitEditIntent.launch();
        return true;
      }
    } catch (_) {}

    // 2. Try explicit ACTION_EDIT targeting F-Droid ImageToolbox package
    final fossEditIntent = AndroidIntent(
      action: 'android.intent.action.EDIT',
      package: imageToolboxFossPackage,
      data: fileUri,
      type: mimeType,
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
        Flag.FLAG_GRANT_WRITE_URI_PERMISSION,
      ],
    );

    try {
      if (await fossEditIntent.canResolveActivity()) {
        await fossEditIntent.launch();
        return true;
      }
    } catch (_) {}

    // 3. Try explicit ACTION_SEND targeting standard ImageToolbox package
    final explicitSendIntent = AndroidIntent(
      action: 'android.intent.action.SEND',
      package: imageToolboxPackage,
      type: mimeType,
      arguments: <String, dynamic>{
        'android.intent.extra.STREAM': fileUri,
      },
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
      ],
    );

    try {
      if (await explicitSendIntent.canResolveActivity()) {
        await explicitSendIntent.launch();
        return true;
      }
    } catch (_) {}

    // 4. Try explicit ACTION_SEND targeting F-Droid ImageToolbox package
    final fossSendIntent = AndroidIntent(
      action: 'android.intent.action.SEND',
      package: imageToolboxFossPackage,
      type: mimeType,
      arguments: <String, dynamic>{
        'android.intent.extra.STREAM': fileUri,
      },
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
      ],
    );

    try {
      if (await fossSendIntent.canResolveActivity()) {
        await fossSendIntent.launch();
        return true;
      }
    } catch (_) {}

    // 5. Fallback: Generic ACTION_EDIT with image/* MIME type
    final genericEditIntent = AndroidIntent(
      action: 'android.intent.action.EDIT',
      data: fileUri,
      type: mimeType,
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
        Flag.FLAG_GRANT_WRITE_URI_PERMISSION,
      ],
    );

    try {
      if (await genericEditIntent.canResolveActivity()) {
        await genericEditIntent.launch();
        return true;
      }
    } catch (_) {}

    // 6. Chooser fallback: ACTION_SEND chooser
    try {
      final chooserIntent = AndroidIntent(
        action: 'android.intent.action.SEND',
        type: mimeType,
        arguments: <String, dynamic>{
          'android.intent.extra.STREAM': fileUri,
        },
        flags: <int>[
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ],
      );
      await chooserIntent.launchChooser('Edit in ImageToolbox or Image Editor');
      return true;
    } catch (_) {}

    return false;
  }
}

/// Sleek fade overlay providing cinema-grade visual handoff transition.
class _HandoffFadeTransitionOverlay extends StatefulWidget {
  const _HandoffFadeTransitionOverlay();

  @override
  State<_HandoffFadeTransitionOverlay> createState() =>
      _HandoffFadeTransitionOverlayState();
}

class _HandoffFadeTransitionOverlayState
    extends State<_HandoffFadeTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _opacityAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Material(
            color: Colors.black.withOpacity(0.68),
            child: Center(
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E26),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF9C27B0).withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF9C27B0).withOpacity(0.25),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE040FB).withOpacity(0.4),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Opening ImageToolbox',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Handoff in progress...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
