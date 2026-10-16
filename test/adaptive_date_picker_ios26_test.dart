import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The native date pickers created: their ids and creation parameters.
  final created = <(int, Map<Object?, Object?>)>[];

  setUp(() {
    created.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method != 'create') return null;
          final args = call.arguments as Map<Object?, Object?>;
          if (args['viewType'] == 'adaptive_platform_ui/ios26_date_picker') {
            final params = args['params']! as Uint8List;
            created.add((
              args['id']! as int,
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(params),
                  )
                  as Map<Object?, Object?>,
            ));
          }
          return null;
        });
  });

  tearDown(() {
    IOS26DatePicker.debugHasUIKitOverride = null;
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  /// Sends [method] from the native picker with [id] to Flutter.
  Future<void> fromNative(int id, String method, Object arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'adaptive_platform_ui/ios26_date_picker_$id',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  testWidgets('the native picker gets its dates, tint and language, and '
      'reports the date picked and the height it needs', (tester) async {
    IOS26DatePicker.debugHasUIKitOverride = true;
    final picked = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Localizations(
          locale: const Locale('nl', 'BE'),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Center(
            child: IOS26DatePicker(
              initialDate: DateTime(1990, 5, 17),
              firstDate: DateTime(1900),
              lastDate: DateTime(2010, 12, 31),
              tint: const Color(0xFF009DD6),
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final (id, params) = created.single;
    expect(params['mode'], 'date');
    expect(params['style'], 'inline');
    expect(params['initial'], DateTime(1990, 5, 17).millisecondsSinceEpoch);
    expect(params['minimum'], DateTime(1900).millisecondsSinceEpoch);
    expect(params['maximum'], DateTime(2010, 12, 31).millisecondsSinceEpoch);
    expect(params['tint'], 0xFF009DD6);
    expect(params['locale'], 'nl-BE');

    await fromNative(id, 'changed', {
      'date': DateTime(1991, 2, 3).millisecondsSinceEpoch.toDouble(),
    });
    expect(picked, [DateTime(1991, 2, 3)]);

    await fromNative(id, 'height', {'height': 331.0});
    await tester.pump();
    expect(tester.getSize(find.byType(IOS26DatePicker)).height, 331);
  });

  group('on iOS 26', () {
    setUp(() {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
    });

    Future<Future<DateTime?>> open(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      final result = AdaptiveDatePicker.show(
        context: context,
        initialDate: DateTime(1990, 5, 17, 10, 30),
        firstDate: DateTime(1900),
        lastDate: DateTime(2010),
        title: 'Birthday',
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows the picker in a sheet on glass, with a title', (
      tester,
    ) async {
      final result = open(tester);
      await result;

      expect(find.byType(IOS26DatePicker), findsOneWidget);
      expect(find.text('Birthday'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(IOS26DatePicker),
          matching: find.byType(IOS26GlassSurface),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the checkmark confirms the day shown, without its time', (
      tester,
    ) async {
      final result = await open(tester);

      await tester.tap(find.bySemanticsLabel('OK'));
      await tester.pumpAndSettle();

      expect(await result, DateTime(1990, 5, 17));
    });

    testWidgets('on the month and year wheels, the checkmark goes back to '
        'the days first; on the days it confirms', (tester) async {
      IOS26DatePicker.debugHasUIKitOverride = true;
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      final (id, _) = created.single;
      var wheels = true;
      final asked = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel('adaptive_platform_ui/ios26_date_picker_$id'),
            (call) async {
              asked.add(call.method);
              final shown = wheels;
              wheels = false;
              return shown;
            },
          );

      await tester.tap(find.bySemanticsLabel('OK'));
      await tester.pumpAndSettle();
      expect(asked, ['showDays']);
      expect(done, isFalse);
      expect(find.byType(IOS26DatePicker), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('OK'));
      await tester.pumpAndSettle();
      expect(await result, DateTime(1990, 5, 17));
    });

    testWidgets('a picker taller than the screen gets the room there is, '
        'below the status bar', (tester) async {
      IOS26DatePicker.debugHasUIKitOverride = true;
      tester.view.padding = const FakeViewPadding(top: 150);
      tester.view.viewPadding = const FakeViewPadding(top: 150);
      addTearDown(tester.view.reset);
      await open(tester);
      final (id, _) = created.single;

      // The largest text sizes on a small display.
      await fromNative(id, 'height', {'height': 2000.0});
      await tester.pump();

      expect(tester.takeException(), isNull);
      final sheet = tester.getRect(find.byType(IOS26GlassSurface));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        sheet.top,
        greaterThanOrEqualTo(150 / tester.view.devicePixelRatio),
      );
      expect(sheet.bottom, lessThanOrEqualTo(screen.height));
      expect(
        tester.getSize(find.byType(IOS26DatePicker)).height,
        lessThan(2000),
      );
    });

    testWidgets('the close button keeps one colour, also while the sheet '
        'leaves', (tester) async {
      await open(tester);

      final close = tester.widget<AdaptiveButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdaptiveButton && widget.sfSymbol?.name == 'xmark',
        ),
      );
      expect(close.sfSymbol?.color, isNotNull);
    });

    testWidgets('the close button picks nothing', (tester) async {
      final result = await open(tester);

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });
  });
}
