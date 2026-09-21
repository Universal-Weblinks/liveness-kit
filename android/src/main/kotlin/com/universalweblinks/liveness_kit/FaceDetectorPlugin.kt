package com.universalweblinks.liveness_kit

import android.content.Context
import android.util.Log
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.min

/**
 * Face detection for the liveness check, on MediaPipe Face Landmarker.
 *
 * A Gradle dependency rather than a CocoaPod, which is the point: the iOS
 * side uses Apple Vision and neither platform pulls in ML Kit or Firebase.
 *
 * Everything reduces to the same six numbers the iOS side produces, so the
 * Dart layer never learns which platform it is on.
 */
class FaceDetectorPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.universalweblinks.liveness_kit/face_detector"

        /** Bundled asset. Absent means detection is simply unavailable. */
        private const val TAG = "FaceDetectorPlugin"
        private const val MODEL_ASSET = "face_landmarker.task"

        /**
         * Blendshape names MediaPipe emits. Read by name rather than index —
         * the order is not part of its contract and has changed between
         * releases.
         */
        private const val JAW_OPEN = "jawOpen"
        private const val BLINK_LEFT = "eyeBlinkLeft"
        private const val BLINK_RIGHT = "eyeBlinkRight"
    }

    private var landmarker: FaceLandmarker? = null

    /// Why the landmarker could not be built, kept so the Dart side can show
    /// it. The exception is otherwise swallowed to keep KYC alive, which left
    /// "Face check unavailable" as the only evidence of anything at all.
    private var initError: String? = null
    private var initialised = false

    /**
     * Releases the landmarker.
     *
     * Called by the Dart side when the screen closes, and again by the plugin
     * when the engine detaches — an engine torn down mid-check would
     * otherwise leave the native model loaded with nothing to free it.
     */
    fun close() {
        landmarker?.close()
        landmarker = null
        initialised = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(ensureLandmarker() != null)

            "unavailableReason" -> {
                ensureLandmarker()
                result.success(initError)
            }

            "detect" -> {
                val detector = ensureLandmarker()
                if (detector == null) {
                    result.success(emptySignals())
                    return
                }
                val planes = call.argument<List<Map<String, Any>>>("planes")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotationDegrees") ?: 0
                if (planes.isNullOrEmpty() || width == null || height == null) {
                    result.success(emptySignals())
                    return
                }

                val nv21 = try {
                    packNv21(planes, width, height)
                } catch (error: Throwable) {
                    // A frame we cannot read is one missed reading, not a
                    // failure. Never let it take the session down.
                    Log.w(TAG, "Could not pack frame into NV21", error)
                    null
                }
                if (nv21 == null) {
                    result.success(emptySignals())
                    return
                }

                result.success(detect(detector, nv21, width, height, rotation))
            }

            "dispose" -> {
                close()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Loads the model once. A missing or unreadable model leaves detection
     * unavailable rather than throwing — the Dart side is built to fall back,
     * and a crash here would take the whole KYC flow down.
     */
    private fun ensureLandmarker(): FaceLandmarker? {
        if (initialised) return landmarker
        initialised = true

        landmarker = try {
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetBuffer(readModel()).build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(2) // Enough to notice a second face in frame.
                .setOutputFaceBlendshapes(true)
                .setOutputFacialTransformationMatrixes(true)
                .build()
            FaceLandmarker.createFromOptions(context, options)
        } catch (error: Throwable) {
            // Swallowed so a failure here cannot take KYC down with it, but
            // logged: without this the only symptom was "Face check
            // unavailable" on the device and no way at all to tell why.
            Log.e(TAG, "Face landmarker unavailable: could not load $MODEL_ASSET", error)
            initError = "${error.javaClass.simpleName}: ${error.message}"
            null
        }

        return landmarker
    }

    /**
     * Reads the bundled model into a direct buffer.
     *
     * Not `setModelAssetPath`, which is the obvious call: that one reaches for
     * `AssetManager.openFd`, and a file descriptor can only be opened on a zip
     * entry the packager stored rather than deflated. An app would have to add
     *
     *     androidResources { noCompress += "task" }
     *
     * to its own build file for that to hold — a step nobody adding a
     * dependency would think to take, whose only symptom when missed is the
     * face check quietly reporting itself unavailable on every Android device.
     *
     * Reading the bytes ourselves works either way. It costs one 3.6 MB read
     * at startup, once per session.
     */
    private fun readModel(): ByteBuffer {
        val bytes = context.assets.open(MODEL_ASSET).use { it.readBytes() }
        // MediaPipe requires a direct buffer; a heap one is rejected at
        // construction.
        return ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            rewind()
        }
    }

    private fun detect(
        detector: FaceLandmarker,
        bytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int
    ): Map<String, Any> {
        val bitmap = nv21ToBitmap(bytes, width, height, rotation)
            ?: return emptySignals()

        val result = try {
            detector.detect(BitmapImageBuilder(bitmap).build())
        } catch (error: Throwable) {
            return emptySignals()
        }

        val faceCount = result.faceLandmarks().size
        if (faceCount == 0) return emptySignals()

        val (yaw, pitch) = headPose(result)

        return mapOf(
            "faceCount" to faceCount,
            "yaw" to yaw,
            "pitch" to pitch,
            "mouthOpenness" to blendshape(result, JAW_OPEN),
            // MediaPipe reports how closed an eye is; the Dart side wants how
            // open it is.
            "eyeOpenness" to (1.0 - maxOf(
                blendshape(result, BLINK_LEFT),
                blendshape(result, BLINK_RIGHT)
            )),
            "faceFillRatio" to faceFillRatio(result)
        )
    }

    /**
     * Yaw and pitch in degrees, pulled out of the facial transformation
     * matrix, in the Dart convention: negative yaw is the subject's own left,
     * positive their right.
     *
     * MediaPipe's matrix is expressed in the coordinate space of the image it
     * was given, and the image here is the raw front-sensor buffer, which the
     * camera does not mirror. So its yaw runs the opposite way to the subject:
     * a head turned to its own left reads positive. Confirmed on a device, not
     * inferred — with the sign the other way the prompt asking for a turn to
     * the left was satisfied by turning right, exactly the report iOS gave
     * before its own sign was corrected.
     *
     * Pitch is derived the same way and its axis convention is unconfirmed. It
     * is reported for completeness and gates nothing: no challenge uses it,
     * and `FaceSignals.isNeutral` deliberately ignores it.
     */
    private fun headPose(result: FaceLandmarkerResult): Pair<Double, Double> {
        val matrices = result.facialTransformationMatrixes()
        if (!matrices.isPresent || matrices.get().isEmpty()) return 0.0 to 0.0

        // The API hands back the flattened matrix itself — a FloatArray of
        // 16 — not a wrapper with a data field.
        val m: FloatArray = matrices.get()[0]
        if (m.size < 16) return 0.0 to 0.0

        // Column-major 4x4, so element (row, col) sits at m[col * 4 + row].
        // These three are R[2][0], R[2][1] and R[2][2] — the bottom row of the
        // rotation block, which is all the yaw and pitch need.
        val r20 = m[2].toDouble()
        val r21 = m[6].toDouble()
        val r22 = m[10].toDouble()

        val yaw = Math.toDegrees(asin(r20.coerceIn(-1.0, 1.0)))
        val pitch = Math.toDegrees(atan2(r21, r22))

        return yaw to pitch
    }

    private fun blendshape(result: FaceLandmarkerResult, name: String): Double {
        val shapes = result.faceBlendshapes()
        if (!shapes.isPresent || shapes.get().isEmpty()) return 0.0
        return shapes.get()[0]
            .firstOrNull { it.categoryName() == name }
            ?.score()
            ?.toDouble()
            ?: 0.0
    }

    /** How much of the frame's shorter side the face spans. */
    private fun faceFillRatio(result: FaceLandmarkerResult): Double {
        val landmarks = result.faceLandmarks().firstOrNull() ?: return 0.0
        if (landmarks.isEmpty()) return 0.0

        var minY = Float.MAX_VALUE
        var maxY = Float.MIN_VALUE
        for (point in landmarks) {
            if (point.y() < minY) minY = point.y()
            if (point.y() > maxY) maxY = point.y()
        }
        // Landmarks are normalised to the image, so the span is already a
        // share of its height.
        return min(1.0, abs(maxY - minY).toDouble())
    }

    /**
     * Packs the camera's planar YUV into NV21, respecting the strides.
     *
     * Done here rather than asked of the camera plugin. Requesting
     * `ImageFormatGroup.nv21` routes every frame through the plugin's
     * `ImageProxyUtils.areUVPlanesNV21`, which advances the V buffer by one
     * byte to compare it against U — and on a device whose V plane ends
     * exactly at its limit that throws `newPosition > limit` before a frame is
     * ever delivered. The camera ran, the stream started, and not one frame
     * arrived.
     *
     * Reading the planes with their own row and pixel strides is also simply
     * correct: hardware pads rows to an alignment boundary and often
     * interleaves the chroma samples already, so nothing here assumes the
     * bytes are packed and nothing reads past the end of a buffer.
     */
    private fun packNv21(
        planes: List<Map<String, Any>>,
        width: Int,
        height: Int
    ): ByteArray? {
        if (planes.size < 3) {
            // Already interleaved by whoever sent it. Nothing to pack.
            return planes[0]["bytes"] as? ByteArray
        }

        fun bytesOf(index: Int) = planes[index]["bytes"] as? ByteArray
        fun rowStride(index: Int) = (planes[index]["bytesPerRow"] as? Int) ?: width
        fun pixelStride(index: Int) = (planes[index]["bytesPerPixel"] as? Int) ?: 1

        val y = bytesOf(0) ?: return null
        val u = bytesOf(1) ?: return null
        val v = bytesOf(2) ?: return null

        val out = ByteArray(width * height * 3 / 2)
        var at = 0

        val yRow = rowStride(0)
        val yPixel = pixelStride(0)
        for (row in 0 until height) {
            var offset = row * yRow
            for (col in 0 until width) {
                if (offset >= y.size) return null
                out[at++] = y[offset]
                offset += yPixel
            }
        }

        // NV21 is V then U, interleaved, at half resolution on both axes.
        val uRow = rowStride(1)
        val vRow = rowStride(2)
        val uPixel = pixelStride(1)
        val vPixel = pixelStride(2)
        for (row in 0 until height / 2) {
            var uAt = row * uRow
            var vAt = row * vRow
            for (col in 0 until width / 2) {
                if (vAt >= v.size || uAt >= u.size) return null
                out[at++] = v[vAt]
                out[at++] = u[uAt]
                vAt += vPixel
                uAt += uPixel
            }
        }

        return out
    }

    /**
     * The frame arrives as NV21 by the time it gets here. MediaPipe wants a Bitmap, so
     * the frame is compressed to JPEG and decoded — slower than a direct
     * conversion, but the Dart side throttles to a few frames a second and
     * this avoids hand-rolling a YUV converter.
     */
    private fun nv21ToBitmap(
        bytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int
    ): Bitmap? = try {
        val yuv = YuvImage(bytes, ImageFormat.NV21, width, height, null)
        val stream = ByteArrayOutputStream()
        yuv.compressToJpeg(Rect(0, 0, width, height), 85, stream)
        val raw = stream.toByteArray()
        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size)

        if (decoded == null || rotation == 0) {
            decoded
        } else {
            // A sideways frame reads as no face at all, so the sensor
            // orientation has to be undone before detection.
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(
                decoded, 0, 0, decoded.width, decoded.height, matrix, true
            )
        }
    } catch (error: Throwable) {
        null
    }

    private fun emptySignals(): Map<String, Any> = mapOf(
        "faceCount" to 0,
        "yaw" to 0.0,
        "pitch" to 0.0,
        "mouthOpenness" to 0.0,
        "eyeOpenness" to 0.0,
        "faceFillRatio" to 0.0
    )
}
