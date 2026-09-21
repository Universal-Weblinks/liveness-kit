# liveness_kit

A face liveness check for Flutter. It opens the front camera, asks the person
to turn their head a couple of times in a random order, and gives you back a
photo taken once they are facing forward again and holding still.

Face detection runs natively on both platforms: Apple Vision on iOS,
MediaPipe Face Landmarker on Android. Nothing here pulls in Firebase, ML Kit
or a CocoaPod.

## What this is not

You cannot prove someone is alive from a phone. The app runs on their device,
so anything it measures can be faked by someone who wants it badly enough.

What you get is a much higher bar than "upload a selfie". A photo held up to
the lens cannot turn its head on cue, and a recording of an earlier session
answers the wrong prompts. Treat a pass as "worth a look", never as
"verified". Your server still decides.

## Getting a photo

```dart
final result = await Navigator.of(context).push<LivenessResult>(
  MaterialPageRoute(builder: (_) => const LivenessCapture()),
);

switch (result) {
  case LivenessPassed(:final photoPath):
    await upload(File(photoPath));
  case LivenessUnavailable(:final reason):
    // This phone has no face detector. Offer your manual route, because
    // trying again will not help them.
  case LivenessCancelled() || LivenessSkipped() || null:
    break;
}
```

The result is a sealed type on purpose. "No photo" can mean three different
things, and if you cannot tell them apart you will end up treating a phone
with no face detector like someone who changed their mind.

## Making it yours

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

The screen stays dark whatever your app's theme is. A face on camera is lit by
the room it is in, and a white page around it washes the picture out and
throws light back at the subject from the wrong angle. Only the accent colour
follows your app.

Wire up `onEscape` if you can. Some people cannot do the gestures. A tremor, a
stiff neck, a camera that cannot see them in the light they have. Without a way
out they are stuck on that screen. The link stays hidden until the second
failed attempt, so it does not become the easy option for everyone else.

## Without the screen

The rules are plain Dart and have no idea a camera exists:

```dart
final session = LivenessSession();

session.onFrame(signals);   // FaceSignals, from wherever you like
session.stage;              // findingFace | challenging | holding | passed
session.currentChallenge;   // what to prompt for
session.completedCount;     // for your own progress indicator
```

Feed it from `NativeFaceDetector`, or from your own `FaceDetectorPort` if you
already have a detector you would rather use.

## How the check works

Four things make this harder to fake than a single photo.

The challenges come in a random order, so a recording of an earlier session
answers the wrong prompts.

Each one is a movement rather than a pose. You have to reach the far end and
come back. Someone can tilt a photo in front of the lens to clear a threshold,
but they cannot bring it back to centre on cue.

The far end has to be held for a few frames in a row, so a flicker in the
readings does not count.

The photo is taken after a still, forward-facing hold, so you get a usable
portrait instead of a face caught mid-turn.

A face that drops out of frame for a moment is forgiven. Longer than that and
the sequence restarts, as it does if a second face turns up or a challenge
takes too long. Every restart draws new challenges.

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

On iOS, add the camera permission to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to check that you are really there.</string>
```

Vision ships with iOS. Minimum deployment target is 13.0.

On Android there is nothing to add. The camera permission comes from the
`camera` plugin, and the face model ships inside this package, so there is
nothing to download and nothing to register. Minimum SDK is 24.

## Size

The Android model adds about 3.6 MB to your app. iOS adds nothing, since
Vision is part of the system.

## Testing against it

`FaceDetectorPort` is the seam. Hand a fake to `LivenessCapture(detector: …)`,
or drive `LivenessSession` yourself with `FaceSignals`. That is how this
package covers the whole sequence in its own tests without a device.

## Licence

MIT. The bundled Android model is Google's MediaPipe Face Landmarker, under
Apache 2.0.
