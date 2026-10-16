import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const window = Size(669, 951);

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..physicalSize = const Size(1200, 1200)
      ..devicePixelRatio = 1;
  });

  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize(),
  );
  const padding = EdgeInsets.only(top: 84, bottom: 34);

  Widget host({
    required Widget child,
    List<DisplayFeature> features = const [],
    Rect? duoHinge,
    Size size = window,
    TextDirection textDirection = TextDirection.ltr,
  }) => Directionality(
    textDirection: textDirection,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
        displayFeatures: features,
      ),
      child: FoldScope(
        hinge: duoHinge,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  );

  const start = Key('start');
  const end = Key('end');

  Widget panes({bool withEnd = true, Axis direction = Axis.vertical}) =>
      AdaptiveTwoPane(
        direction: direction,
        start: const _Probe(key: start),
        end: withEnd ? const _Probe(key: end) : null,
      );

  DisplayFeature fold(Rect bounds, DisplayFeatureState state) => DisplayFeature(
    bounds: bounds,
    type: DisplayFeatureType.fold,
    state: state,
  );

  testWidgets('shares a window without a fold by the proportion', (
    tester,
  ) async {
    await tester.pumpWidget(host(child: panes()));

    expect(
      tester.getRect(find.byKey(start)),
      const Rect.fromLTWH(0, 0, 669, 475.5),
    );
    expect(
      tester.getRect(find.byKey(end)),
      const Rect.fromLTWH(0, 475.5, 669, 475.5),
    );
  });

  testWidgets('leaves the whole window to the start pane without an end', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        child: panes(withEnd: false),
        features: [
          fold(
            const Rect.fromLTWH(0, 400, 669, 0),
            DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
    );

    expect(tester.getRect(find.byKey(start)), Offset.zero & window);
    expect(_paddingOf(tester, start), padding);
  });

  testWidgets(
    'puts the start pane above an Android fold across the window and the end below',
    (tester) async {
      await tester.pumpWidget(
        host(
          child: panes(direction: Axis.horizontal),
          features: [
            fold(
              const Rect.fromLTWH(0, 420, 669, 20),
              DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
      );

      expect(
        tester.getRect(find.byKey(start)),
        const Rect.fromLTWH(0, 0, 669, 420),
      );
      expect(
        tester.getRect(find.byKey(end)),
        const Rect.fromLTWH(0, 440, 669, 511),
      );
      expect(_paddingOf(tester, start), const EdgeInsets.only(top: 84));
      expect(_paddingOf(tester, end), const EdgeInsets.only(bottom: 34));
    },
  );

  testWidgets('follows the iPhone Duo fold from the toolbar host', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(child: panes(), duoHinge: const Rect.fromLTWH(0, 476, 669, 0)),
    );

    expect(tester.getRect(find.byKey(start)).bottom, 476);
    expect(tester.getRect(find.byKey(end)).top, 476);
  });

  testWidgets('meets a fold down the window side by side', (tester) async {
    const size = Size(951, 669);
    await tester.pumpWidget(
      host(
        size: size,
        child: panes(),
        features: [
          fold(
            const Rect.fromLTWH(470, 0, 10, 669),
            DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
    );

    expect(
      tester.getRect(find.byKey(start)),
      const Rect.fromLTWH(0, 0, 470, 669),
    );
    expect(
      tester.getRect(find.byKey(end)),
      const Rect.fromLTWH(480, 0, 471, 669),
    );
  });

  testWidgets('puts the start pane on the right in a right-to-left layout', (
    tester,
  ) async {
    const size = Size(951, 669);
    await tester.pumpWidget(
      host(
        size: size,
        textDirection: TextDirection.rtl,
        child: const AdaptiveTwoPane(
          proportion: 0.6,
          start: _Probe(key: start),
          end: _Probe(key: end),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(start)).left, closeTo(951 * 0.4, 0.01));
    expect(tester.getRect(find.byKey(end)).width, closeTo(951 * 0.4, 0.01));
  });

  testWidgets('ignores a fold of a device that lies flat', (tester) async {
    await tester.pumpWidget(
      host(
        child: panes(direction: Axis.horizontal),
        features: [
          fold(
            const Rect.fromLTWH(0, 420, 669, 0),
            DisplayFeatureState.postureFlat,
          ),
        ],
      ),
    );

    expect(tester.getRect(find.byKey(start)).width, closeTo(334.5, 0.01));
  });

  testWidgets(
    'keeps the start pane\'s state as the device folds and the end comes',
    (tester) async {
      await tester.pumpWidget(host(child: panes(withEnd: false)));
      final state = tester.state(find.byKey(start));

      await tester.pumpWidget(
        host(
          child: panes(),
          features: [
            fold(
              const Rect.fromLTWH(0, 420, 669, 0),
              DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
      );

      expect(tester.state(find.byKey(start)), same(state));
      expect(
        AdaptiveTwoPane.hasFoldAcross(tester.element(find.byKey(start))),
        isTrue,
      );
    },
  );

  group('in a window of its own', () {
    const inner = Size(951, 669);

    /// [child] laid out at [at] in a window of [size], [width] wide.
    Widget placed({
      required Widget child,
      Rect? hinge,
      Rect? crease,
      List<DisplayFeature> features = const [],
      Size size = inner,
      double at = 0,
      double? width,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size, displayFeatures: features),
        child: FoldScope(
          hinge: hinge,
          crease: crease,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: at),
              child: SizedBox(
                width: width ?? size.width - at,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    Widget panes({bool followsCrease = false}) => AdaptiveTwoPane(
      followsCrease: followsCrease,
      start: const _Probe(key: start),
      end: const _Probe(key: end),
    );

    const flatDuo = Rect.fromLTWH(475, 0, 1, 669);

    testWidgets('followsCrease meets where the fold runs while an iPhone Duo '
        'lies flat; without it the panes share the window', (tester) async {
      await tester.pumpWidget(
        placed(child: panes(followsCrease: true), crease: flatDuo),
      );
      expect(
        tester.getRect(find.byKey(start)),
        const Rect.fromLTWH(0, 0, 475, 669),
      );
      expect(
        tester.getRect(find.byKey(end)),
        const Rect.fromLTWH(476, 0, 475, 669),
      );

      await tester.pumpWidget(placed(child: panes(), crease: flatDuo));
      expect(tester.getRect(find.byKey(start)).width, 951 / 2);
    });

    testWidgets('followsCrease meets an Android fold lying flat', (
      tester,
    ) async {
      await tester.pumpWidget(
        placed(
          size: window,
          child: panes(followsCrease: true),
          features: [
            fold(
              const Rect.fromLTWH(0, 420, 669, 0),
              DisplayFeatureState.postureFlat,
            ),
          ],
        ),
      );

      expect(
        tester.getRect(find.byKey(start)),
        const Rect.fromLTWH(0, 0, 669, 420),
      );
      expect(tester.getRect(find.byKey(end)).top, 420);
    });

    testWidgets('beside a list it meets the fold where it runs through it, '
        'from the window into its own coordinates', (tester) async {
      await tester.pumpWidget(placed(child: panes(), hinge: flatDuo, at: 362));
      // Where it is laid out is known once the frame is done.
      await tester.pump();

      expect(
        tester.getRect(find.byKey(start)),
        const Rect.fromLTWH(362, 0, 113, 669),
      );
      expect(
        tester.getRect(find.byKey(end)),
        const Rect.fromLTWH(476, 0, 475, 669),
      );
    });

    testWidgets('a fold beside it, not through it, leaves the panes to the '
        'proportion', (tester) async {
      await tester.pumpWidget(
        placed(child: panes(), hinge: flatDuo, width: 362),
      );
      await tester.pump();

      expect(tester.getRect(find.byKey(start)).width, 181);
      expect(tester.getRect(find.byKey(end)).width, 181);
    });
  });
}

EdgeInsets _paddingOf(WidgetTester tester, Key key) =>
    MediaQuery.paddingOf(tester.element(find.byKey(key)));

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
