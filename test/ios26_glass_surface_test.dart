import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('a fill lies over the frosted stand-in', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: IOS26GlassSurface(fill: Color(0x80FFFFFF)),
        ),
      ),
    );

    final color = tester.widget<ColoredBox>(find.byType(ColoredBox)).color;
    expect(
      color,
      Color.alphaBlend(const Color(0x80FFFFFF), const Color(0xB3FFFFFF)),
    );
  });

  testWidgets('hands its fill to the native glass', (tester) async {
    IOS26GlassSurface.debugHasUIKitOverride = true;
    addTearDown(() => IOS26GlassSurface.debugHasUIKitOverride = null);
    final created = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          final params = (call.arguments as Map)['params'] as Uint8List;
          created.add(
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(params),
                )
                as Map<Object?, Object?>,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: IOS26GlassSurface(fill: Color(0x80FFFFFF)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(created.single['fill'], 0x80FFFFFF);
  });
}
