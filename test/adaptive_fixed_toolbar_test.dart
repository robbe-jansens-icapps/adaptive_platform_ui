import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// Forces the chrome on; the insets are those of an ordinary iPhone.
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

/// The iPhone Duo inner display in landscape: the strip on the right.
void useDuo(WidgetTester tester) {
  tester.view.physicalSize = const Size(951, 669);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget mapPage({VoidCallback? onLocate, bool showsBackdrop = false}) =>
    AdaptiveFixedToolbar(
      appBar: AdaptiveAppBar(
        useNativeToolbar: true,
        automaticallyImplyLeading: false,
        showsBackdrop: showsBackdrop,
        actions: [
          AdaptiveAppBarAction(
            icon: Icons.my_location,
            label: 'My location',
            onPressed: onLocate ?? () {},
          ),
        ],
      ),
      child: const ColoredBox(color: Colors.green, child: SizedBox.expand()),
    );

Widget hostedApp(Widget home, {FoldableData? fold}) => MaterialApp(
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: fold ?? forcedChrome(), child: child!),
  home: home,
);

double backdropOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.byKey(const ValueKey<String>('adaptive_toolbar_backdrop')),
    )
    .opacity
    .value;

void main() {
  testWidgets('shows the page\'s actions in the fixed toolbar', (tester) async {
    usePhone(tester);
    var located = 0;
    await tester.pumpWidget(hostedApp(mapPage(onLocate: () => located++)));
    await tester.pump();

    final action = find.descendant(
      of: find.byType(HostedTopToolbar),
      matching: find.byIcon(Icons.my_location),
    );
    expect(action, findsOneWidget);

    await tester.tap(action);
    expect(located, 1);
  });

  testWidgets('leaves the page clear when it asks for no backdrop', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(mapPage()));
    await tester.pump();
    expect(backdropOpacity(tester), 0);

    await tester.pumpWidget(hostedApp(mapPage(showsBackdrop: true)));
    await tester.pump();
    expect(backdropOpacity(tester), 1);
  });

  testWidgets('puts the actions in the vertical bar on iPhone Duo', (
    tester,
  ) async {
    useDuo(tester);
    await tester.pumpWidget(hostedApp(mapPage()));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(HostedDuoBar),
        matching: find.byIcon(Icons.my_location),
      ),
      findsOneWidget,
    );
  });

  testWidgets('takes its actions away when the page goes', (tester) async {
    usePhone(tester);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
        home: const SizedBox.expand(),
      ),
    );
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => mapPage()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    nav.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.my_location), findsNothing);
  });
}
