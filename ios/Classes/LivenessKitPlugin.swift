import Flutter
import UIKit

/// Registers the two channels the liveness screen needs.
///
/// Face detection is Apple Vision, which ships with iOS — no CocoaPod, no
/// Firebase, nothing to resolve at build time. Keeping the screen awake is
/// one property on `UIApplication`.
public class LivenessKitPlugin: NSObject, FlutterPlugin {
  private static let screenAwakeChannel = "com.universalweblinks.liveness_kit/screen_awake"

  public static func register(with registrar: FlutterPluginRegistrar) {
    FaceDetectorPlugin.register(with: registrar)

    let channel = FlutterMethodChannel(
      name: screenAwakeChannel,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setKeepAwake" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // A liveness check is watched, not touched, so the idle timer runs down
      // mid-gesture and the display dims on somebody doing exactly what the
      // screen asked. Released again the moment that screen closes.
      UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
      result(nil)
    }
  }
}
