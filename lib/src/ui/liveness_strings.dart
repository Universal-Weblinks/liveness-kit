import '../engine/liveness_challenge.dart';
import '../engine/liveness_session.dart';

/// Every word the capture screen can say.
///
/// Gathered in one place so a host app can translate them, or match its own
/// voice, without forking the screen. The defaults are written to be read
/// while someone is holding a phone at arm's length and moving their head:
/// short, in the imperative, and never blaming them for a failure the camera
/// or the light caused.
class LivenessStrings {
  const LivenessStrings({
    this.appBarTitle = 'Liveness check',
    this.findingFaceTitle = 'Position your face',
    this.findingFaceSubtitle = 'Fit your face inside the circle in good light.',
    this.timedOut = "That took a little long. Let's start again.",
    this.faceLost = 'We lost sight of your face. Starting again.',
    this.crowded = 'Only your face should be in frame. Starting again.',
    this.challengeSubtitle = 'Take your time.',
    this.holdingTitle = 'Look straight ahead',
    this.holdingSubtitle = 'Hold still for the photo.',
    this.passedTitle = 'All done',
    this.passedSubtitle = 'Taking your photo…',
    this.turnLeft = 'Turn your head to your left, then back',
    this.turnRight = 'Turn your head to your right, then back',
    this.unavailableTitle = 'Face check unavailable',
    this.unavailableBody =
        'We could not start the face check on this device. '
        'Your photo can be reviewed another way.',
    this.cameraProblemTitle = 'Camera problem',
    this.cameraOpenFailed = 'We could not open the camera.',
    this.captureFailed = 'We could not save that photo. Please try again.',
    this.goBack = 'Go back',
    this.tryAgain = 'Try again',
    this.escapeHatch = 'Having trouble? Skip the face check',
  });

  final String appBarTitle;

  final String findingFaceTitle;
  final String findingFaceSubtitle;

  /// Why the sequence started over. Shown in place of [findingFaceSubtitle].
  final String timedOut;
  final String faceLost;
  final String crowded;

  final String challengeSubtitle;
  final String holdingTitle;
  final String holdingSubtitle;
  final String passedTitle;
  final String passedSubtitle;

  /// What each gesture is asked for as. The order is drawn at random, so each
  /// prompt has to stand on its own — "and then the other way" would be read
  /// by someone who was never asked for the first one.
  ///
  /// Each names the movement *and* the return, because that is what the
  /// challenge actually measures: reaching the pose is half of it.
  final String turnLeft;
  final String turnRight;

  final String unavailableTitle;
  final String unavailableBody;
  final String cameraProblemTitle;
  final String cameraOpenFailed;
  final String captureFailed;

  final String goBack;
  final String tryAgain;

  /// The way out, offered after two failed attempts.
  ///
  /// Some people cannot complete the gestures, and a check with no exit traps
  /// them on this screen. Shown only when the host provides somewhere for it
  /// to go.
  final String escapeHatch;

  String promptFor(LivenessChallenge challenge) => switch (challenge) {
    LivenessChallenge.turnLeft => turnLeft,
    LivenessChallenge.turnRight => turnRight,
  };

  String restartReason(LivenessRestart reason) => switch (reason) {
    LivenessRestart.timedOut => timedOut,
    LivenessRestart.faceLost => faceLost,
    LivenessRestart.crowded => crowded,
  };
}
