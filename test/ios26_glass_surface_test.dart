import 'dart:ui' show ImageFilter;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_view_settle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('drawn by Flutter on iOS, it blurs what is behind it in its '
      'shape and makes no native view', (tester) async {
    IOS26GlassSurface.debugHasUIKitOverride = true;
    addTearDown(() => IOS26GlassSurface.debugHasUIKitOverride = null);
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: IOS26GlassSurface(
              cornerRadius: 24,
              fill: const Color(0x80FFFFFF),
              drawnByFlutter: true,
              child: GestureDetector(
                onTap: () => taps++,
                child: const Text('content'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(UiKitView), findsNothing);
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur.filter, ImageFilter.blur(sigmaX: 20, sigmaY: 20));
    final clip = tester.layers.whereType<ClipRSuperellipseLayer>().single;
    expect(
      clip.clipRSuperellipse,
      BorderRadius.circular(
        24,
      ).toRSuperellipse(tester.getRect(find.byType(IOS26GlassSurface))),
    );
    await tester.tap(find.text('content'));
    expect(taps, 1);
  });

  testWidgets('drawn by Flutter, it shows the stand-in rather than the blur '
      'while what holds it moves, and blurs again once it rests', (
    tester,
  ) async {
    IOS26GlassSurface.debugHasUIKitOverride = true;
    addTearDown(() => IOS26GlassSurface.debugHasUIKitOverride = null);
    final moving = ValueNotifier<bool>(false);
    addTearDown(moving.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NativeViewSettleScope(
          moving: moving,
          child: const Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: IOS26GlassSurface(cornerRadius: 24, drawnByFlutter: true),
            ),
          ),
        ),
      ),
    );
    final blur = find.byType(BackdropFilter);
    final standIn = find.descendant(
      of: find.byType(FadeTransition),
      matching: find.byType(DecoratedBox),
    );
    expect(blur, findsOneWidget);
    expect(standIn, findsNothing);

    moving.value = true;
    await tester.pump();
    expect(blur, findsNothing);
    expect(standIn, findsOneWidget);

    moving.value = false;
    await tester.pump();
    // The stand-in fades out over the blur.
    expect(blur, findsOneWidget);
    expect(standIn, findsOneWidget);
    await tester.pumpAndSettle();
    expect(standIn, findsNothing);
    expect(find.byType(UiKitView), findsNothing);
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

  group('content clip', () {
    const content = Key('content');

    // A sheet floating 8 points from the bottom and sides of a 400 by 800
    // display with 62 point corners.
    Widget sheet({Clip clipBehavior = Clip.antiAlias}) => MaterialApp(
      home: Stack(
        children: [
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            height: 300,
            child: IOS26GlassSurface(
              cornerRadius: 34,
              corners: GlassSurfaceCorners.concentric,
              clipBehavior: clipBehavior,
              child: const SizedBox.expand(key: content),
            ),
          ),
        ],
      ),
    );

    void usePhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PlatformInfo.debugDisplayCornerRadiusOverride = 62;
      addTearDown(() => PlatformInfo.debugDisplayCornerRadiusOverride = null);
      IOS26GlassSurface.debugHasUIKitOverride = true;
      addTearDown(() => IOS26GlassSurface.debugHasUIKitOverride = null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
    }

    RenderObject clipOf(WidgetTester tester) =>
        tester.renderObject(find.byKey(content)).parent!;

    testWidgets('cuts the content off in the glass\'s concentric shape', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(sheet());

      const bottom = Radius.circular(62 - 8);
      expect(
        clipOf(tester),
        paints..clipRSuperellipse(
          rsuperellipse: const BorderRadius.only(
            topLeft: Radius.circular(34),
            topRight: Radius.circular(34),
            bottomLeft: bottom,
            bottomRight: bottom,
          ).toRSuperellipse(Offset.zero & const Size(384, 300)),
        ),
      );
    });

    testWidgets('leaves the content as it is unless asked', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(sheet(clipBehavior: Clip.none));

      expect(clipOf(tester), isNot(paints..clipRSuperellipse()));
    });

    testWidgets('never clips the glass itself', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(sheet());
      await tester.pump();

      final surface = tester.renderObject(find.byType(IOS26GlassSurface));
      final clip = clipOf(tester);
      RenderObject? ancestor = tester.renderObject(find.byType(UiKitView));
      while (ancestor != null && ancestor != surface) {
        expect(ancestor, isNot(same(clip)));
        ancestor = ancestor.parent;
      }
      expect(ancestor, same(surface));
    });
  });
}
