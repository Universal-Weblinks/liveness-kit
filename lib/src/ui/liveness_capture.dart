import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../detector/face_detector_port.dart';
import '../detector/native_face_detector.dart';
import '../engine/camera_frame_geometry.dart';
import '../engine/face_signals.dart';
import '../engine/liveness_session.dart';
import '../platform/screen_awake.dart';
import 'liveness_strings.dart';
import 'liveness_theme.dart';

/// What a completed check produced.
///
/// A sealed result rather than a nullable path: "no photo" has three quite
/// different meanings — the customer backed out, the device cannot do this at
/// all, or they asked for another way through — and a caller that cannot tell
/// them apart ends up treating a device with no face detector as somebody who
/// changed their mind.
sealed class LivenessResult {
  const LivenessResult();
}

/// The gestures were completed and a still was taken.
class LivenessPassed extends LivenessResult {
  const LivenessPassed(this.photoPath);

  /// A JPEG on disk, in the app's temporary directory. Nothing is uploaded —
  /// what happens to it is the host app's business.
  final String photoPath;
}

/// The customer left without finishing.
class LivenessCancelled extends LivenessResult {
  const LivenessCancelled();
}

/// No face detection on this device, so there was nothing to gate on.
///
/// Worth handling rather than treating as a cancellation: the customer did
/// nothing wrong and cannot fix it by trying again.
class LivenessUnavailable extends LivenessResult {
  const LivenessUnavailable(this.reason);

  /// What the platform said, when it could say anything. Diagnostic — not
  /// written for a customer to read.
  final String? reason;
}

/// The customer took the way out offered after repeated failures.
class LivenessSkipped extends LivenessResult {
  const LivenessSkipped();
}

/// Runs the gesture check and returns the photo it ends on.
///
/// Push it and await the result:
///
/// ```dart
/// final result = await Navigator.of(context).push<LivenessResult>(
///   MaterialPageRoute(builder: (_) => const LivenessCapture()),
/// );
/// if (result is LivenessPassed) upload(File(result.photoPath));
/// ```
///
/// The gestures are a gate on this screen only. Nothing here proves a live
/// human — the app runs on the customer's device and anything it measures can
/// be lied to. It raises the cost of a casual attempt; whatever checks the
/// photo on your server is what actually decides.
class LivenessCapture extends StatefulWidget {
  const LivenessCapture({
    this.theme,
    this.strings = const LivenessStrings(),
    this.session,
    this.detector,
    this.onEscape,
    this.onDiagnostic,
    this.showDiagnostics = false,
    super.key,
  });

  /// Colours. Defaults to a dark screen with the host app's primary as the
  /// accent.
  final LivenessTheme? theme;

  /// Every word on screen.
  final LivenessStrings strings;

  /// Builds the session, for a different challenge count, timeout or hold.
  /// A default is built when this is null — and again on every retry, so the
  /// gestures are redrawn rather than repeated.
  final LivenessSession Function()? session;

  /// Stands in for the native detectors. Provided in tests; leave null in an
  /// app.
  final FaceDetectorPort? detector;

  /// Offered after two failed attempts, if given. Without it nobody is shown
  /// a way out, which suits a flow that has one elsewhere and traps people in
  /// one that does not.
  ///
  /// Called just before the screen closes with [LivenessSkipped].
  final VoidCallback? onEscape;

  /// Told about failures worth recording: a detector that will not start, a
  /// camera that will not open. A face check that quietly does nothing is
  /// otherwise invisible from both sides.
  final void Function(Object error, StackTrace stackTrace)? onDiagnostic;

  /// Draws the live detector readings over the preview.
  ///
  /// For tuning against real faces on a real device. Ignored in release
  /// builds — the numbers are meaningless to a customer and the overlay
  /// rebuilds on every frame.
  final bool showDiagnostics;

  @override
  State<LivenessCapture> createState() => _LivenessCaptureState();
}

class _LivenessCaptureState extends State<LivenessCapture> {
  late final FaceDetectorPort _detector =
      widget.detector ?? NativeFaceDetector();

  CameraController? _controller;
  late LivenessSession _session = _newSession();

  bool _initialising = true;
  bool _detectorMissing = false;

  /// Why, when the platform can say.
  String? _detectorReason;
  bool _capturing = false;

