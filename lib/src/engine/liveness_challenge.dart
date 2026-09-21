import 'face_signals.dart';

/// A single thing the customer is asked to do.
///
/// Every challenge is a *movement*, not a pose: the customer has to reach a
/// position and then come back. A held photograph can be tilted to satisfy a
/// threshold, but it cannot return to centre on cue.
enum LivenessChallenge {
  turnLeft,
  turnRight;

  /// What the customer is told to do. Written as an instruction, in the
  /// second person, because it is read while their face fills the screen and
  /// there is no room to explain.
  String get prompt => switch (this) {
    LivenessChallenge.turnLeft => 'Turn your head to your left, then back',
    LivenessChallenge.turnRight => 'Turn your head to your right, then back',
  };

  /// Whether this frame is at the far end of the movement.
  bool isReachedBy(FaceSignals signals) {
    if (!signals.isUsable) return false;

    return switch (this) {
      // Yaw is signed from the subject's point of view, so their left is
      // negative. Getting this backwards asks people to turn the wrong way,
      // which reads as the detector being broken.
      LivenessChallenge.turnLeft => signals.yaw <= -_turnDegrees,
      LivenessChallenge.turnRight => signals.yaw >= _turnDegrees,
    };
  }

  /// Whether this frame is back at rest, which completes the movement.
  ///
  /// Looser than [FaceSignals.isNeutral] on the axes this challenge does not
  /// use: coming back from a head turn should not also have to be level.
  bool isReturnedBy(FaceSignals signals) {
    if (!signals.isUsable) return false;

    return switch (this) {
      LivenessChallenge.turnLeft ||
      LivenessChallenge.turnRight => signals.yaw.abs() < _yawCentre,
    };
  }

  /// Generous enough that an ordinary head turn clears it, tight enough that
  /// a still photograph tilted in front of the lens does not.
  static const double _turnDegrees = 25;

  /// Coming back has to be looser than going out, or a customer who overshoots
  /// slightly can never finish.
  static const double _yawCentre = 15;
}
