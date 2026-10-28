import 'dart:convert';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/style/glass_button_glyph.dart';
import 'package:adaptive_platform_ui/src/toolbar/chrome_barrier.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:flutter/foundation.dart';
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

/// A 1×1 PNG: what iOS draws a glyph into, as far as a test can tell.
final glyphPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget page(String title) => AdaptiveScaffold(
  appBar: AdaptiveAppBar(useNativeToolbar: true, titleWidget: Text(title)),
  body: Center(child: Text('body:$title')),
);

Widget hostedApp(GlobalKey<NavigatorState> navigator) => MaterialApp(
  navigatorKey: navigator,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
  home: page('Home'),
);

final standIn = find.byKey(
  const ValueKey<String>('adaptive_toolbar_back_stand_in'),
);

/// The native back buttons on stage: the one in the chevron's place.
final nativeBack = find.descendant(
  of: find.byType(HostedTopToolbar),
  matching: find.byType(AdaptiveButton),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The glyphs iOS was asked for.
  final asked = <Map<Object?, Object?>>[];
  var drawsGlyphs = true;

  setUp(() {
    asked.clear();
    drawsGlyphs = true;
    GlassButtonGlyph.debugReset();
    GlassButtonGlyph.debugDecodes = false;
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('adaptive_platform_ui/symbols'),
      (call) async {
        expect(call.method, 'buttonGlyph');
        asked.add(call.arguments as Map<Object?, Object?>);
        return drawsGlyphs
            ? {
                'bytes': glyphPng,
                'scale': 1.0,
                // As iOS reports them: its colour, and a glyph a little off
                // the button's centre.
                'color': 0xFF0066DD,
                'dx': -1.5,
                'dy': 0.5,
              }
            : null;
      },
    );
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    GlassButtonGlyph.debugReset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('adaptive_platform_ui/symbols'),
      null,
    );
  });

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  /// The app, with the glyphs drawn and decoded.
  Future<GlobalKey<NavigatorState>> start(WidgetTester tester) async {
    usePhone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator));
    await tester.pumpAndSettle();
    return navigator;
  }

  testWidgets('the glyphs of both buttons come from iOS as the native buttons '
      'show them, before any page needs them, and again in the other '
      'appearance', (tester) async {
    await start(tester);
    expect(asked, [
      {
        'name': 'chevron.left',
        'size': 19.0,
        'weight': 600,
        'side': 44.0,
        'isDark': false,
      },
      {
        'name': 'xmark',
        'size': 17.0,
        'weight': 600,
        'side': 44.0,
        'isDark': false,
      },
    ]);

    asked.clear();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(asked.map((args) => (args['name'], args['isDark'])), [
      ('chevron.left', true),
      ('xmark', true),
    ]);
  }, variant: ios);

  testWidgets('while it fades in with a page coming in, a Flutter button '
      'with the glyph stands in for the native one, which is back once the '
      'page holds still', (tester) async {
    final navigator = await start(tester);
    expect(nativeBack, findsNothing);

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Detail')),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      // Never a native button while the page moves.
      expect(nativeBack, findsNothing);
    }
    expect(standIn, findsOneWidget);
    final glyph = tester.widget<Image>(
      find.descendant(of: standIn, matching: find.byType(Image)),
    );
    expect(glyph.image, isA<MemoryImage>());
    expect((glyph.image as MemoryImage).bytes, orderedEquals(glyphPng));
    // In the colour, and in the place, iOS shows it in.
    expect(glyph.color, const Color(0xFF0066DD));
    expect(glyph.colorBlendMode, BlendMode.srcIn);
    final moved = tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byWidget(glyph),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation();
    expect((moved.x, moved.y), (-1.5, 0.5));

    await tester.pumpAndSettle();
    expect(nativeBack, findsOneWidget);
    expect(standIn, findsNothing);
  }, variant: ios);

  testWidgets('it stands in while the button fades out with the page that '
      'pops, and while a back swipe drags it', (tester) async {
    final navigator = await start(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Detail')),
    );
    await tester.pumpAndSettle();
    expect(nativeBack, findsOneWidget);

    final swipe = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 4; i++) {
      await swipe.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(nativeBack, findsNothing);
    expect(standIn, findsOneWidget);
    await swipe.moveBy(const Offset(200, 0));
    await swipe.up();
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsNothing);

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Detail')),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(nativeBack, findsNothing);
    expect(standIn, findsOneWidget);
    await tester.pumpAndSettle();
  }, variant: ios);

  testWidgets('a back button both pages show is stood in for too while the '
      'pages move, and is native again once they hold still', (tester) async {
    final navigator = await start(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('One')),
    );
    await tester.pumpAndSettle();
    expect(nativeBack, findsOneWidget);

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Two')),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(nativeBack, findsNothing);
      expect(standIn, findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(nativeBack, findsOneWidget);
    expect(standIn, findsNothing);
  }, variant: ios);

  testWidgets('without a glyph from iOS the native button stays', (
    tester,
  ) async {
    drawsGlyphs = false;
    final navigator = await start(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Detail')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(standIn, findsNothing);
    expect(nativeBack, findsOneWidget);
    await tester.pumpAndSettle();
  }, variant: ios);

  testWidgets('a tap on the stand-in goes back, as one on the button does', (
    tester,
  ) async {
    final navigator = await start(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Detail')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(standIn, findsOneWidget);
    await tester.tap(standIn, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsNothing);
  }, variant: ios);

  testWidgets('the chevron keeps the system\'s colour, or takes the bar\'s '
      'tint where the app bar asks for it, as its actions do', (tester) async {
    final navigator = await start(tester);
    const green = Color(0xFF007C30);
    for (final tints in [false, true]) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              useNativeToolbar: true,
              tintColor: green,
              tintsBackButton: tints,
              titleWidget: const Text('Tinted'),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final back = tester.widget<AdaptiveButton>(nativeBack.last);
      expect(back.sfSymbol?.name, 'chevron.left');
      expect(back.sfSymbol?.color, tints ? green : null);
    }
  });

  group('shown over the Flutter view', () {
    const buttonType = 'adaptive_platform_ui/ios26_button';

    /// The native views made over the Flutter view by id, and the values of
    /// the last layout iOS got for each.
    final made = <int, String>{};
    final layouts = <int, List<double>>{};

    setUp(() {
      made.clear();
      layouts.clear();
      AdaptiveNativeChrome.enabled = true;
      IOS26Button.debugHasUIKitOverride = true;
      NativeChromeCoordinator.instance.debugReset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeChromeCoordinator.channel, (
            call,
          ) async {
            if (call.method == 'create') {
              final args = call.arguments as Map<Object?, Object?>;
              made[args['id']! as int] = args['viewType']! as String;
            } else if (call.method == 'layout') {
              final values = call.arguments as Float64List;
              for (
                var i = 0;
                i < values.length;
                i += NativeChromeCoordinator.stride
              ) {
                layouts[values[i].toInt()] = values.sublist(
                  i,
                  i + NativeChromeCoordinator.stride,
                );
              }
            }
            return null;
          });
    });

    tearDown(() {
      AdaptiveNativeChrome.enabled = false;
      IOS26Button.debugHasUIKitOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
    });

    /// The values of the native buttons on screen.
    List<List<double>> shownButtons() => [
      for (final MapEntry(key: id, value: type) in made.entries)
        if (type == buttonType &&
            layouts[id] != null &&
            layouts[id]![27].toInt() & NativeChromeCoordinator.hiddenFlag == 0)
          layouts[id]!,
    ];

    testWidgets('over the Flutter view the native back button moves and '
        'fades with the pages, with no stand-in', (tester) async {
      final navigator = await start(tester);
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(standIn, findsNothing);
      expect(shownButtons(), hasLength(1));
      expect(shownButtons().single[19], allOf(greaterThan(0), lessThan(1)));

      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(standIn, findsNothing);
      await tester.pumpAndSettle();
    }, variant: ios);

    testWidgets('the back button is a native button over the Flutter view, '
        'whose glass iOS dims under a dialog', (tester) async {
      final navigator = await start(tester);
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pumpAndSettle();
      expect(shownButtons(), hasLength(1));
      expect(shownButtons().single[28], 0);

      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const Center(child: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      // Over the button's glass Flutter lays none: it would lie under it.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChromeBarrierBox && widget.shape is CircleBorder,
        ),
        findsNothing,
      );
      expect(shownButtons(), hasLength(1));
      final dim = Color(shownButtons().single[28].toInt());
      expect(dim.withValues(alpha: 1), Colors.black);
      expect(dim.a, greaterThan(0));

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(shownButtons().single[28], 0);
    }, variant: ios);
  });
}
