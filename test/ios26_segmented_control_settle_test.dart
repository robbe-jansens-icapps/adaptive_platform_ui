import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
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
}
