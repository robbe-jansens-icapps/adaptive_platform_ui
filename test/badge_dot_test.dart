import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_glass_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('badge dot', () {
    test('reaches the native views as kBadgeDot', () {
      const dot = AdaptiveNavigationDestination(
        icon: Icons.home,
        label: 'Home',
        showsBadgeDot: true,
      );

      expect(dot.nativeBadge, kBadgeDot);
      expect(GlassCapsuleItem.fromDestination(dot).toNativeMap()['badge'], -1);
    });

    test('gives way to a count', () {
      const counted = AdaptiveNavigationDestination(
        icon: Icons.home,
        label: 'Home',
        badgeCount: 3,
        showsBadgeDot: true,
      );

      expect(counted.nativeBadge, 3);
    });

    test('is absent by default', () {
      const plain = AdaptiveNavigationDestination(
        icon: Icons.home,
        label: 'Home',
      );

      expect(plain.nativeBadge, isNull);
      expect(
        GlassCapsuleItem.fromDestination(plain).toNativeMap(),
        isNot(contains('badge')),
      );
    });

    testWidgets('is drawn on the Material tab bar', (tester) async {
      PlatformInfo.debugPlatformOverride = TargetPlatform.android;
      addTearDown(() => PlatformInfo.debugPlatformOverride = null);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              selectedIndex: 0,
              onTap: (_) {},
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(
                  icon: Icons.info,
                  label: 'Info',
                  showsBadgeDot: true,
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );

      expect(
        find.ancestor(of: find.byIcon(Icons.info), matching: find.byType(Badge)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.byIcon(Icons.home), matching: find.byType(Badge)),
        findsNothing,
      );
    });
  });
}
