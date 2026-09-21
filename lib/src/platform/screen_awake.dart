import 'package:flutter/services.dart';

/// Holds the screen on while something is being watched through the camera.
///
/// The liveness check asks a customer to look at their phone and move their
/// head — which registers as no touch at all, so the idle timer runs down and
/// the display dims mid-gesture. Other apps that run a face check keep the
/// screen lit for its duration, and the difference is obvious: ours went dark
/// on people who were doing exactly what they were told.
///
/// Native on both sides rather than a package: it is `isIdleTimerDisabled` on
/// iOS and one window flag on Android, and this feature already keeps its
/// platform work in the plugins it owns.
abstract final class ScreenAwake {
  static const MethodChannel _channel = MethodChannel(
    'com.universalweblinks.liveness_kit/screen_awake',
  );

  /// Keeps the display on until [release] is called.
  static Future<void> keepOn() => _set(true);

  /// Hands the screen back to the system's idle timer.
  ///
  /// Must be called even on the failure paths. A wake lock left on outlives
  /// the screen that needed it and quietly drains the battery.
  static Future<void> release() => _set(false);

  static Future<void> _set(bool awake) async {
    try {
      await _channel.invokeMethod<void>('setKeepAwake', awake);
    } on PlatformException {
      // A screen that dims is a nuisance, not a failure. Never take the check
      // down over it.
    } on MissingPluginException {
      // No implementation on this platform or build.
    }
  }
}
