## 0.1.0

First release.

* `LivenessCapture`, a camera screen that runs randomised head-turn
  challenges and gives you back the photo it ends on.
* `LivenessSession`, the same rules with no camera, platform or widget code
  in them. Feed it `FaceSignals` and it tells you what to ask for next.
* Native face detection. Apple Vision on iOS, MediaPipe Face Landmarker on
  Android. No Firebase, no ML Kit, no CocoaPod.
* Themeable through `LivenessTheme`, translatable through `LivenessStrings`.
* Holds the screen awake for the length of the check, and hands it back
  afterwards.
