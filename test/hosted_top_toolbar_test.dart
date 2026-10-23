import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'voice_over_fixture.dart';

/// Forces the chrome on (there is no iOS 26 in a widget test); the insets
/// stay those of an ordinary iPhone, so this is not the Duo pose.
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

Widget page(String title, {IconData? action, VoidCallback? onAction}) =>
    AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: title,
        useNativeToolbar: true,
        actions: [
          if (action != null)
            AdaptiveAppBarAction(icon: action, onPressed: onAction ?? () {}),
        ],
      ),
      body: Center(child: Text('body:$title')),
    );

Widget hostedApp({
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
  home: home,
);

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

Finder get bar => find.byType(HostedTopToolbar);
Finder inBar(Finder finder) => find.descendant(of: bar, matching: finder);

/// Opacity of the page layer (or shared back layer) [finder] is drawn in.
double opacityOf(WidgetTester tester, Finder finder) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: inBar(finder),
            // Layers are keyed; the buttons' own press feedback fades are not.
            matching: find.byWidgetPredicate(
              (w) => w is FadeTransition && w.key != null,
            ),
          )
          .first,
    )
    .opacity
    .value;

Finder get backButton => inBar(find.byType(AdaptiveButton));

void main() {
  group('HostedTopToolbar', () {
    testWidgets('back fills the toolbar height and is tappable near its edge', (
      tester,
    ) async {
      usePhone(tester);
      tester.view.display.size = tester.view.physicalSize;
      addTearDown(tester.view.display.resetSize);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Home')));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pumpAndSettle();

      final rect = tester.getRect(backButton);
      expect(rect.size, const Size(44, 44));
      expect(rect.topLeft, const Offset(16, 62));
      expect(rect.bottom, 62 + kHostedToolbarHeight);
      final button = tester.widget<AdaptiveButton>(backButton);
      expect(button.size, AdaptiveButtonSize.large);
      expect(button.useSmoothRectangleBorder, isFalse);

      // This point is above the old 38-point button's bounds.
      await tester.tapAt(rect.topCenter + const Offset(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('body:Detail'), findsNothing);
      expect(backButton, findsNothing);
    });

    testWidgets('one fixed bar at the top shows the page in front', (
      tester,
    ) async {
      usePhone(tester);
      final nav = GlobalKey<NavigatorState>();
      var added = 0;
      await tester.pumpWidget(
        hostedApp(
          navigatorKey: nav,
          home: page('Home', action: Icons.add, onAction: () => added++),
        ),
      );
      await tester.pump();

      expect(bar, findsOneWidget);
      expect(find.byType(HostedDuoBar), findsNothing);
      expect(inBar(find.text('Home')), findsOneWidget);
      expect(backButton, findsNothing);
      final rect = tester.getRect(
        find.descendant(of: bar, matching: find.byType(SizedBox)).first,
      );
      expect(rect.top, 0);
      expect(
        rect.height,
        kHostedToolbarHeight + kHostedToolbarBottomPadding + 62,
      );

      await tester.tap(inBar(find.byIcon(Icons.add)));
      expect(added, 1);

      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page('Detail', action: Icons.share),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mid-transition: the bar has not moved; it is handing over from the
      // outgoing page's items to the incoming page's.
      expect(
        tester.getRect(
          find.descendant(of: bar, matching: find.byType(SizedBox)).first,
        ),
        rect,
      );
      expect(opacityOf(tester, find.text('Home')), lessThan(1));
      expect(opacityOf(tester, find.text('Detail')), lessThan(1));
      await tester.pumpAndSettle();
      expect(inBar(find.text('Home')), findsNothing);
      expect(opacityOf(tester, find.text('Detail')), 1);

      // Back is performed on the owner's navigator.
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.text('body:Detail'), findsNothing);
      expect(inBar(find.text('Home')), findsOneWidget);
    });

    testWidgets('outgoing items leave before incoming ones arrive', (
      tester,
    ) async {
      usePhone(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Home')));
      await tester.pump();

      final route = PageRouteBuilder<void>(
        transitionDuration: const Duration(seconds: 4),
        reverseTransitionDuration: const Duration(seconds: 4),
        pageBuilder: (_, _, _) => page('Detail'),
      );
      nav.currentState!.push(route);
      await tester.pump();
      await tester.pump();

      // A quarter in: the old title is fading, the new one has not started.
      await tester.pump(const Duration(seconds: 1));
      expect(opacityOf(tester, find.text('Home')), inExclusiveRange(0, 1));
      expect(opacityOf(tester, find.text('Detail')), 0);

      // Three quarters in: the old one is gone, the new one is arriving.
      await tester.pump(const Duration(seconds: 2));
      expect(opacityOf(tester, find.text('Home')), 0);
      expect(opacityOf(tester, find.text('Detail')), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
    });

    testWidgets('a back button both pages show stays put', (tester) async {
      usePhone(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('A')));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('B')),
      );
      await tester.pumpAndSettle();
      final backRect = tester.getRect(backButton);

      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('C')),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(backButton, findsOneWidget);
      expect(opacityOf(tester, find.byType(AdaptiveButton)), 1);
      expect(tester.getRect(backButton), backRect);
      expect(opacityOf(tester, find.text('B')), lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a page shown like a dialog keeps its cross and travels with the page',
      (tester) async {
        usePhone(tester);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          hostedApp(navigatorKey: nav, home: page('Map')),
        );
        await tester.pump();
        nav.currentState!.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const AdaptiveScaffold(
              appBar: AdaptiveAppBar(
                title: 'Bikes',
                useNativeToolbar: true,
                backButtonStyle: AdaptiveBackButtonStyle.close,
              ),
              body: SizedBox.shrink(),
            ),
          ),
        );
        double titleTop() => tester.getTopLeft(inBar(find.text('Bikes'))).dy;
        String backSymbol() =>
            tester.widget<AdaptiveButton>(backButton).sfSymbol!.name;

        // It comes up with the page, as it is, rather than fading in place.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final rising = titleTop();
        expect(opacityOf(tester, find.text('Bikes')), 1);
        await tester.pumpAndSettle();
        final top = titleTop();
        expect(rising, greaterThan(top));
        expect(backSymbol(), 'xmark');

        // Closing it, it goes down with the page, its cross still a cross
        // while the page below owns the bar.
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(titleTop(), greaterThan(top));
        expect(opacityOf(tester, find.text('Bikes')), 1);
        expect(backSymbol(), 'xmark');
        await tester.pumpAndSettle();
        expect(backButton, findsNothing);
        expect(inBar(find.text('Map')), findsOneWidget);
      },
    );

    testWidgets('on iPhone Duo a closing dialog page keeps its cross', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(951, 669);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
      addTearDown(tester.view.reset);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Map')));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'Bikes',
              useNativeToolbar: true,
              backButtonStyle: AdaptiveBackButtonStyle.close,
            ),
            body: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Iterable<bool> crosses() => tester
          .widgetList<DuoBarBackButton>(find.byType(DuoBarBackButton))
          .map((button) => button.close);
      expect(crosses(), [true]);

      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(crosses(), [true]);
      await tester.pumpAndSettle();
      expect(crosses(), isEmpty);
    });

    testWidgets(
      'a back swipe reversed again and again keeps semantics intact',
      (tester) async {
        // A screen reader is on, so semantics nodes exist for the bar. Each
        // page layer is a FadeTransition; one that reaches zero opacity used
        // to drop its semantics and restore them when the swipe came back,
        // which tripped SemanticsNode._replaceChildren mid gesture.
        usePhone(tester);
        final semantics = tester.ensureSemantics();
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          hostedApp(
            navigatorKey: nav,
            home: page('Home', action: Icons.add),
          ),
        );
        await tester.pump();
        nav.currentState!.push(
          CupertinoPageRoute<void>(
            builder: (_) => page('Detail', action: Icons.share),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(4, 300));
        await gesture.moveBy(const Offset(40, 0));
        for (var i = 0; i < 4; i++) {
          // All the way across, so the leaving layer hits zero opacity, and
          // back to the start, a few times without lifting the finger.
          await gesture.moveBy(const Offset(360, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.moveBy(const Offset(-360, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: 'pass $i');
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('body:Detail'), findsOneWidget);

        // The hidden page's bar is not read out while it is hidden.
        expect(
          find.descendant(of: bar, matching: find.byIcon(Icons.add)),
          findsNothing,
        );
        semantics.dispose();
      },
    );

    testWidgets('pages are told the host draws their toolbar', (tester) async {
      usePhone(tester);
      ToolbarChromeScope? scope;
      await tester.pumpWidget(
        hostedApp(
          home: Builder(
            builder: (context) {
              scope = ToolbarChromeScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(scope?.hostsToolbar, isTrue);
      expect(scope?.hostsDuoControls, isFalse);
    });

    testWidgets('a title with a subtitle is drawn by Flutter and blended', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        hostedApp(
          home: const AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'Inbox',
              subtitle: '3 unread',
              useNativeToolbar: true,
            ),
            body: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      expect(inBar(find.text('3 unread')), findsOneWidget);
    });

    testWidgets('a page without a toolbar empties the bar', (tester) async {
      usePhone(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Home')));
      await tester.pump();

      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const AdaptiveScaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      expect(inBar(find.text('Home')), findsNothing);

      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(inBar(find.text('Home')), findsOneWidget);
    });

    testWidgets('a Flutter-drawn bar opens an action\'s menu', (tester) async {
      usePhone(tester);
      final selected = <String>[];
      await tester.pumpWidget(
        hostedApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'Game',
              useNativeToolbar: true,
              actions: [
                AdaptiveAppBarAction(
                  icon: Icons.more_horiz,
                  label: 'More',
                  menuItems: const [
                    AdaptivePopupMenuItem(label: 'Hide game'),
                    AdaptivePopupMenuItem(label: 'Report'),
                  ],
                  onMenuItemSelected: (_, item) => selected.add(item.label),
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(inBar(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(selected, ['Report']);
    });

    testWidgets('on iPhone Duo the top bar keeps the title only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(951, 669);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hostedApp(home: page('Home', action: Icons.add)));
      await tester.pump();

      expect(inBar(find.text('Home')), findsOneWidget);
      expect(inBar(find.byIcon(Icons.add)), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HostedDuoBar),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
    });
  });

  group('VoiceOver', () {
    // Off iOS, a platform view's focus node takes a focus action, which
    // VoiceOver would stop at.
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
    const toolbarType = 'adaptive_platform_ui/ios26_toolbar';
    final created = <(int, String)>[];

    setUp(() {
      created.clear();
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      IOS26Button.debugHasUIKitOverride = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, (
            call,
          ) async {
            if (call.method == 'create') {
              final args = call.arguments as Map<Object?, Object?>;
              created.add((args['id']! as int, args['viewType']! as String));
            }
            return null;
          });
    });

    tearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
      IOS26Button.debugHasUIKitOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });

    /// A pushed page with a native title and a native button, over a list
    /// that runs under the bar, as VoiceOver finds content scrolled under it.
    Future<void> pumpDetail(
      WidgetTester tester, {
      required VoidCallback onShare,
      String? backIdentifier,
    }) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Home')));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'Detail',
              useNativeToolbar: true,
              backButtonIdentifier: backIdentifier,
              actions: [
                AdaptiveAppBarAction(
                  iosSymbol: 'square.and.arrow.up',
                  label: 'Share',
                  onPressed: onShare,
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder nativeToolbar() => find.byWidgetPredicate(
      (widget) => widget is UiKitView && widget.viewType == toolbarType,
    );

    /// The native bar tells where its items are, in its view.
    Future<void> tellItemFrames(
      WidgetTester tester, {
      required List<Rect?> actions,
      Rect? title,
    }) async {
      Object? encode(Rect? frame) => frame == null
          ? null
          : {
              'x': frame.left,
              'y': frame.top,
              'width': frame.width,
              'height': frame.height,
            };
      final id = created.lastWhere((view) => view.$2 == toolbarType).$1;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        '${toolbarType}_$id',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('itemFramesChanged', {
            'actions': [for (final frame in actions) encode(frame)],
            'leading': null,
            'title': encode(title),
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    /// A labelled list under the whole screen, over everything but the bars.
    Widget listUnderBars(Widget child) => Stack(
      children: [
        Semantics(
          container: true,
          label: 'List',
          child: const SizedBox.expand(),
        ),
        child,
      ],
    );

    testWidgets('finds the native bar\'s button, title and back button over '
        'what is under the bar', (tester) async {
      usePhone(tester);
      final semantics = tester.ensureSemantics();
      var shares = 0;
      await pumpDetail(tester, onShare: () => shares++);
      // Laid over the page, under the host's bars, as a list scrolled under
      // them is.
      final navigatorState = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigatorState.overlay!.insert(
        OverlayEntry(builder: (_) => listUnderBars(const SizedBox.shrink())),
      );
      await tester.pump();

      const share = Rect.fromLTWH(342, 62, 44, 44);
      const title = Rect.fromLTWH(170, 73, 62, 22);
      await tellItemFrames(tester, actions: [share], title: title);
      final origin = tester.getTopLeft(nativeToolbar());

      expect(voiceOverHit(tester, share.shift(origin).center)?.label, 'Share');
      final header = voiceOverHit(tester, title.shift(origin).center)!;
      expect(header.label, 'Detail');
      expect(header.getSemanticsData().flagsCollection.isHeader, isTrue);
      expect(voiceOverHit(tester, tester.getCenter(backButton))?.label, 'Back');

      tester.semantics.tap(find.semantics.byLabel('Share'));
      expect(shares, 1);
      tester.semantics.tap(find.semantics.byLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsNothing);
      semantics.dispose();
    }, variant: ios);

    testWidgets('the back button has the page\'s identifier on its node, for '
        'UI tests', (tester) async {
      usePhone(tester);
      final semantics = tester.ensureSemantics();
      await pumpDetail(tester, onShare: () {}, backIdentifier: 'back_button');

      final back = find.semantics.byLabel('Back').evaluate().single;
      expect(back.getSemanticsData().identifier, 'back_button');
      semantics.dispose();
    }, variant: ios);

    testWidgets('until the native bar tells where they are, its buttons are '
        'where it lays them out', (tester) async {
      usePhone(tester);
      final semantics = tester.ensureSemantics();
      await pumpDetail(tester, onShare: () {});
      final origin = tester.getTopLeft(nativeToolbar());
      final width = tester.getSize(nativeToolbar()).width;

      final share = find.semantics.byLabel('Share').evaluate().single;
      expect(
        globalRectOf(tester, share),
        Rect.fromLTWH(width - 16 - 44, 62, 44, 44).shift(origin),
      );
      semantics.dispose();
    }, variant: ios);
  });
}
