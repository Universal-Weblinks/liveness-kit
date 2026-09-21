import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_kit/liveness_kit.dart';

/// What the screen hands back, on the paths that do not need a camera.
///
/// "No photo" has three meanings — nobody finished, the device cannot do this
/// at all, or the way out was taken — and a caller that cannot tell them
/// apart treats a device with no face detector as somebody who changed their
/// mind. On a phone that is a support ticket about a broken app; in the
/// figures it is a drop-off that looks like reluctance.
void main() {
  /// Pushes the screen and holds onto whatever it pops, which arrives after
  /// the caller has already returned.
  Future<_Holder> run(
    WidgetTester tester, {
    required FaceDetectorPort detector,
    VoidCallback? onEscape,
  }) async {
    final holder = _Holder();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              holder.result = await Navigator.of(context).push<LivenessResult>(
                MaterialPageRoute(
                  builder: (_) =>
                      LivenessCapture(detector: detector, onEscape: onEscape),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return holder;
  }

  testWidgets('a device with no detector says so, and says why', (
    tester,
  ) async {
    final detector = _FakeDetector(
      available: false,
      reason: 'model failed to load',
    );

    final holder = await run(tester, detector: detector);

    expect(find.text(const LivenessStrings().unavailableTitle), findsOneWidget);

    await tester.tap(find.text(const LivenessStrings().goBack));
    await tester.pumpAndSettle();

    final result = holder.result;
    expect(
      result,
      isA<LivenessUnavailable>(),
      reason: 'not a cancellation: nobody chose this',
    );
    expect((result as LivenessUnavailable).reason, 'model failed to load');
  });

  testWidgets('backing out is a cancellation', (tester) async {
    final holder = await run(tester, detector: _FakeDetector(available: false));

    // The system back gesture, not the button on the screen.
    final route = ModalRoute.of(tester.element(find.byType(LivenessCapture)))!;
    route.navigator!.maybePop();
    await tester.pumpAndSettle();

    expect(holder.result, isA<LivenessCancelled>());
  });

  testWidgets('the reason reaches the host, not just the screen', (
    tester,
  ) async {
    final reported = <Object>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LivenessCapture(
          detector: _FakeDetector(available: false, reason: 'no model'),
          onDiagnostic: (error, _) => reported.add(error),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(reported, hasLength(1));
    expect(reported.single.toString(), contains('no model'));
  });

  testWidgets('the words on screen are the ones the host chose', (
    tester,
  ) async {
    const strings = LivenessStrings(
      unavailableTitle: 'Nous ne pouvons pas vérifier',
      goBack: 'Retour',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LivenessCapture(
          detector: _FakeDetector(available: false),
          strings: strings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nous ne pouvons pas vérifier'), findsOneWidget);
    expect(find.text('Retour'), findsOneWidget);
  });

  group('the way out', () {
    const label = 'Skip the face check';

    Future<void> pumpHatch(
      WidgetTester tester, {
      required int attempts,
      VoidCallback? onEscape,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EscapeHatch(
              attempts: attempts,
              label: label,
              theme: LivenessTheme(accent: const Color(0xFF8531D1)),
              onEscape: onEscape,
            ),
          ),
        ),
      );
    }

    // A button that closes the screen and drops somebody back where they
    // started is worse than no button.
    testWidgets('is not offered when the host gave nowhere to go', (
      tester,
    ) async {
      await pumpHatch(tester, attempts: 5);
      expect(find.text(label), findsNothing);
    });

    // Offered from the first prompt, it reads as the easier path.
    testWidgets('is held back until somebody has plainly struggled', (
      tester,
    ) async {
      await pumpHatch(tester, attempts: 1, onEscape: () {});
      expect(find.text(label), findsNothing);

      await pumpHatch(tester, attempts: 2, onEscape: () {});
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('and tells the host when it is taken', (tester) async {
      var taken = 0;
      await pumpHatch(tester, attempts: 2, onEscape: () => taken++);

      await tester.tap(find.text(label));
      await tester.pump();

      expect(taken, 1);
    });
  });

  testWidgets('the accent follows the app that opened it', (tester) async {
    const pink = Color(0xFFD81B60);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(primary: pink)),
        home: LivenessCapture(detector: _FakeDetector(available: false)),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final background = button.style?.backgroundColor?.resolve({});
    expect(background, pink);
  });
}

class _Holder {
  LivenessResult? result;
}

class _FakeDetector implements FaceDetectorPort {
  _FakeDetector({required this.available, this.reason});

  final bool available;
  final String? reason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> unavailableReason() async => reason;

  @override
  Future<FaceSignals> detect(FaceFrame frame) async => FaceSignals.empty;

  @override
  Future<void> dispose() async {}
}
