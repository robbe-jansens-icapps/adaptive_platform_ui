import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.android);
  tearDown(() => PlatformInfo.debugPlatformOverride = null);

  Future<void> setWidth(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    addTearDown(tester.view.reset);
    await tester.pump();
  }

  Widget tabs({
    double? railMinWidth,
    ValueChanged<int>? onTap,
    Widget? accessory,
    Widget body = const SizedBox.expand(),
  }) => MaterialApp(
    home: AdaptiveScaffold(
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        items: const [
          AdaptiveNavigationDestination(
            icon: Icons.map,
            label: 'Map',
            identifier: 'tab_map',
          ),
          AdaptiveNavigationDestination(icon: Icons.person, label: 'Account'),
        ],
        selectedIndex: 0,
        onTap: onTap ?? (_) {},
        accessory: accessory,
        railMinWidth: railMinWidth,
      ),
      body: body,
    ),
  );

  testWidgets('a window at least railMinWidth wide shows the tabs as a rail '
      'with the accessory at its top', (tester) async {
    await setWidth(tester, 800);
    AdaptiveAccessorySpec? spec;
    var tapped = -1;
    await tester.pumpWidget(
      tabs(
        railMinWidth: 600,
        onTap: (index) => tapped = index,
        accessory: Builder(
          builder: (context) {
            spec = AdaptiveAccessoryScope.maybeOf(context);
            return const SizedBox(width: 40, height: 40);
          },
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(spec, AdaptiveBottomNavigationBar.railAccessorySpec);
    expect(
      find.semantics.byPredicate((node) => node.identifier == 'tab_map'),
      findsOne,
    );

    await tester.tap(find.text('Account'));
    expect(tapped, 1);
  });

  testWidgets('a narrower window keeps the navigation bar', (tester) async {
    await setWidth(tester, 400);
    await tester.pumpWidget(tabs(railMinWidth: 600));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('without railMinWidth the bar stays at any width', (
    tester,
  ) async {
    await setWidth(tester, 1000);
    await tester.pumpWidget(tabs());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('the pages keep their state as the window widens past '
      'railMinWidth and narrows again', (tester) async {
    await setWidth(tester, 400);
    await tester.pumpWidget(tabs(railMinWidth: 600, body: const _Counter()));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await setWidth(tester, 800);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await setWidth(tester, 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('$_count'),
    ),
  );
}
