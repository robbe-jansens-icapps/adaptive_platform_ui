import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_over_fixture.dart';

void main() {
  setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.android);
  tearDown(() => PlatformInfo.debugPlatformOverride = null);

  testWidgets('a destination with an identifier has it on its node in the '
      'Material navigation bar, for UI tests', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveScaffold(
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            items: const [
              AdaptiveNavigationDestination(
                icon: Icons.map,
                label: 'Map',
                identifier: 'tab_map',
              ),
              AdaptiveNavigationDestination(
                icon: Icons.person,
                label: 'Account',
              ),
            ],
            selectedIndex: 0,
            onTap: (_) {},
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    final map = find.semantics
        .byPredicate((node) => node.identifier == 'tab_map')
        .evaluate()
        .single;
    expect(
      tester.getRect(
        find.ancestor(
          of: find.text('Map'),
          matching: find.byType(NavigationDestination),
        ),
      ),
      globalRectOf(tester, map),
    );
    expect(
      find.semantics.byPredicate((node) => node.identifier.isNotEmpty),
      findsOne,
    );
    semantics.dispose();
  });
}
