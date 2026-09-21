/// A gesture-based face liveness check: turn your head, hold still, photo.
///
/// Two layers, either of which can be used on its own.
///
/// The screen — [LivenessCapture] — opens the front camera, runs the
/// sequence and pops a [LivenessResult]. The engine — [LivenessSession] —
/// is plain Dart with no camera, platform or widget code in it: feed it
/// [FaceSignals] and it says what to ask for next. Face detection sits behind
/// [FaceDetectorPort], with a native implementation on each platform and
/// nothing to configure.
///
/// Detection is Apple Vision on iOS and MediaPipe Face Landmarker on
/// Android. Neither pulls in Firebase or ML Kit.
///
/// None of this proves a live human. The app runs on the subject's device and
/// anything it measures can be lied to; the gestures raise the cost of a
/// casual attempt, and whatever checks the photo on your server is what
/// actually decides.
library;

export 'src/detector/face_detector_port.dart';
export 'src/detector/native_face_detector.dart';
export 'src/engine/camera_frame_geometry.dart';
export 'src/engine/face_signals.dart';
export 'src/engine/liveness_challenge.dart';
export 'src/engine/liveness_session.dart';
export 'src/platform/screen_awake.dart';
export 'src/ui/liveness_capture.dart';
export 'src/ui/liveness_strings.dart';
export 'src/ui/liveness_theme.dart';
