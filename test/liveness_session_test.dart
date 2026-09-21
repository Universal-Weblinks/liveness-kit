import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_kit/liveness_kit.dart';

FaceSignals face({
  int faceCount = 1,
  double yaw = 0,
  double pitch = 0,
  double mouthOpenness = 0,
  double eyeOpenness = 0.9,
  double faceFillRatio = 0.5,
}) => FaceSignals(
  faceCount: faceCount,
  yaw: yaw,
  pitch: pitch,
  mouthOpenness: mouthOpenness,
  eyeOpenness: eyeOpenness,
  faceFillRatio: faceFillRatio,
);

/// The far end of a movement.
FaceSignals reach(LivenessChallenge challenge) => switch (challenge) {
  LivenessChallenge.turnLeft => face(yaw: -35),
  LivenessChallenge.turnRight => face(yaw: 35),
};

void feed(LivenessSession session, FaceSignals signals, int times) {
  for (var i = 0; i < times; i++) {
    session.onFrame(signals);
  }
}

/// Settle, reach the pose, hold it, then come back — one whole challenge, in
/// the order a customer performs it.
///
/// The settle at the front is not decoration. Between challenges the session
/// waits for the face to come to rest facing forward, which is what stops one
/// continuous sweep of the head answering a left turn and a right turn at
/// once. Before the first challenge there is nothing to settle and these
/// frames do nothing.
void perform(LivenessSession session, LivenessChallenge challenge) {
  feed(session, face(), session.framesToHold);
  feed(session, reach(challenge), session.framesToHold);
  session.onFrame(face());
}

