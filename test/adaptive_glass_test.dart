import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpGlass(WidgetTester tester, Widget glass, {bool highContrast = false}) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 200, height: 56, child: glass)),
      ),
    ),
  );

  ShapeDecoration tintOf(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(find.descendant(of: find.byType(AdaptiveGlass), matching: find.byType(DecoratedBox)))
      .map((box) => box.decoration)
      .whereType<ShapeDecoration>()
      .firstWhere((decoration) => decoration.color != null);

  testWidgets('blurs what is underneath a translucent tint', (tester) async {
    await pumpGlass(tester, const AdaptiveGlass(style: AdaptiveGlassStyle(tint: Color(0xB0202020)), child: Text('Tabs')));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipPath), findsOneWidget);
    expect(tintOf(tester).color, const Color(0xB0202020));
    expect(find.text('Tabs'), findsOneWidget);
  });

  testWidgets('draws no blur where nothing shows through it', (tester) async {
    await pumpGlass(tester, const AdaptiveGlass(style: AdaptiveGlassStyle(tint: Color(0xFF202020))));
    expect(find.byType(BackdropFilter), findsNothing);

    await pumpGlass(tester, const AdaptiveGlass(style: AdaptiveGlassStyle(blurSigma: 0)));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('takes the style of the theme around it', (tester) async {
    await pumpGlass(
      tester,
      const AdaptiveGlassTheme(
        style: AdaptiveGlassStyle(tint: Color(0xCCFF8800)),
        child: AdaptiveGlass(),
      ),
    );

    expect(tintOf(tester).color, const Color(0xCCFF8800));
  });

  testWidgets('turns opaque when the user asks for more contrast', (tester) async {
    await pumpGlass(tester, const AdaptiveGlass(style: AdaptiveGlassStyle(tint: Color(0xB0202020))), highContrast: true);

    expect(find.byType(BackdropFilter), findsNothing);
    expect(tintOf(tester).color, const Color(0xFF202020));

    await pumpGlass(
      tester,
      const AdaptiveGlass(style: AdaptiveGlassStyle(tint: Color(0xB0202020), highContrastTint: Color(0xFF000000))),
      highContrast: true,
    );
    expect(tintOf(tester).color, const Color(0xFF000000));
  });

  testWidgets('outlines its shape with the rim and casts its shadows outside it', (tester) async {
    await pumpGlass(
      tester,
      AdaptiveGlass(
        style: const AdaptiveGlassStyle(rimColor: Color(0x66FFFFFF), rimWidth: 2, shadows: [BoxShadow(blurRadius: 4)]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );

    final tint = tintOf(tester);
    final shape = tint.shape as RoundedRectangleBorder;
    expect(shape.side, const BorderSide(color: Color(0x66FFFFFF), width: 2));
    expect(shape.borderRadius, BorderRadius.circular(20));
    final outer = tester.widget<DecoratedBox>(find.descendant(of: find.byType(AdaptiveGlass), matching: find.byType(DecoratedBox)).first);
    expect((outer.decoration as ShapeDecoration).shadows, const [BoxShadow(blurRadius: 4)]);
  });

  testWidgets('shares one read of the content with the glass around it in a BackdropGroup', (tester) async {
    await pumpGlass(
      tester,
      BackdropGroup(
        child: const Row(
          children: [
            Expanded(child: AdaptiveGlass()),
            Expanded(child: AdaptiveGlass()),
          ],
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
