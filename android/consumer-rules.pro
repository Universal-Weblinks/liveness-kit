# Shipped to every app that depends on liveness_kit, via
# `consumerProguardFiles` in this package's build.gradle. Host apps need not
# copy anything.
#
# Without these, a host app's release build starts the face check, loads
# libmediapipe_tasks_jni.so successfully, and then fails inside
# FaceLandmarker.createFromOptions with
#
#   java.lang.RuntimeException: Field platform_ for c1.B not found.
#   Known fields are [public static final c1.B c1.B.f, ...]
#
# `c1.B` is com.google.mediapipe.proto.MediaPipeLoggingProto$SystemInfo after
# obfuscation. It is a protobuf-lite message: its schema names its own fields
# in an embedded string and looks them up by reflection at startup, so R8
# renaming the fields breaks the lookup even though nothing failed to link.
#
# The only symptom reaching the user is LivenessUnavailable — on every release
# build, while debug builds work fine, because R8 only runs for release. That
# is a miserable thing to debug in a host app, which is why it is fixed here.

# The native side resolves these by name through JNI, so R8 cannot see the
# uses; protobuf-lite reflects on their fields, so the members matter too.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**

# The same reflection, stated the way protobuf documents it. Redundant with
# the rule above for today's MediaPipe, whose generated messages all sit under
# com.google.mediapipe — and deliberately so: a future version emitting a
# message elsewhere would otherwise reintroduce the failure above, and it
# would only show up in a release build on a real handset.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
}

# com.google.mediapipe.framework.Graph's static initializer builds a Flogger
# logger with FluentLogger.forEnclosingClass(), which works out which class is
# calling it by walking the stack and matching frames against Flogger's own
# class names. Renaming those classes breaks the walk:
#
#   java.lang.ExceptionInInitializerError
#     at com.google.mediapipe.tasks.core.TaskRunner.create
#   Caused by: java.lang.IllegalStateException: no caller found on the stack for: M0.d
#     at com.google.mediapipe.framework.Graph.<clinit>
#
# A second, independent R8 failure that only appears once the protobuf one
# above is fixed, with the same single symptom: the face check is unavailable.
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**

# The tasks libraries carry @AutoValue references and a shaded copy of its
# code generator, which points at javax.lang.model — a compile-time API that
# does not exist on Android. R8 treats the missing classes as errors. Nothing
# calls them at runtime, so silence the warnings rather than keeping them.
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**
-dontwarn com.google.auto.value.**
