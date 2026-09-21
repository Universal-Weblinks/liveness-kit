import 'dart:typed_data';

import '../engine/face_signals.dart';

/// One plane of a camera frame, with the strides needed to read it.
///
/// The strides are not decoration. Camera hardware pads each row out to an
/// alignment boundary and may interleave chroma samples, so a plane's bytes
/// are almost never `width * height` laid end to end. Anything that reads them
/// without the strides produces a sheared or interleaved mess, and a detector
/// handed that simply reports no face.
class FacePlane {
  const FacePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;

  /// Distance in bytes from the start of one row to the start of the next.
  final int bytesPerRow;

  /// Distance in bytes between two samples in the same row. Two for a chroma
  /// plane the hardware has already interleaved.
  final int bytesPerPixel;
}

/// One camera frame, in the form the native detectors expect.
class FaceFrame {
  /// The planes exactly as the camera delivered them.
  ///
  /// One on iOS, which streams BGRA. Three on Android, which streams planar
  /// YUV — and the packing into something a detector can read is done on the
  /// native side rather than asked of the camera plugin.
  ///
  /// The plugin was asked, once. `ImageFormatGroup.nv21` routes every frame
  /// through `ImageProxyUtils.areUVPlanesNV21`, which advances the V buffer by
  /// one byte to compare it against U — and on a device whose V plane ends
  /// exactly at its limit that throws `newPosition > limit` before a frame is
  /// ever built. The stream started, no frame arrived, and the liveness screen
  /// sat on "Position your face" with the camera plainly running.
  final List<FacePlane> planes;

  final int width;
  final int height;

  /// Clockwise rotation, in degrees, needed to make the frame upright. The
  /// sensor is usually mounted sideways, and a detector fed a sideways face
  /// reports no face at all.
  final int rotationDegrees;

  /// Platform image format, passed through so the native side can decode
  /// without guessing.
  final String format;

  const FaceFrame({
    required this.planes,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.format,
  });
}

/// Reads a face out of a camera frame.
///
/// Implemented natively — Apple Vision on iOS, MediaPipe on Android — behind
/// this one method so the challenge logic and the UI never depend on either.
/// A fake stands in for both in tests.
abstract class FaceDetectorPort {
  /// Whether detection is available at all. False on a platform with no
  /// implementation, or when the model failed to load, so the caller can fall
  /// back rather than leave the customer staring at a prompt nothing answers.
  Future<bool> isAvailable();

  /// Why detection is unavailable, when it is, or null if it is fine or the
  /// platform cannot say.
  ///
  /// Diagnostic only. A detector that will not start is otherwise completely
  /// silent from the customer's side and from ours — the failure is caught so
  /// it cannot take KYC down with it, which also means nothing surfaces.
  Future<String?> unavailableReason();

  /// Reads one frame. Returns [FaceSignals.empty] when nothing is found.
  Future<FaceSignals> detect(FaceFrame frame);

  /// Releases native resources.
  Future<void> dispose();
}
