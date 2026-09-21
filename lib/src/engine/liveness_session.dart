import 'dart:math';

import 'face_signals.dart';
import 'liveness_challenge.dart';

/// Where a session has got to.
enum LivenessStage {
  /// Waiting for a single, close-enough face before asking for anything.
  findingFace,

  /// A challenge is on screen and being watched for.
  challenging,

  /// Every challenge is done; waiting for a still, forward-facing frame to
  /// photograph.
  holding,

  /// The photo should be taken now.
  passed,
}

/// Why a session started over.
enum LivenessRestart {
  /// The customer did not complete a challenge in time.
  timedOut,

  /// The face left the frame for longer than the grace period.
  faceLost,

  /// A second face entered the frame.
  crowded,
}

/// Runs the turn / nod / open-mouth sequence.
///
/// Deliberately free of camera, platform and widget code: it takes one
/// [FaceSignals] at a time and says what to show next. That keeps the part
/// with the actual rules in it testable without a device, which matters
/// because the failure modes here are all timing and ordering.
///
/// Four things make the sequence harder to fake than a single photo. The
/// challenges are drawn in a random order, so a recording of a previous
/// session answers the wrong prompts. Each one is a *movement* — reach the
/// pose, then come back — which a held photograph cannot perform. The far end
/// must be held for several consecutive frames, so a flicker does not count.
/// And the photo is taken only after a still, forward-facing hold, so the
/// frame that reaches the server is a usable portrait rather than whatever
/// the customer's face was doing mid-gesture.
///
/// None of that is proof of a live human — the app runs on the customer's
/// device and anything it measures can be lied to. It raises the cost of a
/// casual attempt; the server-side check is what actually decides.
class LivenessSession {
  LivenessSession({
    List<LivenessChallenge>? challenges,
    this.framesToHold = 3,
    this.challengeTimeout = const Duration(seconds: 20),
    this.faceLostGrace = const Duration(milliseconds: 1500),
    Random? random,
  }) : _random = random ?? Random.secure(),
       _fixedChallenges = challenges {
    _challenges = challenges ?? _drawChallenges(_random);
  }

  /// How many consecutive qualifying frames count as holding a pose. At a
  /// typical preview rate this is a fraction of a second — enough to reject
  /// noise, short enough not to feel like a hold.
  final int framesToHold;

  /// How long a single challenge may take before the session starts over.
  final Duration challengeTimeout;

  /// How long the face may be out of frame before the sequence is abandoned.
  ///
  /// Without this a single dropped detection — a hand passing the lens, a
  /// moment of backlight — would restart a sequence the customer is halfway
  /// through.
  final Duration faceLostGrace;

  final Random _random;
  final List<LivenessChallenge>? _fixedChallenges;

  late List<LivenessChallenge> _challenges;
  int _index = 0;
  int _consecutiveHits = 0;
  bool _reachedFarEnd = false;

  /// Whether the face has yet to come to rest before the next challenge is
  /// watched for.
  ///
  /// Set between challenges, never before the first — finding the face
  /// already required a settled, forward-facing frame.
  ///
  /// This is what stops one sweep of the head answering both turns. Without
  /// it, going left, through centre and on to the right satisfies "turn left,
  /// then back" and "turn right" in a single motion, because passing through
  /// centre is indistinguishable from returning to it. Costs a real customer
  /// nothing: the next prompt only appears once the previous gesture is done,
  /// and they are facing forward while they read it.
  bool _awaitingSettle = false;
  LivenessStage _stage = LivenessStage.findingFace;
  DateTime? _challengeStartedAt;
  DateTime? _lastSawFaceAt;

  /// How many times the sequence has started over. The screen uses this to
  /// stop asking after a while and offer a person instead.
  int attempts = 0;

  /// Why the sequence last started over, for the message on screen.
  LivenessRestart? restartReason;

  LivenessStage get stage => _stage;
  List<LivenessChallenge> get challenges => List.unmodifiable(_challenges);

  /// The challenge on screen, or null when there is nothing to ask for.
  LivenessChallenge? get currentChallenge =>
      _stage == LivenessStage.challenging ? _challenges[_index] : null;

  int get completedCount => _index;
  int get totalCount => _challenges.length;
  bool get isFinished => _stage == LivenessStage.passed;