  /// True while a frame is with the detector. Frames that arrive meanwhile are
  /// dropped rather than queued: the challenge logic needs a few readings a
  /// second, and a backlog would have it reacting to poses from seconds ago.
  bool _busy = false;

  /// When the last frame went to the detector.
  ///
  /// The busy flag alone only stops overlap — it still runs detection as fast
  /// as detection can finish, which on Android means compressing a frame to
  /// JPEG and decoding it again, continuously, on the thread drawing the
  /// preview. The session needs about ten readings a second; anything above
  /// that is heat and dropped frames.
  DateTime? _lastDetectionAt;

  static const Duration _detectionInterval = Duration(milliseconds: 90);

  String? _cameraError;

  /// The most recent reading, for the diagnostic overlay.
  FaceSignals? _lastSignals;

  /// Whether the detector can currently see one usable face.
  ///
  /// Drives the guide ring, which is the only thing on the screen that tells
  /// somebody their face is in the right place before the prompts start.
  bool _faceInFrame = false;

  bool get _diagnostics => widget.showDiagnostics && kDebugMode;

  LivenessSession _newSession() => widget.session?.call() ?? LivenessSession();

  @override
  void initState() {
    super.initState();
    // Before anything can fail. A check that never opens the camera should
    // still hand the screen back on the way out, and dispose does that.
    ScreenAwake.keepOn();
    _start();
  }

  @override
  void dispose() {
    ScreenAwake.release();
    _controller?.dispose();
    _detector.dispose();
    super.dispose();
  }

