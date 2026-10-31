import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_view_settle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    IOS26SegmentedControl.debugHasUIKitOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async => null,
        );
  });

  tearDown(() {
    IOS26SegmentedControl.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  final control = find.byType(IOS26SegmentedControl);
  final standIn = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_SegmentedControlStandIn',
  );

  /// The native views composited in the last frame: the control's while its
  /// page holds still in front.
  int nativeViews(WidgetTester tester) =>
      tester.layers.whereType<PlatformViewLayer>().length;

  Future<void> pumpPage(WidgetTester tester, GlobalKey<NavigatorState> root) =>
      tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: IOS26SegmentedControl(
                  labels: const ['Bike 2027', 'E-bike 2028'],
                  selectedIndex: 1,
                  onValueChanged: (_) {},
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a native segmented control leaves the screen while a dialog '
      'covers its page, a stand-in with its segments taking its place, and '
      'comes back once it has gone', (tester) async {
    final root = GlobalKey<NavigatorState>();
    await pumpPage(tester, root);
    await tester.pumpAndSettle();
    final size = tester.getSize(control);
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);

    // Left on screen, iOS showed the dialog's barrier, and a page pushed over
    // it, only within the clip around the native view: a sheet's shape.
    showDialog<void>(
      context: root.currentContext!,
      builder: (_) => const Center(child: Text('dialog')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);
    expect(find.text('E-bike 2028'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 0);
    expect(tester.getSize(control), size);

    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
    expect(tester.getSize(control), size);
  });

  testWidgets('a page sliding over the control finds it gone for the '
      'stand-in', (tester) async {
    final root = GlobalKey<NavigatorState>();
    await pumpPage(tester, root);
    await tester.pumpAndSettle();

    root.currentState!.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const Scaffold(body: Text('over')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);

    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
  });

  /// The control on a sheet that is [moving], as one that springs to rest.
  Future<void> pumpOnSheet(
    WidgetTester tester,
    ValueNotifier<bool> moving, {
    ValueChanged<int>? onValueChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NativeViewSettleScope(
          moving: moving,
          child: Center(
            child: SizedBox(
              width: 300,
              child: IOS26SegmentedControl(
                labels: const ['Bike 2027', 'E-bike 2028'],
                selectedIndex: 1,
                onValueChanged: onValueChanged ?? (_) {},
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('while its sheet moves, the stand-in takes the taps on the '
      'segments, as the native control is away', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final moving = ValueNotifier<bool>(true);
    addTearDown(moving.dispose);
    final selected = <int>[];
    await pumpOnSheet(tester, moving, onValueChanged: selected.add);
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);

    await tester.tap(find.text('E-bike 2028'));
    await tester.tap(find.text('Bike 2027'));
    // As UIKit tells it: only a new segment, with a light tap.
    expect(selected, [0]);
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    // Once the sheet rests, the native control is back under the stand-in
    // fading out, and takes the taps.
    moving.value = false;
    await tester.pump();
    expect(nativeViews(tester), 1);
    expect(standIn, findsOneWidget);
    await tester.tap(find.text('Bike 2027'), warnIfMissed: false);
    expect(selected, [0]);
  });

  testWidgets("the stand-in draws every label in the app font's face that "
      'iOS draws them in, at their size whatever the text size', (
    tester,
  ) async {
    const fonts = MethodChannel('adaptive_platform_ui/fonts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fonts,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        fonts,
        null,
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AdaptiveNativeFonts.register({
      FontWeight.w400: 'assets/fonts/rubik/rubik_regular.ttf',
      FontWeight.w600: 'assets/fonts/rubik/rubik_semi_bold.ttf',
    });
    debugDefaultTargetPlatformOverride = null;
    addTearDown(AdaptiveNativeFonts.debugReset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final moving = ValueNotifier<bool>(true);
    addTearDown(moving.dispose);

    await pumpOnSheet(tester, moving);

    final labels = tester.renderObjectList<RenderParagraph>(
      find.descendant(of: standIn, matching: find.byType(RichText)),
    );
    expect(labels, hasLength(2));
    for (final label in labels) {
      expect(label.text.style!.fontWeight, FontWeight.w600);
      expect(label.text.style!.fontSize, 13);
      // Material's body text, around it here, spaces its letters.
      expect(label.text.style!.letterSpacing, 0);
      expect(label.textScaler, TextScaler.noScaling);
    }
  });
}
