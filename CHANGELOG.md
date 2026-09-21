## 0.1.0

First release.

* `LivenessCapture`, a camera screen that runs randomised head-turn
  challenges and returns the still it ends on.
* `LivenessSession`, the same rules with no camera, platform or widget code
  in them — feed it `FaceSignals`, it says what to ask for next.
* Native face detection: Apple Vision on iOS, MediaPipe Face Landmarker on
  Android. No Firebase, no ML Kit, no CocoaPod.
* Themeable through `LivenessTheme` and translatable through
  `LivenessStrings`.
* Holds the screen awake for the length of the check, and hands it back.