  void _finish(LivenessResult result) {
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _start() async {
    if (!await _detector.isAvailable()) {
      // Without a detector there is nothing to gate on. Say so rather than
      // leaving the customer performing gestures nothing is watching.
      final reason = await _detector.unavailableReason();

      // Reported, not just shown: a detector that will not start is otherwise
      // completely silent, and a device that cannot do this at all looks
      // identical to one that can.
      widget.onDiagnostic?.call(
        StateError(
          'Liveness: face detector unavailable. ${reason ?? 'no reason given'}',
        ),
        StackTrace.current,
      );

      if (mounted) {
        setState(() {
          _initialising = false;
          _detectorMissing = true;
          _detectorReason = reason;
        });
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        // Pinned rather than left to the plugin's per-platform default. The
        // native detectors each decode one layout — Vision reads BGRA, the
        // MediaPipe side builds its bitmap from NV21 — and Android's default
        // is neither.
        //
        // Planar YUV on Android, not `nv21`: asking for nv21 makes the camera
        // plugin pack it, and its packer throws `newPosition > limit` on a
        // device whose V plane ends exactly at its buffer limit — before any
        // frame reaches us. The planes are handed over untouched instead and
        // packed natively, where the strides are respected and nothing reads
        // past an end.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Pin the frames to portrait.
      //
      // On iOS the plugin orients its buffers from `UIDevice.orientation` —
      // the physical handset — not from the screen. Somebody leaning back
      // with the phone tipped into landscape would get sideways frames with
      // an upright face in them, and the detector would simply stop finding
      // anyone. Locking it makes the frames match what is on screen, and
      // makes the zero rotation this screen sends true rather than usually
      // true.
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException {
        // Not supported everywhere, and not worth failing the check over: the
        // rotation is right for an upright phone either way.
      }

      setState(() {
        _controller = controller;
        _initialising = false;
      });
      await controller.startImageStream(_onFrame);
    } catch (error, stackTrace) {
      widget.onDiagnostic?.call(error, stackTrace);
      if (mounted) {
        setState(() {
          _initialising = false;
          _cameraError = widget.strings.cameraOpenFailed;
        });
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _session.isFinished || _capturing) return;

    final now = DateTime.now();
    final last = _lastDetectionAt;
    if (last != null && now.difference(last) < _detectionInterval) return;

    _busy = true;
    _lastDetectionAt = now;

    try {
      final signals = await _detector.detect(
        FaceFrame(
          planes: [
            for (final plane in image.planes)
              FacePlane(
                bytes: plane.bytes,
                bytesPerRow: plane.bytesPerRow,
                // A luma plane is one byte per sample; a chroma plane the
                // hardware has interleaved is two. Absent means one.
                bytesPerPixel: plane.bytesPerPixel ?? 1,
              ),
          ],
          width: image.width,
          height: image.height,
          rotationDegrees: uprightRotationDegrees(
            pipeline: Platform.isIOS
                ? CameraPipeline.avFoundation
                : CameraPipeline.cameraX,
            sensorOrientation: _controller?.description.sensorOrientation ?? 0,
          ),
          format: image.format.group.name,
        ),
      );

      if (!mounted) return;
      final before = _session.stage;
      _session.onFrame(signals);
      if (_diagnostics) _lastSignals = signals;

      // The ring has to answer while the session is still looking for a face,
      // which is the stage that produces no other change to rebuild on.
      final seen = signals.isUsable;
      final faceChanged = seen != _faceInFrame;
      _faceInFrame = seen;

      if (_session.stage != before ||
          faceChanged ||
          _session.currentChallenge != null ||
          _diagnostics) {
        setState(() {});
      }

      if (_session.stage == LivenessStage.passed) await _capture();
    } finally {
      _busy = false;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);

    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      _finish(LivenessPassed(file.path));
    } catch (error, stackTrace) {
      widget.onDiagnostic?.call(error, stackTrace);
      if (mounted) {
        setState(() {
          _capturing = false;
          _cameraError = widget.strings.captureFailed;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _session = _newSession();
      _cameraError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? LivenessTheme.of(context);
    final strings = widget.strings;

    return PopScope(
      // Backing out is a cancellation, and the caller is told so rather than
      // left to read a null.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _finish(const LivenessCancelled());
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          foregroundColor: theme.foreground,
          elevation: 0,
          title: Text(strings.appBarTitle),
        ),
        body: SafeArea(child: _body(theme, strings)),
      ),
    );
  }

  Widget _body(LivenessTheme theme, LivenessStrings strings) {
    if (_initialising) return _loader(theme);

    if (_detectorMissing) {
      return _Message(
        theme: theme,
        title: strings.unavailableTitle,
        body: strings.unavailableBody,
        actionLabel: strings.goBack,
        onAction: () => _finish(LivenessUnavailable(_detectorReason)),
        detail: _diagnostics ? _detectorReason : null,
      );
    }

    final error = _cameraError;
    if (error != null) {
      return _Message(
        theme: theme,
        title: strings.cameraProblemTitle,
        body: error,
        actionLabel: strings.tryAgain,
        onAction: _retry,
      );
    }

    return _camera(theme, strings);
  }

  Widget _loader(LivenessTheme theme) => Center(
    child: CircularProgressIndicator(color: theme.accent, strokeWidth: 2),
  );

  Widget _camera(LivenessTheme theme, LivenessStrings strings) {
    final controller = _controller;
    if (controller == null) return _loader(theme);

    final preview = controller.value.previewSize;

    return Column(
      children: [
        const SizedBox(height: 24),
        _Prompt(session: _session, theme: theme, strings: strings),
        const SizedBox(height: 20),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Sized to the space it is given. A fixed ring drawn for one
                // handset is a postage stamp on a tablet and overflows a
                // small phone.
                final side = _ringSide(constraints);
                return _FaceGuide(
                  stage: _session.stage,
                  faceInFrame: _faceInFrame,
                  theme: theme,
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        // The preview reports its size in sensor orientation,
                        // which is landscape while the phone is upright.
                        width: preview?.height ?? 1,
                        height: preview?.width ?? 1,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_diagnostics && _lastSignals != null)
          _SignalReadout(signals: _lastSignals!),
        _Progress(session: _session, theme: theme),
        const SizedBox(height: 24),
        EscapeHatch(
          attempts: _session.attempts,
          label: strings.escapeHatch,
          theme: theme,
          onEscape: widget.onEscape == null
              ? null
              : () {
                  widget.onEscape!.call();
                  _finish(const LivenessSkipped());
                },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  double _ringSide(BoxConstraints constraints) {
    final widest = constraints.maxWidth - 48;
    final tallest = constraints.maxHeight - 24;
    final side = widest < tallest ? widest : tallest;
    return side.clamp(160.0, 320.0);
  }
}

/// The ring the customer is asked to put their face inside.
///
/// Every app that runs a face check draws one, and for the same reason: a
/// circular crop of a camera feed says nothing about where a face is supposed
/// to go, or whether the one on screen has been found.
///
/// The ring carries the state rather than merely framing the picture: dim
/// while nothing is detected, bright once a usable face is in it, the accent
/// once the gestures are being watched, and the success colour when the check
/// has passed. That makes "move closer" or "more light" something somebody
/// can work out for themselves, without being told.
class _FaceGuide extends StatelessWidget {
  const _FaceGuide({
    required this.stage,
    required this.faceInFrame,
    required this.theme,
    required this.child,
  });

  final LivenessStage stage;
  final bool faceInFrame;
  final LivenessTheme theme;
  final Widget child;

  Color get _ringColor => switch (stage) {
    LivenessStage.passed => theme.success,
    LivenessStage.challenging || LivenessStage.holding => theme.accent,
    // Still looking. Bright enough to read as "found you", dim enough that an
    // empty ring does not look like a failure.
    LivenessStage.findingFace =>
      faceInFrame
          ? theme.foreground.withValues(alpha: 0.85)
          : theme.foreground.withValues(alpha: 0.22),
  };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = _ringColor;
    final lit = stage != LivenessStage.findingFace || faceInFrame;

    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: lit ? 3 : 2),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipOval(child: child),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.session,
    required this.theme,
    required this.strings,
  });

  final LivenessSession session;
  final LivenessTheme theme;
  final LivenessStrings strings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final challenge = session.currentChallenge;

    final (title, subtitle) = switch (session.stage) {
      LivenessStage.findingFace => (
        strings.findingFaceTitle,
        session.restartReason == null
            ? strings.findingFaceSubtitle
            : strings.restartReason(session.restartReason!),
      ),
      LivenessStage.challenging => (
        challenge == null ? '' : strings.promptFor(challenge),
        strings.challengeSubtitle,
      ),
      LivenessStage.holding => (strings.holdingTitle, strings.holdingSubtitle),
      LivenessStage.passed => (strings.passedTitle, strings.passedSubtitle),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: theme.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: theme.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// One pip per challenge, filled as each is cleared.
///
/// The sequence is short and randomised, so without this somebody cannot tell
/// whether they are nearly finished or have just started.
class _Progress extends StatelessWidget {
  const _Progress({required this.session, required this.theme});

  final LivenessSession session;
  final LivenessTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(session.totalCount, (index) {
        final done = index < session.completedCount;
        return Container(
          width: 28,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: done
                ? theme.success
                : theme.foreground.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.theme,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.detail,
  });

  final LivenessTheme theme;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  /// The underlying failure, for diagnostics. Never shown to customers.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: theme.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: theme.mutedForeground),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.foreground.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                detail!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: theme.mutedForeground,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.foreground,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live detector output, for tuning on a device.
///
/// The thresholds are degrees and ratios, and they mean nothing until you
/// watch what a real face in a real room produces — the two platforms
/// normalise them differently.
class _SignalReadout extends StatelessWidget {
  const _SignalReadout({required this.signals});

  final FaceSignals signals;

  @override
  Widget build(BuildContext context) {
    String n(double value) => value.toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'faces ${signals.faceCount}   '
              'fill ${n(signals.faceFillRatio)}   '
              'usable ${signals.isUsable}',
            ),
            Text(
              'yaw ${n(signals.yaw)}°   '
              'pitch ${n(signals.pitch)}°   '
              'neutral ${signals.isNeutral}',
            ),
            Text(
              'mouth ${n(signals.mouthOpenness)}   '
              'eyes ${n(signals.eyeOpenness)}',
            ),
          ],
        ),
      ),
    );
  }
}

/// The way out, once somebody has plainly struggled.
///
/// Held back until the second failed attempt: offered from the start it reads
/// as the easier path, and most people who see it on their first try will
/// take it rather than turn their head. Withheld entirely when the host gave
/// nowhere for it to go — a button that closes the screen and drops the
/// customer back where they started is worse than no button.
@visibleForTesting
class EscapeHatch extends StatelessWidget {
  const EscapeHatch({
    required this.attempts,
    required this.label,
    required this.theme,
    required this.onEscape,
    super.key,
  });

  /// How many times the sequence has restarted.
  final int attempts;
  final String label;
  final LivenessTheme theme;
  final VoidCallback? onEscape;

  /// After two goes. One restart is a dropped frame or a misread prompt;
  /// two is a pattern.
  static const int offerAfterAttempts = 2;

  @override
  Widget build(BuildContext context) {
    if (onEscape == null || attempts < offerAfterAttempts) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextButton(
        onPressed: onEscape,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
