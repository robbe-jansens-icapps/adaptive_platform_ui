import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
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

  /// The native glass views created, by the view type they were created for.
  final created = <int>[];

  setUp(() {
    IOS26GlassSurface.debugHasUIKitOverride = true;
    created.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            created.add((call.arguments as Map)['id'] as int);
          }
          return null;
        });
  });

  tearDown(() {
    IOS26GlassSurface.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Widget glassPage(String name) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 200,
        height: 60,
        child: IOS26GlassSurface(
          key: ValueKey(name),
          corners: GlassSurfaceCorners.capsule,
          child: Text(name),
        ),
      ),
    ),
  );

  Widget app(GlobalKey<NavigatorState> navigator, {bool host = false}) =>
      MaterialApp(
        navigatorKey: navigator,
        builder: host
            ? (context, child) =>
                  AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!)
            : null,
        home: glassPage('home'),
      );

  Finder glassOf(String name) => find.byKey(ValueKey(name));

  /// Whether the native glass of [name] is on screen (not off stage).
  bool showsNative(WidgetTester tester, String name) {
    final offstage = tester.widget<Offstage>(
      find.descendant(of: glassOf(name), matching: find.byType(Offstage)),
    );
    return !offstage.offstage;
  }

  /// Whether the Flutter stand-in of [name] is drawn, and how strongly.
  double standIn(WidgetTester tester, String name) {
    final fades = find.descendant(
      of: glassOf(name),
      matching: find.byType(FadeTransition),
    );
    if (fades.evaluate().isEmpty) return 0;
    return tester.widget<FadeTransition>(fades.first).opacity.value;
  }

  testWidgets('a page at rest shows the native glass, the stand-in fading out '
      'once it is there', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator));
    expect(standIn(tester, 'home'), 1);

    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(showsNative(tester, 'home'), isTrue);
    expect(standIn(tester, 'home'), 0);
  });

  testWidgets('a page pushed over it hides its glass behind the stand-in, '
      'and the same native view comes back once uncovered', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator));
    await tester.pumpAndSettle();

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => glassPage('next')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Native glass would show through the page sliding over it.
    expect(showsNative(tester, 'home'), isFalse);
    expect(standIn(tester, 'home'), 1);
    // The new page's glass is not made while the page moves.
    expect(created, hasLength(1));
    expect(standIn(tester, 'next'), 1);

    await tester.pumpAndSettle();
    expect(created, hasLength(2));
    expect(showsNative(tester, 'next'), isTrue);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(showsNative(tester, 'home'), isFalse);

    await tester.pumpAndSettle();
    expect(showsNative(tester, 'home'), isTrue);
    expect(standIn(tester, 'home'), 0);
    // Not created anew.
    expect(created, hasLength(2));
  });

  testWidgets('a full-screen dialog covers it too, though the page below does '
      'not move, until it has gone again', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator, host: true));
    await tester.pumpAndSettle();

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Dialog', useNativeToolbar: true),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(showsNative(tester, 'home'), isFalse);
    await tester.pumpAndSettle();

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Current again, but the dialog still slides away over it.
    expect(showsNative(tester, 'home'), isFalse);

    await tester.pumpAndSettle();
    expect(showsNative(tester, 'home'), isTrue);
  });

  testWidgets('a dialog over it shows the stand-in while it is open', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator));
    await tester.pumpAndSettle();

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(showsNative(tester, 'home'), isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(showsNative(tester, 'home'), isTrue);
  });
}
