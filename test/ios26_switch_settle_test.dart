import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    IOS26Switch.debugHasUIKitOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async => null,
        );
  });

  tearDown(() {
    IOS26Switch.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  const barHeight = 100.0;
  final standIn = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_SwitchStandIn',
  );

  /// The native views composited in the last frame.
  int nativeViews(WidgetTester tester) =>
      tester.layers.whereType<PlatformViewLayer>().length;

  /// A list with a switch 300 points down, under a bar along the top whose
  /// frost is [frost]'s opacity.
  Future<ScrollController> pumpList(
    WidgetTester tester, {
    double frost = 1,
    GlobalKey<NavigatorState>? navigator,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: [
                  const SizedBox(height: 300),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [IOS26Switch(value: true, onChanged: (_) {})],
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: barHeight,
                child: Opacity(
                  opacity: frost,
                  child: const AdaptiveBarBackdrop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('a native switch scrolled under a bar leaves the frost to a '
      'stand-in, which the bar blurs with the rest, from the frame it gets '
      'there, and comes back as it scrolls out', (tester) async {
    final controller = await pumpList(tester);
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);

    // iOS blurs a native view under the frost within its own frame only: a
    // grey box with hard edges in the bar.
    controller.jumpTo(230);
    await tester.pump();
    expect(tester.getRect(find.byType(IOS26Switch)).top, lessThan(barHeight));
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
  });

  testWidgets('a native switch stays on screen under a bar with no frost '
      'showing', (tester) async {
    final controller = await pumpList(tester, frost: 0);

    controller.jumpTo(230);
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
  });

  testWidgets('a native switch that is not scrolled stays on screen where a '
      'frost is drawn, as in a bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: barHeight,
                child: AdaptiveBarBackdrop(),
              ),
              Positioned(
                right: 16,
                top: 40,
                child: IOS26Switch(value: false, onChanged: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
  });

  testWidgets('a native switch leaves the screen while a dialog covers its '
      'page, its stand-in in its place in the same state', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await pumpList(tester, navigator: navigator);
    final size = tester.getSize(find.byType(IOS26Switch));

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const Center(child: Text('dialog')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);
    expect(tester.getSize(find.byType(IOS26Switch)), size);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
  });
}
