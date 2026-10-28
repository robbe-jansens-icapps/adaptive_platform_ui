import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_occluder.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What iOS was told about each view, by id: the values of its last `layout`.
class _Host {
  _Host({this.frameLocked = false});

  /// Whether the host applies each frame's message with its pixels.
  final bool frameLocked;

  final List<String> calls = <String>[];
  final Map<int, Float64List> views = <int, Float64List>{};
  int layouts = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    if (call.method == 'reset' && frameLocked) {
      return <String, Object?>{'frameLocked': true};
    }
    if (call.method == 'layout') {
      layouts++;
      final values = call.arguments as Float64List;
      for (var i = 0; i < values.length; i += NativeChromeCoordinator.stride) {
        views[values[i].toInt()] = Float64List.sublistView(
          values,
          i,
          i + NativeChromeCoordinator.stride,
        );
      }
    }
    return null;
  }

  Float64List get only => views.values.single;

  static Rect rectOf(Float64List v) {
    final transform = Matrix4.fromList(v.sublist(3, 19));
    return MatrixUtils.transformRect(
      transform,
      Rect.fromLTWH(0, 0, v[1], v[2]),
    );
  }

  static bool hidden(Float64List v) =>
      v[27].toInt() & NativeChromeCoordinator.hiddenFlag != 0;

  static bool interactive(Float64List v) =>
      v[27].toInt() & NativeChromeCoordinator.interactiveFlag != 0;
}

