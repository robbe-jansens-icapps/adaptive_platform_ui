import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lays its content over a frosted stand-in off device', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: IOS26GlassSurface(
              cornerRadius: 24,
              child: Center(
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const Text('content'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      tester
          .widget<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
          .borderRadius,
      BorderRadius.circular(24),
    );
    expect(
      tester.getSize(find.byType(IOS26GlassSurface)),
      const Size(200, 100),
    );

    await tester.tap(find.text('content'));
    expect(taps, 1);
  });

  testWidgets('a capsule rounds the short side fully', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 200,
          height: 40,
          child: IOS26GlassSurface(corners: GlassSurfaceCorners.capsule),
        ),
      ),
    );

    expect(
      tester
          .widget<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
          .borderRadius,
      BorderRadius.circular(20),
    );
  });

  testWidgets('a tint colors the stand-in', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: IOS26GlassSurface(tint: Color(0xFF009DD6)),
        ),
      ),
    );

    final color = tester.widget<ColoredBox>(find.byType(ColoredBox)).color;
    expect(color, isNot(const Color(0xB3FFFFFF)));
  });
}
