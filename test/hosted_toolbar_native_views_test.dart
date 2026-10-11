import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// Forces the chrome on (there is no iOS 26 in a widget test).
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The native views created: their type and what they were created with.
  final created = <(String, Map<Object?, Object?>?)>[];

  setUp(() {
    created.clear();
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map<Object?, Object?>;
            final params = args['params'] as Uint8List?;
            created.add((
              args['viewType']! as String,
              params == null
                  ? null
                  : const StandardMessageCodec().decodeMessage(
                          ByteData.sublistView(params),
                        )
                        as Map<Object?, Object?>?,
            ));
          }
          return null;
        });
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
  }

  Widget page(
    String title, {
    List<AdaptiveAppBarAction>? actions,
    AdaptiveBackButtonStyle back = AdaptiveBackButtonStyle.back,
  }) => AdaptiveScaffold(
    appBar: AdaptiveAppBar(
      useNativeToolbar: true,
      titleWidget: Text(title),
      actions: actions,
      backButtonStyle: back,
    ),
    body: const SizedBox.expand(),
  );

  Widget hostedApp(GlobalKey<NavigatorState> navigator, Widget home) =>
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
        home: home,
      );

  Iterable<Map<Object?, Object?>?> createdOf(String viewType) =>
      created.where((view) => view.$1 == viewType).map((view) => view.$2);

  testWidgets(
    'the back button is a circle as tall as the bar, in the system glyph, '
    'made once for each look and kept from page to page',
    (tester) async {
      usePhone(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigator, page('Home')));
      await tester.pumpAndSettle();
      final buttons = find.descendant(
        of: find.byType(HostedTopToolbar),
        matching: find.byType(AdaptiveButton, skipOffstage: false),
        skipOffstage: false,
      );
      // A chevron and a cross, ready before any page needs them.
      expect(buttons, findsNWidgets(2));
      final looks = tester.widgetList<AdaptiveButton>(buttons);
      for (final button in looks) {
        expect(button.useSmoothRectangleBorder, isFalse);
        expect(button.sfSymbol!.weight, FontWeight.w600);
        expect(
          tester.getSize(find.byWidget(button, skipOffstage: false)),
          const Size.square(44),
        );
      }
      expect(looks.map((button) => button.sfSymbol!.name), {
        'chevron.left',
        'xmark',
      });
      final elements = buttons.evaluate().toList();

      for (var i = 0; i < 2; i++) {
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => page('Detail')),
        );
        await tester.pumpAndSettle();
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => page('Dialog', back: AdaptiveBackButtonStyle.close),
          ),
        );
        await tester.pumpAndSettle();
        navigator.currentState!
          ..pop()
          ..pop();
        await tester.pumpAndSettle();
      }

      // The same two, never made again.
      expect(buttons.evaluate().toList(), elements);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a page without bar buttons gets no native bar; one with them '
      'does', (tester) async {
    usePhone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, page('Home')));
    await tester.pumpAndSettle();
    expect(createdOf('adaptive_platform_ui/ios26_toolbar'), isEmpty);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => page(
          'Detail',
          actions: [AdaptiveAppBarAction(title: 'Edit', onPressed: () {})],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(createdOf('adaptive_platform_ui/ios26_toolbar'), hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a long title keeps clear of the back button and the bar '
      'buttons, centred between them', (tester) async {
    usePhone(tester);
    const long =
        'Rate formulas and account management, a title far too long to fit';
    Widget titled({List<AdaptiveAppBarAction>? actions}) => AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        useNativeToolbar: true,
        titleWidget: const Text(
          long,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: actions,
      ),
      body: const SizedBox.expand(),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, page('Home')));
    await tester.pumpAndSettle();

    // Back button: 16 points in, 44 wide, then 8 points of room.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => titled()),
    );
    await tester.pumpAndSettle();
    var title = tester.getRect(find.text(long));
    expect(title.left, greaterThanOrEqualTo(16 + 44 + 8));
    expect(title.right, lessThanOrEqualTo(402 - (16 + 44 + 8)));
    expect(title.center.dx, closeTo(201, 0.5));

    // Two bar buttons take more room on the right: the left keeps as much.
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => titled(
          actions: [
            AdaptiveAppBarAction(
              iosSymbol: 'square.and.arrow.up',
              onPressed: () {},
            ),
            AdaptiveAppBarAction(iosSymbol: 'ellipsis', onPressed: () {}),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    title = tester.getRect(find.text(long));
    expect(title.right, lessThanOrEqualTo(402 - (16 + 88 + 8)));
    expect(title.left, greaterThanOrEqualTo(16 + 88 + 8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
