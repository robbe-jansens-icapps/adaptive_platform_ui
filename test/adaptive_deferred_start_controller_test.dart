import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'it is under way at once but only moves once the first frames are built, all of its way',
    (tester) async {
      final controller = AdaptiveDeferredStartController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(const SizedBox());

      controller.forward();
      expect(controller.status, AnimationStatus.forward);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.value, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.value, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.value, closeTo(0.5, 0.01));
      await tester.pumpAndSettle();
      expect(controller.status, AnimationStatus.completed);
    },
  );

  testWidgets('sent back before it moves, it does not start after all', (
    tester,
  ) async {
    final controller = AdaptiveDeferredStartController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(const SizedBox());

    controller.forward();
    controller.reverse();
    await tester.pumpAndSettle();
    expect(controller.value, 0);
    expect(controller.status, AnimationStatus.dismissed);
  });

  testWidgets(
    'going away from fully in, it holds for a frame and then goes all of its way',
    (tester) async {
      final controller = AdaptiveDeferredStartController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      )..value = 1;
      addTearDown(controller.dispose);
      await tester.pumpWidget(const SizedBox());

      controller.reverse();
      expect(controller.status, AnimationStatus.reverse);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.value, 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.value, closeTo(0.5, 0.01));
      await tester.pumpAndSettle();
      expect(controller.status, AnimationStatus.dismissed);
    },
  );
}
