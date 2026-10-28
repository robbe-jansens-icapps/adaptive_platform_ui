import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const controlType = 'adaptive_platform_ui/ios26_glass_control';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The controls made over the Flutter view, and what each was last told.
  final made = <int>[];
  final updates = <int, Map<Object?, Object?>>{};
  final images = <int, List<String>>{};
  final layouts = <int, List<double>>{};

  setUp(() {
    made.clear();
    updates.clear();
    images.clear();
    layouts.clear();
    AdaptiveNativeChrome.enabled = true;
    IOS26GlassControl.debugHasUIKitOverride = true;
    NativeChromeCoordinator.instance.debugReset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeChromeCoordinator.channel, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        if (args['viewType'] == controlType) {
          final id = args['id']! as int;
          made.add(id);
          messenger.setMockMethodCallHandler(
            MethodChannel('${controlType}_$id'),
            (call) async {
              final args = call.arguments as Map<Object?, Object?>;
              if (call.method == 'update') updates[id] = args;
              if (call.method == 'setImage') {
                (images[id] ??= []).add(args['slot']! as String);
              }
              return null;
            },
          );
        }
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
    IOS26GlassControl.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
  });

  Future<void> tapNative(WidgetTester tester, String method) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        '${controlType}_${made.single}',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );

  Widget app(Widget control, {GlobalKey<NavigatorState>? navigator}) =>
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(height: 44, child: control),
          ),
        ),
      );

  testWidgets('iOS draws the glass, the label and the icons where Flutter '
      'lays them out, and taps on it reach the callbacks', (tester) async {
    var pressed = 0;
    var cleared = 0;
    await tester.pumpWidget(
      app(
        IOS26GlassControl(
          onPressed: () => pressed++,
          leading: const SizedBox.square(dimension: 20),
          label: 'Search',
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF112233),
          ),
          trailing: const SizedBox.square(dimension: 16),
          onTrailingPressed: () => cleared++,
          tint: const Color(0x80FF0000),
        ),
      ),
    );
    await tester.pump();

    expect(made, hasLength(1));
    final update = updates[made.single]!;
    expect(update['label'], 'Search');
    expect(update['fontSize'], 16);
    expect(update['fontWeight'], 600);
    expect(update['labelColor'], 0xFF112233);
    expect(update['tint'], 0x80FF0000);
    expect(update['interactive'], isTrue);
    final leading = update['leading']! as List<Object?>;
    final label = update['labelFrame']! as List<Object?>;
    final trailing = update['trailing']! as List<Object?>;
    // In a row: 16 in, the icon, 10 room, the label, 8 room, the icon.
    expect(leading.take(3), [16, 12, 20]);
    expect(label[0], 46);
    expect(trailing[0], (label[0]! as double) + (label[2]! as double) + 8);
    // The images of the icons are taken once the frame is drawn.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(images[made.single], containsAll(['leading', 'trailing']));
    // Flutter draws none of it.
    expect(
      layouts[made.single]![27].toInt() & NativeChromeCoordinator.hiddenFlag,
      0,
    );

    await tapNative(tester, 'pressed');
    await tapNative(tester, 'trailingPressed');
    expect((pressed, cleared), (1, 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('under a dialog Flutter draws it, on the glass stand-in, and '
      'iOS takes it off the screen', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      app(
        IOS26GlassControl(onPressed: () {}, label: 'City bike'),
        navigator: navigator,
      ),
    );
    await tester.pump();
    final id = made.single;
    expect(layouts[id]![27].toInt() & NativeChromeCoordinator.hiddenFlag, 0);

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const Center(child: Text('Sure?')),
    );
    await tester.pumpAndSettle();
    expect(
      layouts[id]![27].toInt() & NativeChromeCoordinator.hiddenFlag,
      NativeChromeCoordinator.hiddenFlag,
    );
    expect(find.byType(DecoratedBox), findsWidgets);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(layouts[id]![27].toInt() & NativeChromeCoordinator.hiddenFlag, 0);
    expect(made, hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('without native chrome it is a row on a glass surface', (
    tester,
  ) async {
    AdaptiveNativeChrome.enabled = false;
    var pressed = 0;
    await tester.pumpWidget(
      app(IOS26GlassControl(onPressed: () => pressed++, label: 'E-bike')),
    );

    expect(made, isEmpty);
    expect(find.byType(IOS26GlassSurface), findsOneWidget);
    await tester.tap(find.text('E-bike'));
    expect(pressed, 1);
  });
}
