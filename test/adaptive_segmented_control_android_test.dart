import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.android);
  tearDown(() => PlatformInfo.debugPlatformOverride = null);

  Future<List<int>> pumpControl(WidgetTester tester, {int selected = 0}) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AdaptiveSegmentedControl(
                labels: const ['Bike 404', 'Cargo bike 3528'],
                selectedIndex: selected,
                onValueChanged: picked.add,
                color: const Color(0xFF009DD6),
              ),
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Color? fillOf(WidgetTester tester, Finder pill) =>
      (tester.widget<DecoratedBox>(pill).decoration as ShapeDecoration).color;

  testWidgets('on Android it is a pill with the selected segment filled, '
      'without a checkmark or an outline', (tester) async {
    await pumpControl(tester);

    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    final thumb = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(DecoratedBox),
    );
    expect(fillOf(tester, thumb), const Color(0xFF009DD6));
    // The filled pill sits under the selected segment.
    expect(
      tester.getCenter(thumb).dx,
      closeTo(tester.getCenter(find.text('Bike 404')).dx, 1),
    );
  });

  testWidgets('a tap picks another segment, and the fill slides to it', (
    tester,
  ) async {
    final picked = await pumpControl(tester);

    await tester.tap(find.text('Cargo bike 3528'));
    expect(picked, [1]);

    await pumpControl(tester, selected: 1);
    await tester.pumpAndSettle();
    final thumb = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(DecoratedBox),
    );
    expect(
      tester.getCenter(thumb).dx,
      closeTo(tester.getCenter(find.text('Cargo bike 3528')).dx, 1),
    );
  });

  testWidgets('tells assistive technologies which segment is selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpControl(tester);

    expect(
      tester.getSemantics(find.text('Bike 404')),
      matchesSemantics(
        label: 'Bike 404',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    handle.dispose();
  });
}
