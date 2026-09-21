# liveness_kit

A face liveness check you can put in front of a KYC upload: the camera opens,
the app asks for a couple of head turns in a random order, and it hands back a
still taken once the face is forward and steady again.

Face detection is native on both platforms — Apple Vision on iOS, MediaPipe
Face Landmarker on Android — so nothing here pulls in Firebase, ML Kit or a
CocoaPod.

## What it is not

Nothing on a phone can prove a live human. The app runs on the subject's
device, and anything it measures can be lied to by someone determined enough.
What this does is raise the cost of a casual attempt — a photo held up to the
lens, a screen recording of someone else's session — and hand you a usable
portrait to check properly on your server. **The server-side check is what
decides.** Treat a pass here as "worth looking at", never as "verified".

## Using it

```dart
final result = await Navigator.of(context).push<LivenessResult>(
  MaterialPageRoute(builder: (_) => const LivenessCapture()),
);

switch (result) {
  case LivenessPassed(:final photoPath):
    await upload(File(photoPath));
  case LivenessUnavailable(:final reason):
    // No detector on this device. Offer your manual route — the customer
    // cannot fix this by trying again.
  case LivenessCancelled() || LivenessSkipped() || null:
    break;
}
```

The result is a sealed type on purpose. "No photo" has three quite different
meanings, and a caller that cannot tell them apart ends up treating a device
with no face detector as somebody who changed their mind.

### Making it yours

```dart
LivenessCapture(
  theme: LivenessTheme(accent: Theme.of(context).colorScheme.primary),
  strings: const LivenessStrings(appBarTitle: 'Vérification'),
  session: () => LivenessSession(
    framesToHold: 4,
    challengeTimeout: const Duration(seconds: 30),
  ),
  onEscape: () => context.go('/manual-review'),
  onDiagnostic: (error, stack) => Sentry.captureException(error),
)
```

The screen is dark whatever your app's theme is: the preview is a face lit by
the room, and a white page around it washes the picture out and lights the
subject from the wrong side. Only the accent follows your app.

`onEscape` is worth wiring up. Some people cannot complete the gestures — a
tremor, a stiff neck, a bad camera — and a check with no way out traps them.
The link is held back until the second failed attempt, so it does not become
the easy path for everyone else.

### Without the screen

The rules are plain Dart, and they have no idea a camera exists:

```dart
final session = LivenessSession();

session.onFrame(signals);   // FaceSignals, from anywhere
session.stage;              // findingFace | challenging | holding | passed
session.currentChallenge;   // what to prompt for
session.completedCount;     // for your own progress indicator
```

Feed it from `NativeFaceDetector`, or from your own `FaceDetectorPort` if you
have a detector you would rather use.

## How the check works

Four things make it harder to fake than a single photo:

- **The challenges are drawn in a random order**, so a recording of a previous
  session answers the wrong prompts.
- **Each one is a movement, not a pose** — reach the far end, then come back.
  A photograph tilted in front of the lens can satisfy a threshold; it cannot
  return to centre on cue.
- **The far end has to be held** for several consecutive frames, so a flicker
  in the readings does not count.
- **The photo is taken after a still, forward-facing hold**, so what reaches
  your server is a usable portrait rather than a face mid-gesture.

A face that leaves the frame briefly is forgiven; one that leaves for longer
restarts the sequence, as does a second face appearing, or a challenge that
takes too long. Each restart redraws the challenges.

## Setup

```yaml
dependencies:
  liveness_kit: ^0.1.0
```

Or straight from the repository, before it is on pub.dev:

```yaml
dependencies:
  liveness_kit:
    git:
      url: https://github.com/Universal-Weblinks/liveness-kit.git
      ref: v0.1.0
```

**iOS** — camera permission in `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to check that you are really there.</string>
```

Vision ships with iOS. Minimum deployment target 13.0.

**Android** — nothing to add. The camera permission comes from the `camera`
plugin, and the 3.6 MB face model ships inside this package, so there is
nothing to download or register. `minSdk` 24.

## Size

The Android model adds about 3.6 MB to your app. iOS adds nothing: Vision is
part of the system.

## Testing against it

`FaceDetectorPort` is the seam. Pass a fake to `LivenessCapture(detector: …)`,
or drive `LivenessSession` directly with `FaceSignals` — that is how this
package's own tests cover the whole sequence without a device.

## Licence

MIT. The bundled Android model is Google's MediaPipe Face Landmarker,
distributed under Apache 2.0.
