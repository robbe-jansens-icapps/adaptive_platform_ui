import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    IOS26Button.debugHasUIKitOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async => null,
        );
  });

  tearDown(() {
    IOS26Button.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  final button = find.byType(IOS26Button);
  final standIn = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_ButtonStandIn',
  );

  /// The native views composited in the last frame: those of the button
  /// while its page holds still in front.
  int nativeViews(WidgetTester tester) =>
      tester.layers.whereType<PlatformViewLayer>().length;

  Future<void> pumpPage(WidgetTester tester, GlobalKey<NavigatorState> root) =>
      tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 44,
                child: IOS26Button.sfSymbol(
                  onPressed: () {},
                  sfSymbol: const SFSymbol('plus', size: 18),
                  useSmoothRectangleBorder: false,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a native button leaves the screen while a dialog covers its '
      'page, a stand-in taking its place, and comes back once it has gone', (
    tester,
  ) async {
    final root = GlobalKey<NavigatorState>();
    await pumpPage(tester, root);
    await tester.pumpAndSettle();
    final size = tester.getSize(button);
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);

    // Left on screen, iOS showed the dialog's barrier, and a page pushed over
    // it, only within the clip around the native view.
    showDialog<void>(
      context: root.currentContext!,
      builder: (_) => const Center(child: Text('dialog')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(nativeViews(tester), 0);
    expect(standIn, findsOneWidget);
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 0);
    expect(tester.getSize(button), size);

    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 1);
    expect(standIn, findsNothing);
    expect(tester.getSize(button), size);
  });

  testWidgets('a page sliding over the button finds it gone for the stand-in', (
    tester,
  ) async {
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

  testWidgets('a button with a label shows it in its stand-in, at its size', (
    tester,
  ) async {
    final root = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: IOS26Button(onPressed: () {}, label: 'Rent'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(button);
    // The native button draws its label itself.
    expect(find.text('Rent'), findsNothing);

    showDialog<void>(
      context: root.currentContext!,
      builder: (_) => const Center(child: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(nativeViews(tester), 0);
    expect(
      find.descendant(of: standIn, matching: find.text('Rent')),
      findsOneWidget,
    );
    expect(tester.getSize(standIn), size);
  });
}
