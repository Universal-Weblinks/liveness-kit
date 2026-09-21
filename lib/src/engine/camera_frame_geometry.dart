/// Which platform's camera plugin produced a frame.
///
/// The two hand back pixels in different orientations, and nothing on the
/// frame itself says which — so the caller has to.
enum CameraPipeline {
  /// `camera_avfoundation`, on iOS.
  avFoundation,

  /// `camera_android_camerax`, on Android.
  cameraX,
}

/// How far a streamed camera frame must be rotated clockwise to stand upright.
///
/// This is the whole reason the check never got past "position your face" on
/// iOS, and it is worth writing down because both plugins are misleading about
/// it in opposite directions.
///
/// **iOS.** `camera_avfoundation` sets `videoOrientation` on the video data
/// output's connection, so the sample buffers it delivers are *already*
/// upright — width and height come back swapped for portrait. It also reports
/// `sensorOrientation` as a hardcoded 90 for every camera on the device
/// (`camera_avfoundation/lib/src/utils.dart`), which is not a reading of any
/// sensor at all. Rotating by it turned an upright face on its side, and
/// Vision does not find a face on its side. So: nothing to correct.
///
/// The caller must pin the capture orientation to portrait for that to hold.
/// The plugin follows `UIDevice.current.orientation`, which is the *physical*
/// device, not our portrait-locked interface — so a customer holding the phone
/// sideways would otherwise get a sideways buffer while their face stayed
/// upright on screen.
///
/// **Android.** CameraX's `ImageAnalysis` does not rotate its output; the
/// target rotation only changes metadata. The buffer arrives the way the
/// sensor is mounted, so it has to be turned by the sensor's own orientation.
/// `sensorOrientation` here is the real value from `CameraCharacteristics`.
/// Because the app is locked to portrait, the device rotation term in the
/// usual formula is zero and this is the whole correction.
int uprightRotationDegrees({
  required CameraPipeline pipeline,
  required int sensorOrientation,
}) {
  return switch (pipeline) {
    CameraPipeline.avFoundation => 0,
    // Normalised so an over-wound value cannot reach a native side that only
    // switches on 0/90/180/270 and treats anything else as no rotation at
    // all. Dart's `%` is already non-negative for a positive divisor, so this
    // covers -90 as well without the wrap the same code needs in Kotlin.
    CameraPipeline.cameraX => sensorOrientation % 360,
  };
}
