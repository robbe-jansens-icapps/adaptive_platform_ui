import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_view.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const surfaceType = 'adaptive_platform_ui/ios26_glass_surface';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The views made over the Flutter view by type, what the glass was given
  /// of its content, and what each view was last told.
  final made = <int, String>{};
  final contents = <int, List<double>>{};
  final layouts = <int, List<double>>{};

  setUp(() {
    made.clear();
    contents.clear();
    layouts.clear();
    AdaptiveNativeChrome.enabled = true;
    IOS26GlassSurface.debugHasUIKitOverride = true;
    NativeChromeCoordinator.instance.debugReset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeChromeCoordinator.channel, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        made[id] = args['viewType']! as String;
        messenger.setMockMethodCallHandler(
          MethodChannel('${surfaceType}_$id'),
          (call) async {
            if (call.method == 'setContent') {
              final args = call.arguments as Map<Object?, Object?>;
              expect((args['bytes']! as Uint8List), isNotEmpty);
              (contents[id] ??= []).add(args['scale']! as double);
            }
            return null;
          },
        );
      } else if (call.method == 'layout') {
        final values = call.arguments as Float64List;
        for (
          var i = 0;
          i < values.length;
          i += NativeChromeCoordinator.stride
        ) {
          layouts[values[i].toInt()] = values.sublist(
            i,
            i + NativeChromeCoordinator.stride,
          );
        }
      }
      return null;
    });
  });

  tearDown(() {
    AdaptiveNativeChrome.enabled = false;
    IOS26GlassSurface.debugHasUIKitOverride = null;
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
  });

  int surface() => made.entries.singleWhere((e) => e.value == surfaceType).key;
  bool hidden(int id) =>
      layouts[id]![27].toInt() & NativeChromeCoordinator.hiddenFlag != 0;
  bool contentInSight(WidgetTester tester) =>
      tester.widget<NativeOutOfSight>(find.byType(NativeOutOfSight)).visible;

  /// Lets the image of the content be taken and handed over.
  Future<void> takeImages(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('iOS draws the glass and an image of the content, which Flutter '
      'keeps out of sight and which still takes the touches', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: IOS26GlassSurface(
              cornerRadius: 24,
              chrome: true,
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
    await tester.pump();
    final id = surface();
    expect(find.byType(UiKitView), findsNothing);
    // Until iOS has the image, Flutter draws the content, on the stand-in.
    expect(contentInSight(tester), isTrue);
    expect(hidden(id), isTrue);

    await takeImages(tester);
    expect(contents[id], [tester.view.devicePixelRatio]);
    await tester.pump();
    expect(contentInSight(tester), isFalse);
    expect(hidden(id), isFalse);
    expect(layouts[id]![19], 1.0);
    expect(
      layouts[id]![27].toInt() & NativeChromeCoordinator.interactiveFlag,
      0,
    );
    expect(
      find.descendant(
        of: find.byType(IOS26GlassSurface),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );

    await tester.tap(find.text('content'));
    expect(taps, 1);
  });

  testWidgets('a change to the content sends a new image', (tester) async {
    Widget surface(String text) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: IOS26GlassSurface(chrome: true, child: Text(text)),
        ),
      ),
    );
    await tester.pumpWidget(surface('one'));
    await takeImages(tester);
    final id = made.keys.single;
    expect(contents[id], hasLength(1));

    await tester.pumpWidget(surface('two'));
    await takeImages(tester);
    expect(contents[id], hasLength(2));
    // The glass stays on screen meanwhile.
    expect(contentInSight(tester), isFalse);
    expect(hidden(id), isFalse);
  });

  testWidgets('without native chrome it is a platform view', (tester) async {
    AdaptiveNativeChrome.enabled = false;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: IOS26GlassSurface(chrome: true, child: Text('content')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(made, isEmpty);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byType(NativeOutOfSight), findsNothing);
  });

  testWidgets('a toast is drawn by iOS above the native views of the bars, '
      'which stay on screen under it', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AdaptiveToastLayer(child: child!),
        home: const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 40),
            child: SizedBox(
              width: 300,
              height: 44,
              child: NativeChromeView(
                viewType: 'adaptive_platform_ui/ios26_toolbar',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final bar = made.keys.single;

    AdaptiveToast.show(
      navigator.currentContext!,
      builder: (dismiss) =>
          const Padding(padding: EdgeInsets.all(16), child: Text('Saved')),
    );
    await tester.pump();
    await takeImages(tester);
    await tester.pump(const Duration(milliseconds: 600));

    final toast = surface();
    expect(find.byType(UiKitView), findsNothing);
    expect(contents[toast], isNotEmpty);
    expect(hidden(toast), isFalse);
    expect(hidden(bar), isFalse);
    expect(layouts[bar]![20], 0, reason: 'nothing cuts into the bar');
    expect(layouts[toast]![26], greaterThan(layouts[bar]![26]));

    AdaptiveToast.clear();
    await tester.pumpAndSettle();
  });
}
