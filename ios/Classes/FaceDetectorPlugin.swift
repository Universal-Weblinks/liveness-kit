import Flutter
import UIKit
import Vision
import CoreImage

/// Face detection for the liveness check, on Apple's Vision framework.
///
/// Vision ships with iOS, so this adds no CocoaPod, no Firebase dependency
/// and nothing to resolve at build time — which is why it is here rather than
/// a cross-platform SDK.
///
/// Everything reduces to the same six numbers the Android side produces, so
/// the Dart layer never learns which platform it is on.
class FaceDetectorPlugin: NSObject {
  static let channelName = "com.universalweblinks.liveness_kit/face_detector"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = FaceDetectorPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  private let ciContext = CIContext(options: nil)

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // Vision's landmark request is available from iOS 11. The deployment
      // target is above that, so this is always true — the method exists so
      // the Dart side can treat both platforms identically.
      result(true)

    case "unavailableReason":
      // Answered rather than left to fall through. An unhandled method comes
      // back to Dart as a MissingPluginException, which that side reports as
      // "No face detector is built into this app" — the one thing that is
      // certainly not true here.
      result(nil)

    case "detect":
      // One plane on this side: the camera streams BGRA. The payload carries a
      // list because Android streams three and packs them natively.
      guard let args = call.arguments as? [String: Any],
            let planes = args["planes"] as? [[String: Any]],
            let plane = planes.first,
            let data = (plane["bytes"] as? FlutterStandardTypedData)?.data,
            let width = args["width"] as? Int,
            let height = args["height"] as? Int
      else {
        result(Self.emptySignals)
        return
      }
      let rotation = args["rotationDegrees"] as? Int ?? 0
      let bytesPerRow = plane["bytesPerRow"] as? Int ?? width * 4
      detect(
        data: data, width: width, height: height,
        bytesPerRow: bytesPerRow, rotation: rotation, result: result
      )

    case "dispose":
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func detect(
    data: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    rotation: Int,
    result: @escaping FlutterResult
  ) {
    guard let image = bgraImage(
      from: data, width: width, height: height, sourceBytesPerRow: bytesPerRow
    ) else {
      result(Self.emptySignals)
      return
    }

    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(
      ciImage: image,
      orientation: Self.orientation(for: rotation),
      options: [:]
    )

    do {
      try handler.perform([request])
    } catch {
      result(Self.emptySignals)
      return
    }

    guard let faces = request.results, let face = faces.first else {
      result(Self.emptySignals)
      return
    }

    // Vision reports yaw and roll but not pitch before iOS 15. Where pitch is
    // missing the nod challenge cannot be judged, so it reports zero and the
    // session simply never satisfies it — better than inventing a value that
    // would clear the check on a still photograph.
    var pitchDegrees = 0.0
    if #available(iOS 15.0, *), let pitch = face.pitch?.doubleValue {
      pitchDegrees = pitch * 180 / .pi
    }
    let yawDegrees = (face.yaw?.doubleValue ?? 0) * 180 / .pi

    result([
      "faceCount": faces.count,
      // Vision's yaw already runs the way the Dart side expects: negative as
      // the subject turns to their own left, positive to their right.
      //
      // This used to be negated. That came from reading Apple's wording rather
      // than from a face, and it was wrong: on a device the prompt asking for
      // a turn to the right was satisfied by turning left, and vice versa.
      // Confirmed on an iPhone, not inferred — the docs describe the angle
      // from the image's point of view, which is the opposite of the subject's
      // only when you assume the frame is mirrored, and this one is not.
      "yaw": yawDegrees,
      "pitch": pitchDegrees,
      "mouthOpenness": Self.mouthOpenness(face),
      "eyeOpenness": Self.eyeOpenness(face),
      "faceFillRatio": Double(face.boundingBox.height),
    ])
  }

  /// Rebuilds the frame as a pixel buffer, row by row.
  ///
  /// The rows matter. Camera hardware pads each row out to an alignment
  /// boundary, so the incoming buffer's stride is usually wider than
  /// `width * 4`, and the buffer this allocates picks its own stride
  /// independently. Copying the whole thing in one `memcpy` — which is what
  /// this used to do — shifts every row a little further than the last and
  /// hands Vision a sheared image. Vision then finds no face, the session
  /// never leaves "position your face", and nothing anywhere reports an error.
  private func bgraImage(
    from data: Data,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int
  ) -> CIImage? {
    let rowBytes = max(sourceBytesPerRow, width * 4)
    guard data.count >= rowBytes * height else { return nil }

    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    guard CVPixelBufferCreate(
      kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer
    ) == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let copyBytes = min(rowBytes, destinationBytesPerRow)

    data.withUnsafeBytes { raw in
      guard let source = raw.baseAddress else { return }
      for row in 0..<height {
        memcpy(
          base.advanced(by: row * destinationBytesPerRow),
          source.advanced(by: row * rowBytes),
          copyBytes
        )
      }
    }

    return CIImage(cvPixelBuffer: buffer)
  }

  /// How far the lips are apart, as a share of the face's height.
  ///
  /// Normalised by face height so it does not change as the customer moves
  /// closer to or further from the lens.
  private static func mouthOpenness(_ face: VNFaceObservation) -> Double {
    guard let landmarks = face.landmarks,
          let inner = landmarks.innerLips?.normalizedPoints,
          inner.count >= 2 else { return 0 }

    let ys = inner.map { Double($0.y) }
    guard let top = ys.max(), let bottom = ys.min() else { return 0 }

    // innerLips points are normalised to the face box, so the gap is already
    // a share of face height. Scaled so a wide-open mouth reads near 1.
    return min(1, (top - bottom) * 3.0)
  }

  /// Rough eye aperture, used only to reject a face with both eyes shut.
  private static func eyeOpenness(_ face: VNFaceObservation) -> Double {
    guard let landmarks = face.landmarks else { return 1 }

    func aperture(_ eye: VNFaceLandmarkRegion2D?) -> Double {
      guard let points = eye?.normalizedPoints, points.count >= 2 else {
        return 1
      }
      let ys = points.map { Double($0.y) }
      guard let top = ys.max(), let bottom = ys.min() else { return 1 }
      return min(1, (top - bottom) * 8.0)
    }

    return (aperture(landmarks.leftEye) + aperture(landmarks.rightEye)) / 2
  }

  /// Kept for completeness, though the Dart side now always sends zero on
  /// iOS: `camera_avfoundation` orients its sample buffers itself, and the
  /// capture orientation is pinned to portrait while the check is running.
  /// This used to receive the plugin's hardcoded `sensorOrientation` of 90 and
  /// turn every upright face on its side, which Vision does not detect.
  private static func orientation(for rotation: Int) -> CGImagePropertyOrientation {
    switch rotation {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  private static let emptySignals: [String: Any] = [
    "faceCount": 0,
    "yaw": 0.0,
    "pitch": 0.0,
    "mouthOpenness": 0.0,
    "eyeOpenness": 0.0,
    "faceFillRatio": 0.0,
  ]
}
