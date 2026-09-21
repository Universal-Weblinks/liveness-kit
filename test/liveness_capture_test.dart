import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_kit/liveness_kit.dart';

/// Holding the screen on for the length of the face check.
///
/// The check is watched, not touched: a customer turning their head produces
/// no input at all, so the idle timer runs down and the display dims part-way
/// through. Every app that runs one of these keeps the screen lit until it is
/// done.
///
/// The pairing is what matters. A wake lock taken and not given back outlives
/// the screen that needed it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.universalweblinks.liveness_kit/screen_awake'),
          (call) async {
            calls.add(call);
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.universalweblinks.liveness_kit/screen_awake'),
          null,
        );
  });

  test('keepOn asks the platform to hold the screen', () async {
    await ScreenAwake.keepOn();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setKeepAwake');
    expect(calls.single.arguments, isTrue);
  });

  test('release hands it back', () async {
    await ScreenAwake.release();

    expect(calls.single.arguments, isFalse);
  });

  // The screen dimming is a nuisance; the check failing is not. A platform
  // that has no implementation, or one that throws, must not take the flow down.
  test('a platform that cannot do it is not an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.universalweblinks.liveness_kit/screen_awake'),
          (call) async => throw PlatformException(code: 'UNAVAILABLE'),
        );

    await expectLater(ScreenAwake.keepOn(), completes);
  });

  test('and neither is a build with no plugin at all', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.universalweblinks.liveness_kit/screen_awake'),
          null,
        );

    await expectLater(ScreenAwake.release(), completes);
  });
}