void main() {
  /// What a face has to be doing before the first prompt appears.
  ///
  /// From an Android device: the camera opened, the face was in the circle,
  /// and the screen never left "Position your face". iOS was fine on the same
  /// build.
  ///
  /// The only term in this check that behaves differently between the two is
  /// pitch. Vision leaves it nil for a landmarks request, so iOS has always
  /// sent a constant zero and passed for free; Android derives a real angle
  /// from MediaPipe's transformation matrix, and a convention mismatch there
  /// puts a resting head near 180, which can never pass. It gated nothing on
  /// one platform and everything on the other, so it gates nothing now.
  group('being ready to start', () {
    FaceSignals ready({double pitch = 0}) => face(pitch: pitch);

    test('a settled face is ready', () {
      expect(ready().isNeutral, isTrue);
    });

    test('whatever the pitch reads', () {
      // Every one of these is a head someone is holding still in front of a
      // phone. None of them may be a reason to refuse to start.
      for (final reading in [0.0, -40.0, 40.0, 179.0, -179.0]) {
        expect(
          ready(pitch: reading).isNeutral,
          isTrue,
          reason: 'pitch $reading blocked the check from ever starting',
        );
      }
    });

    test('but a turned head is still not ready', () {
      expect(face(yaw: -40).isNeutral, isFalse);
      expect(face(yaw: 40).isNeutral, isFalse);
    });

    test('nor an open mouth, a lost face, or one held too far back', () {
      expect(face(mouthOpenness: 0.8).isNeutral, isFalse);
      expect(face(faceCount: 0).isNeutral, isFalse);
      expect(face(faceCount: 2).isNeutral, isFalse);
      expect(face(faceFillRatio: 0.1).isNeutral, isFalse);
      expect(face(eyeOpenness: 0.0).isNeutral, isFalse);
    });
  });

  group('which way is left', () {
    test('the prompt naming a side is met by turning to that side', () {
      const left = LivenessChallenge.turnLeft;
      const right = LivenessChallenge.turnRight;

      expect(left.prompt, contains('your left'));
      expect(right.prompt, contains('your right'));

      // Negative is the subject's left. Flip either detector's sign and the
      // app asks people to turn the wrong way.
      expect(left.isReachedBy(face(yaw: -35)), isTrue);
      expect(left.isReachedBy(face(yaw: 35)), isFalse);

      expect(right.isReachedBy(face(yaw: 35)), isTrue);
      expect(right.isReachedBy(face(yaw: -35)), isFalse);
    });

    test('coming back to centre is neither side', () {
      expect(LivenessChallenge.turnLeft.isReturnedBy(face(yaw: 0)), isTrue);
      expect(LivenessChallenge.turnRight.isReturnedBy(face(yaw: 0)), isTrue);
    });
  });

  group('starting up', () {
    test('asks for nothing until a usable face is in frame', () {
      final session = LivenessSession();

      session.onFrame(FaceSignals.empty);
      expect(session.stage, LivenessStage.findingFace);
      expect(session.currentChallenge, isNull);

      session.onFrame(face());
      expect(session.stage, LivenessStage.challenging);
      expect(session.currentChallenge, isNotNull);
    });

    test('a phone held below eye level still counts as facing forward', () {
      // People look down at a phone, so a resting head is already pitched.
      // Holding pitch to the same tolerance as yaw stranded those customers
      // on "position your face" with nothing they could do about it.
      final session = LivenessSession();

      session.onFrame(face(pitch: -20));

      expect(session.stage, LivenessStage.challenging);
    });

    test('a face too far from the camera does not start it', () {
      final session = LivenessSession();

      session.onFrame(face(faceFillRatio: 0.1));

      expect(session.stage, LivenessStage.findingFace);
    });
  });

  group('a challenge is a movement, not a pose', () {
    test('reaching the pose is not enough on its own', () {
      // A held photograph can be tilted to satisfy a threshold. Coming back is
      // the part it cannot do.
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());

      feed(
        session,
        reach(LivenessChallenge.turnRight),
        session.framesToHold * 3,
      );

      expect(session.completedCount, 0);
      expect(session.stage, LivenessStage.challenging);
    });

    test('reaching then returning completes it', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());

      perform(session, LivenessChallenge.turnRight);

      expect(session.completedCount, 1);
    });

    test('the far end has to be held, not brushed past', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
        framesToHold: 3,
      );
      session.onFrame(face());

      session.onFrame(reach(LivenessChallenge.turnRight));
      session.onFrame(face());

      expect(session.completedCount, 0);
    });

    test(
      'returning is looser than reaching, so a slight overshoot still ends',
      () {
        // Requiring the same tolerance both ways strands anyone who does not
        // land exactly back on centre.
        final session = LivenessSession(
          challenges: [LivenessChallenge.turnLeft],
        );
        session.onFrame(face());
        feed(session, reach(LivenessChallenge.turnLeft), session.framesToHold);

        session.onFrame(face(yaw: -12));

        expect(session.completedCount, 1);
      },
    );

    test('a mouth must close again, not merely open', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());
      feed(session, reach(LivenessChallenge.turnRight), session.framesToHold);
      expect(session.completedCount, 0);

      session.onFrame(face(yaw: 0));

      expect(session.completedCount, 1);
    });
  });

  group('finishing', () {
    test('the photo waits for a still, forward-facing hold', () {
      // Capturing the instant the last challenge ends photographs a face
      // mid-gesture, and that frame is what the provider matches against.
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());
      perform(session, LivenessChallenge.turnRight);

      expect(session.stage, LivenessStage.holding);

      feed(session, face(), session.framesToHold);

      expect(session.stage, LivenessStage.passed);
      expect(session.isFinished, isTrue);
    });

    test('a face still moving does not get photographed', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());
      perform(session, LivenessChallenge.turnRight);

      feed(session, face(yaw: 40), session.framesToHold);

      expect(session.stage, LivenessStage.holding);
    });

    test('every challenge is performed before the hold', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnLeft, LivenessChallenge.turnRight],
      );
      session.onFrame(face());

      for (final challenge in session.challenges) {
        perform(session, challenge);
      }
      feed(session, face(), session.framesToHold);

      expect(session.stage, LivenessStage.passed);
    });
  });

  group('losing the thread starts over rather than failing', () {
    test('a brief loss of the face is tolerated', () {
      // A hand across the lens or a moment of backlight should not undo a
      // sequence the customer is halfway through.
      final start = DateTime(2026, 9, 3, 12);
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face(), now: start);

      session.onFrame(
        FaceSignals.empty,
        now: start.add(const Duration(milliseconds: 400)),
      );

      expect(session.attempts, 0);
      expect(session.stage, LivenessStage.challenging);
    });

    test('a long loss restarts the sequence', () {
      final start = DateTime(2026, 9, 3, 12);
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face(), now: start);

      session.onFrame(
        FaceSignals.empty,
        now: start.add(const Duration(seconds: 3)),
      );

      expect(session.stage, LivenessStage.findingFace);
      expect(session.restartReason, LivenessRestart.faceLost);
      expect(session.attempts, 1);
    });

    test('a challenge not met in time restarts it', () {
      final start = DateTime(2026, 9, 3, 12);
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
        challengeTimeout: const Duration(seconds: 20),
      );
      session.onFrame(face(), now: start);

      session.onFrame(face(), now: start.add(const Duration(seconds: 21)));

      expect(session.stage, LivenessStage.findingFace);
      expect(session.restartReason, LivenessRestart.timedOut);
    });

    test('a second face restarts it immediately, with no grace', () {
      // The shape of someone holding a photograph up beside their own face.
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());

      session.onFrame(face(faceCount: 2));

      expect(session.stage, LivenessStage.findingFace);
      expect(session.restartReason, LivenessRestart.crowded);
    });

    test('progress is discarded on a restart', () {
      // No injected clock here: a crowded frame restarts regardless of time,
      // and mixing a fixed start with real frame times would trip the
      // challenge timeout instead of the thing under test.
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight, LivenessChallenge.turnRight],
      );
      session.onFrame(face());
      perform(session, LivenessChallenge.turnRight);
      expect(session.completedCount, 1);

      session.onFrame(face(faceCount: 2));

      expect(session.completedCount, 0);
    });

    test('a finished session ignores further frames', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnRight],
      );
      session.onFrame(face());
      perform(session, LivenessChallenge.turnRight);
      feed(session, face(), session.framesToHold);
      expect(session.stage, LivenessStage.passed);

      session.onFrame(face(faceCount: 2));

      expect(session.stage, LivenessStage.passed);
    });
  });

  group('the draw', () {
    test('asks for both turns', () {
      // The turns are the only gestures that fire on a real device. The chin
      // lift that used to partner one of them never could: iOS gives a
      // landmarks request a face's yaw but not its pitch, so the reading was
      // a constant zero.
      for (var seed = 0; seed < 50; seed++) {
        final drawn = LivenessSession(random: Random(seed)).challenges;

        expect(drawn, hasLength(2));
        expect(drawn, contains(LivenessChallenge.turnLeft));
        expect(drawn, contains(LivenessChallenge.turnRight));
      }
    });

    test('the order varies between sessions', () {
      final orders = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        orders.add(LivenessSession(random: Random(seed)).challenges.join(','));
      }

      expect(
        orders.length,
        greaterThan(1),
        reason: 'a fixed order can be answered with a recording',
      );
    });

    /// The reason both turns can now be asked for at all.
    ///
    /// Left and right back-to-back is one motion, and passing through centre
    /// on the way looks exactly like returning to it — so without this a
    /// single sweep of the head would answer both challenges, which is easy to
    /// do by accident and easy to replay.
    test('one sweep of the head does not answer both turns', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnLeft, LivenessChallenge.turnRight],
      );

      feed(session, face(), session.framesToHold);
      expect(session.currentChallenge, LivenessChallenge.turnLeft);

      // One continuous motion: hold left, pass through centre without
      // stopping, carry on to the right and hold there.
      feed(session, face(yaw: -35), session.framesToHold);
      session.onFrame(face(yaw: 0));
      feed(session, face(yaw: 35), session.framesToHold);
      session.onFrame(face(yaw: 0));

      expect(
        session.isFinished,
        isFalse,
        reason: 'the sweep never came to rest between the two turns',
      );
      expect(session.completedCount, 1, reason: 'only the left turn counted');
    });

    test('pausing between the turns does answer both', () {
      final session = LivenessSession(
        challenges: [LivenessChallenge.turnLeft, LivenessChallenge.turnRight],
      );

      perform(session, LivenessChallenge.turnLeft);
      perform(session, LivenessChallenge.turnRight);
      feed(session, face(), session.framesToHold);

      expect(session.isFinished, isTrue);
    });

    test('a restart redraws, so it cannot be answered with the same moves', () {
      final session = LivenessSession(random: Random(7));
      final first = session.challenges.join(',');

      var redrawn = first;
      for (var i = 0; i < 20 && redrawn == first; i++) {
        session.onFrame(face());
        session.onFrame(face(faceCount: 2));
        redrawn = session.challenges.join(',');
      }

      expect(redrawn, isNot(first));
    });
  });
}
