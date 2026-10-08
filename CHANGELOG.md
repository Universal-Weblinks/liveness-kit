## 0.1.1

* Ship the R8 rules MediaPipe needs, as `consumerProguardFiles`. Without them
  a host app's release build loaded the native library fine and then failed
  inside `FaceLandmarker.createFromOptions`, so the check reported itself
  unavailable on every release build while debug builds worked. Two separate
  causes, both now covered: R8 renamed the fields of a protobuf-lite message
  that names them in its own schema string, and renamed the Flogger classes
  that `Graph`'s static initializer identifies by walking the stack. Host apps
  need no longer copy anything.

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
