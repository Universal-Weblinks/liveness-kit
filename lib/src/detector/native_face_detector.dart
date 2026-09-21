import 'package:flutter/services.dart';

import 'face_detector_port.dart';
import '../engine/face_signals.dart';

/// Talks to the platform face detectors.
///
/// Frames are sent over rather than the preview being replaced with a native
/// view: the app already has a working camera screen, and a platform view
/// would mean rebuilding it twice. The caller is expected to throttle — the
/// challenge logic needs a handful of readings a second, not sixty.
class NativeFaceDetector implements FaceDetectorPort {
  static const MethodChannel _channel = MethodChannel(
    'com.universalweblinks.liveness_kit/face_detector',
  );

  bool? _available;

  @override
  Future<bool> isAvailable() async {
    // Cached: the answer cannot change within a session, and this is asked on
    // every camera open.
    final cached = _available;
    if (cached != null) return cached;

    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return _available = result ?? false;
    } on PlatformException {
      return _available = false;
    } on MissingPluginException {
      // No native implementation on this platform or build.
      return _available = false;
    }
  }

  @override
  Future<String?> unavailableReason() async {
    try {
      return await _channel.invokeMethod<String>('unavailableReason');
    } on PlatformException catch (error) {
      return error.message;
    } on MissingPluginException {
      return 'No face detector is built into this app.';
    }
  }

  @override
  Future<FaceSignals> detect(FaceFrame frame) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'detect',
        <String, Object?>{
          // Each plane with its own strides, already typed lists, so
          // nothing is copied on the way across. The packing into something
          // a detector can read happens natively.
          'planes': [
            for (final plane in frame.planes)
              <String, Object?>{
                'bytes': plane.bytes,
                'bytesPerRow': plane.bytesPerRow,
                'bytesPerPixel': plane.bytesPerPixel,
              },
          ],
          'width': frame.width,
          'height': frame.height,
          'rotationDegrees': frame.rotationDegrees,
          'format': frame.format,
        },
      );

      if (result == null) return FaceSignals.empty;
      return FaceSignals.fromMap(result);
    } on PlatformException {
      // A frame that cannot be decoded is treated as "no face" rather than an
      // error: dropping one reading of many is invisible, and failing the
      // session over it would be wrong.
      return FaceSignals.empty;
    } on MissingPluginException {
      return FaceSignals.empty;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Nothing useful to do; the native side releases on its own teardown.
    } on MissingPluginException {
      // No implementation to release.
    }
  }
}