  /// Feeds one frame in and moves the session on.
  ///
  /// [now] is injected so the timeout can be tested without waiting for one.
  void onFrame(FaceSignals signals, {DateTime? now}) {
    if (isFinished) return;
    final moment = now ?? DateTime.now();

    if (_handleFacePresence(signals, moment)) return;

    switch (_stage) {
      case LivenessStage.findingFace:
        if (signals.isNeutral) _beginChallenge(moment);

      case LivenessStage.challenging:
        _onChallengeFrame(signals, moment);

      case LivenessStage.holding:
        // The photo has to be a forward-facing portrait, so the last thing
        // the sequence asks for is stillness rather than another movement.
        _consecutiveHits = signals.isNeutral ? _consecutiveHits + 1 : 0;
        if (_consecutiveHits >= framesToHold) _stage = LivenessStage.passed;

      case LivenessStage.passed:
        return;
    }
  }

  /// Returns true when the frame was consumed by presence handling.
  bool _handleFacePresence(FaceSignals signals, DateTime moment) {
    // Two faces is not an accident worth waiting out: it is the shape of
    // someone holding a photograph up beside their own face.
    if (signals.faceCount > 1) {
      _restart(LivenessRestart.crowded);
      return true;
    }

    if (signals.isUsable) {
      _lastSawFaceAt = moment;
      return false;
    }

    // Nothing to lose before the sequence has started.
    if (_stage == LivenessStage.findingFace) return true;

    final lastSeen = _lastSawFaceAt;
    if (lastSeen != null && moment.difference(lastSeen) > faceLostGrace) {
      _restart(LivenessRestart.faceLost);
    }
    return true;
  }

  void _onChallengeFrame(FaceSignals signals, DateTime moment) {
    final startedAt = _challengeStartedAt;
    if (startedAt != null && moment.difference(startedAt) > challengeTimeout) {
      _restart(LivenessRestart.timedOut);
      return;
    }

    if (_awaitingSettle) {
      _consecutiveHits = signals.isNeutral ? _consecutiveHits + 1 : 0;
      if (_consecutiveHits >= framesToHold) {
        _awaitingSettle = false;
        _consecutiveHits = 0;
      }
      return;
    }

    final challenge = _challenges[_index];

    if (!_reachedFarEnd) {
      if (!challenge.isReachedBy(signals)) {
        // A single dropped frame is normal at preview rates. The count resets
        // rather than the session restarting.
        _consecutiveHits = 0;
        return;
      }
      _consecutiveHits++;
      if (_consecutiveHits >= framesToHold) {
        _reachedFarEnd = true;
        _consecutiveHits = 0;
      }
      return;
    }

    // Coming back is what completes it. Reaching the pose alone proves
    // nothing a tilted photograph could not.
    if (challenge.isReturnedBy(signals)) _advance(moment);
  }

  void _advance(DateTime moment) {
    _index++;
    _consecutiveHits = 0;
    _reachedFarEnd = false;

    if (_index >= _challenges.length) {
      _stage = LivenessStage.holding;
      _challengeStartedAt = null;
    } else {
      _challengeStartedAt = moment;
      _awaitingSettle = true;
    }
  }

  void _beginChallenge(DateTime moment) {
    _stage = LivenessStage.challenging;
    _consecutiveHits = 0;
    _reachedFarEnd = false;
    _awaitingSettle = false;
    _challengeStartedAt = moment;
  }

  /// Starts over rather than failing.
  ///
  /// A customer who lost the thread has done nothing wrong, and a dead end
  /// with a "start again" button is a slower version of starting again. The
  /// challenges are redrawn so a restart cannot be answered with the
  /// movements just made.
  void _restart(LivenessRestart reason) {
    attempts++;
    restartReason = reason;
    _stage = LivenessStage.findingFace;
    _index = 0;
    _consecutiveHits = 0;
    _reachedFarEnd = false;
    _awaitingSettle = false;
    _challengeStartedAt = null;
    _lastSawFaceAt = null;
    _challenges = _fixedChallenges ?? _drawChallenges(_random);
  }

  /// Both turns, in a random order.
  ///
  /// The turns are the only gestures that proved reliable on a device. The
  /// chin lift that used to sit here never fired: iOS populates a face's yaw
  /// from a landmarks request but not its pitch, so the reading was a constant
  /// zero and the challenge could not be satisfied by any real movement.
  ///
  /// Pairing the two turns used to be refused on the grounds that left and
  /// right back-to-back is one sweep of the head — a single motion clearing
  /// two challenges, which is easier to do by accident and easier to replay.
  /// That objection is answered by [_awaitingSettle] rather than by avoiding
  /// the pairing: the face has to come to rest facing forward between them, so
  /// one continuous sweep no longer gets through.
  static List<LivenessChallenge> _drawChallenges(Random random) {
    final drawn = <LivenessChallenge>[
      LivenessChallenge.turnLeft,
      LivenessChallenge.turnRight,
    ]..shuffle(random);
    return drawn;
  }
}
