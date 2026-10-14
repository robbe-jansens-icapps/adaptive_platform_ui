import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The appearances the windows were held in, in order; null lets go.
  final held = <Object?>[];

  setUp(() {
    held.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('adaptive_platform_ui/device'),
          (call) async {
            if (call.method == 'lockAppearance') {
              held.add((call.arguments as Map<Object?, Object?>)['style']);
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('adaptive_platform_ui/device'),
          null,
        );
  });

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('a light app stays light on a device in dark mode: its pages '
      'and the native windows', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AdaptiveBrightnessLock(brightness: Brightness.light, child: child!),
        home: Builder(
          builder: (context) {
            page = context;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(MediaQuery.platformBrightnessOf(page), Brightness.light);
    expect(held, ['light']);
  }, variant: ios);

  testWidgets('the lock mounted last holds the windows, and with none left '
      'they follow the device again', (tester) async {
    final inner = ValueNotifier<Brightness?>(Brightness.dark);
    addTearDown(inner.dispose);
    final outer = ValueNotifier<bool>(true);
    addTearDown(outer.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: Listenable.merge([inner, outer]),
        builder: (context, _) {
          Widget tree = inner.value == null
              ? const SizedBox()
              : AdaptiveBrightnessLock(
                  brightness: inner.value!,
                  child: const SizedBox(),
                );
          if (outer.value) {
            tree = AdaptiveBrightnessLock(
              brightness: Brightness.light,
              child: tree,
            );
          }
          return MediaQuery(data: const MediaQueryData(), child: tree);
        },
      ),
    );
    expect(held.last, 'dark');

    inner.value = Brightness.light;
    await tester.pump();
    expect(held.last, 'light');

    inner.value = null;
    await tester.pump();
    expect(held.last, 'light');

    outer.value = false;
    await tester.pump();
    expect(held.last, isNull);
  }, variant: ios);

  testWidgets(
    'off iOS only the pages are held',
    (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(platformBrightness: Brightness.dark),
          child: AdaptiveBrightnessLock(
            brightness: Brightness.light,
            child: SizedBox(),
          ),
        ),
      );
      expect(held, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
