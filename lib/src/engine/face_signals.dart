/// One frame's reading of the face in front of the camera.
///
/// This is the whole contract between the native detectors and everything
/// above them. Apple Vision on iOS and MediaPipe on Android produce very
/// different intermediate data; both reduce to this, so the challenge logic
/// never learns which platform it is running on and stays testable without a
/// camera.
class FaceSignals {
  /// How many faces are in frame. A challenge only counts while this is
  /// exactly one — two faces means someone is being coached, or held up to
  /// the lens beside a photo.
  final int faceCount;

  /// Head rotation left/right in degrees. Negative is the subject's left.
  final double yaw;

  /// Head rotation up/down in degrees. Negative is chin down.
  final double pitch;

  /// How open the mouth is, 0 closed to 1 wide.
  final double mouthOpenness;

  /// How open the eyes are, 0 shut to 1 wide. Averaged across both.
  final double eyeOpenness;

  /// The share of the frame's height the face spans, 0 to 1. Guards against a
  /// face held far enough back that the detector is reading a photo on a
  /// screen rather than a person.
  ///
  /// Height, not the shorter side, which is what this used to claim: Vision
  /// normalises its bounding box to the image, and MediaPipe normalises its
  /// landmarks the same way. Both frames are upright by the time they are
  /// measured, so height is the long side and the same number means the same
  /// thing on either platform.
  final double faceFillRatio;

  const FaceSignals({
    required this.faceCount,
    required this.yaw,
    required this.pitch,
    required this.mouthOpenness,
    required this.eyeOpenness,
    required this.faceFillRatio,
  });

  /// Nothing detected. What a detector reports for an empty frame.
  static const empty = FaceSignals(
    faceCount: 0,
    yaw: 0,
    pitch: 0,
    mouthOpenness: 0,
    eyeOpenness: 0,
    faceFillRatio: 0,
  );

  /// Whether the frame is usable at all: one face, close enough, eyes open.
  ///
  /// Eyes are included because a face with both eyes shut for the whole
  /// session is usually a photograph rather than a person.
  bool get isUsable =>
      faceCount == 1 && faceFillRatio >= minimumFaceFill && eyeOpenness > 0.2;

  /// Facing forward and at rest. Gates the start of a session and the photo
  /// at the end of it.
  ///
  /// Pitch is given far more room than yaw on purpose: a phone is held below
  /// eye level, so a perfectly attentive face is already tilted down. Holding
  /// pitch to the same tolerance as yaw left those customers stuck on
  /// "position your face" with nothing they could do about it.
  /// Pitch is reported but does not gate this, deliberately.
  ///
  /// It gated nothing on iOS either: `VNDetectFaceLandmarksRequest` leaves a
  /// face's pitch nil, so that side has always sent a constant zero and the
  /// check passed for free. Android derives a real number from MediaPipe's
  /// facial transformation matrix, whose axis convention we have never been
  /// able to confirm — and a resting head reading anywhere near 180 makes this
  /// permanently false. That is the shape of the Android report: the camera
  /// opens, the face is right there, and the screen never leaves "Position
  /// your face".
  ///
  /// The gesture that needed pitch is gone, so the only thing this term could
  /// still do is fail. What remains is enough: one face, close enough, eyes
  /// open, facing forward, mouth shut.
  bool get isNeutral =>
      isUsable && yaw.abs() < neutralYawDegrees && mouthOpenness < 0.2;

  static const double minimumFaceFill = 0.25;
  static const double neutralYawDegrees = 15;

  factory FaceSignals.fromMap(Map<Object?, Object?> map) {
    double number(Object? value) => value is num ? value.toDouble() : 0;

    return FaceSignals(
      faceCount: (map['faceCount'] as num?)?.toInt() ?? 0,
      yaw: number(map['yaw']),
      pitch: number(map['pitch']),
      mouthOpenness: number(map['mouthOpenness']),
      eyeOpenness: number(map['eyeOpenness']),
      faceFillRatio: number(map['faceFillRatio']),
    );
  }
}