void main() {
  late _Host host;

  setUp(() {
    host = _Host();
    NativeChromeCoordinator.instance.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, host.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
  });

  Widget view({Key? key, bool interactive = true}) => NativeChromeView(
    key: key,
    viewType: 'adaptive_platform_ui/ios26_button',
    interactive: interactive,
  );

  Widget placed(Widget child, {Offset at = const Offset(20, 40)}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: at.dx,
              top: at.dy,
              width: 100,
              height: 44,
              child: child,
            ),
          ],
        ),
      );

  testWidgets('makes the view and places it where its placeholder is', (
    tester,
  ) async {
    int? createdId;
    await tester.pumpWidget(
      placed(
        NativeChromeView(
          viewType: 'adaptive_platform_ui/ios26_button',
          onPlatformViewCreated: (id) => createdId = id,
        ),
      ),
    );

    expect(host.calls.take(3), <String>['reset', 'create', 'layout']);
    expect(createdId, isNotNull);
    expect(_Host.rectOf(host.only), const Rect.fromLTWH(20, 40, 100, 44));
    expect(host.only[19], 1.0);
    expect(_Host.hidden(host.only), isFalse);
    expect(_Host.interactive(host.only), isTrue);
  });

  testWidgets('sends nothing for a frame in which nothing changed', (
    tester,
  ) async {
    await tester.pumpWidget(placed(view()));
    final layouts = host.layouts;

    tester.binding.scheduleFrame();
    await tester.pump();

    expect(host.layouts, layouts);
  });

  testWidgets('follows a fade above it that does not repaint it', (
    tester,
  ) async {
    final opacity = ValueNotifier<double>(1);
    addTearDown(opacity.dispose);
    await tester.pumpWidget(
      placed(
        ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (context, value, child) => FadeTransition(
            opacity: AlwaysStoppedAnimation(value),
            child: child,
          ),
          child: view(),
        ),
      ),
    );

    opacity.value = 0.5;
    await tester.pump();

    expect(host.only[19], closeTo(0.5, 0.01));
  });

  testWidgets('takes the transform of a slide or scale above it', (
    tester,
  ) async {
    await tester.pumpWidget(
      placed(
        Transform.scale(
          scale: 2,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: const Offset(10, 0),
            child: view(),
          ),
        ),
      ),
    );

    expect(_Host.rectOf(host.only), const Rect.fromLTWH(40, 40, 200, 88));
  });

  testWidgets('is clipped by a clip above it that cuts into it', (
    tester,
  ) async {
    await tester.pumpWidget(
      placed(
        Align(
          alignment: Alignment.topLeft,
          child: ClipRect(
            child: SizedBox(
              width: 50,
              height: 44,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 100,
                maxWidth: 100,
                child: view(),
              ),
            ),
          ),
        ),
      ),
    );

    final values = host.only;
    expect(values[20], 1);
    expect(
      Rect.fromLTRB(values[21], values[22], values[23], values[24]),
      const Rect.fromLTWH(20, 40, 50, 44),
    );
  });

  testWidgets('sends no clip for one that holds all of it', (tester) async {
    await tester.pumpWidget(placed(ClipRect(child: view())));

    expect(host.only[20], 0);
  });

  testWidgets('leaves the screen one frame after it stops being painted', (
    tester,
  ) async {
    final offstage = ValueNotifier<bool>(false);
    addTearDown(offstage.dispose);
    await tester.pumpWidget(
      placed(
        ValueListenableBuilder<bool>(
          valueListenable: offstage,
          builder: (context, value, child) =>
              Opacity(opacity: value ? 0 : 1, child: child),
          child: view(),
        ),
      ),
    );

    offstage.value = true;
    await tester.pump();
    // Still on screen while the stand-in comes, but no longer taking touches.
    expect(_Host.hidden(host.only), isFalse);
    expect(_Host.interactive(host.only), isFalse);

    await tester.pump();
    expect(_Host.hidden(host.only), isTrue);

    offstage.value = false;
    await tester.pump();
    expect(_Host.hidden(host.only), isFalse);
    expect(_Host.interactive(host.only), isTrue);
  });

  testWidgets('takes no touches under an IgnorePointer or when asked not to', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: IgnorePointer(child: view(key: const Key('ignored'))),
            ),
            SizedBox(height: 44, child: view(interactive: false)),
            SizedBox(height: 44, child: view()),
          ],
        ),
      ),
    );

    final byTop = host.views.values.toList()
      ..sort((a, b) => _Host.rectOf(a).top.compareTo(_Host.rectOf(b).top));
    expect(byTop.map(_Host.interactive), <bool>[false, false, true]);
  });

  testWidgets('orders the views as Flutter paints them', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, width: 50, height: 50, child: view()),
            Positioned(left: 0, top: 100, width: 50, height: 50, child: view()),
          ],
        ),
      ),
    );

    final byTop = host.views.values.toList()
      ..sort((a, b) => _Host.rectOf(a).top.compareTo(_Host.rectOf(b).top));
    expect(byTop[0][26], lessThan(byTop[1][26]));
  });

  testWidgets('hides under a color filter it cannot take', (tester) async {
    await tester.pumpWidget(
      placed(
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcATop),
          child: view(),
        ),
      ),
    );

    expect(_Host.hidden(host.only), isTrue);
  });

  testWidgets('disposes the native view with its widget', (tester) async {
    await tester.pumpWidget(placed(view()));
    await tester.pumpWidget(const SizedBox());

    expect(host.calls, contains('dispose'));
  });

  group('an occluder', () {
    setUp(() => AdaptiveNativeChrome.enabled = true);
    tearDown(() => AdaptiveNativeChrome.enabled = false);

    Widget scene({required double occluderTop, bool occluderFirst = false}) {
      final occluder = Positioned(
        left: 0,
        right: 0,
        top: occluderTop,
        height: 60,
        child: const NativeChromeOccluder(child: SizedBox.expand()),
      );
      final native = Positioned(
        left: 20,
        top: 40,
        width: 100,
        height: 44,
        child: view(),
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: occluderFirst ? [occluder, native] : [native, occluder],
        ),
      );
    }

    testWidgets('painted after a view and over it sends it away', (
      tester,
    ) async {
      await tester.pumpWidget(scene(occluderTop: 300));
      expect(_Host.hidden(host.only), isFalse);

      await tester.pumpWidget(scene(occluderTop: 30));
      await tester.pump();
      expect(_Host.hidden(host.only), isTrue);

      await tester.pumpWidget(scene(occluderTop: 300));
      expect(_Host.hidden(host.only), isFalse);
    });

    testWidgets('painted before a view leaves it alone', (tester) async {
      await tester.pumpWidget(scene(occluderTop: 30, occluderFirst: true));
      await tester.pump();
      expect(_Host.hidden(host.only), isFalse);
    });
  });

  testWidgets('frame locked, it sends a message for every frame and hides a '
      'view with the frame its stand-in comes in', (tester) async {
    host = _Host(frameLocked: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, host.handle);
    final offstage = ValueNotifier<bool>(false);
    addTearDown(offstage.dispose);
    await tester.pumpWidget(
      placed(
        ValueListenableBuilder<bool>(
          valueListenable: offstage,
          builder: (context, value, child) =>
              Opacity(opacity: value ? 0 : 1, child: child),
          child: view(),
        ),
      ),
    );
    await tester.pump();

    final layouts = host.layouts;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(host.layouts, layouts + 1);

    offstage.value = true;
    await tester.pump();
    expect(_Host.hidden(host.only), isTrue);
  });
}
