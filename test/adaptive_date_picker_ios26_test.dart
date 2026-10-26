import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
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
    const sheet = MethodChannel('adaptive_platform_ui/date_picker_sheet');

    /// The calls to the native sheet, which answer with [answer].
    final shown = <Map<Object?, Object?>>[];
    late Future<Object?> Function(MethodCall call) answer;

    setUp(() {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      shown.clear();
      answer = (_) async => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sheet, (call) {
            shown.add(call.arguments as Map<Object?, Object?>);
            return answer(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sheet, null);
    });

    /// Opens the picker on a page of its own; returns what it picks.
    Future<Future<DateTime?>> open(
      WidgetTester tester, {
      CupertinoDatePickerMode mode = CupertinoDatePickerMode.date,
      int minuteInterval = 1,
      String? title,
      Locale? locale,
    }) async {
      late BuildContext context;
      final Widget page = Builder(
        builder: (c) {
          context = c;
          return const SizedBox.expand();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: locale == null
              ? page
              : Localizations(
                  locale: locale,
                  delegates: const [
                    DefaultWidgetsLocalizations.delegate,
                    DefaultMaterialLocalizations.delegate,
                  ],
                  child: page,
                ),
        ),
      );
      final result = AdaptiveDatePicker.show(
        context: context,
        initialDate: DateTime(1990, 5, 17, 10, 38),
        firstDate: DateTime(1900),
        lastDate: DateTime(2010),
        mode: mode,
        minuteInterval: minuteInterval,
        title: title,
        tintColor: const Color(0xFF009DD6),
      );
      // The sheet is asked for once the keyboard has been told to go.
      await tester.pump(Duration.zero);
      return result;
    }

    testWidgets('the native sheet gets the dates, tint, language, title and '
        'button labels, the first date on the minute interval', (tester) async {
      await open(
        tester,
        mode: CupertinoDatePickerMode.dateAndTime,
        minuteInterval: 15,
        title: 'Birthday',
        locale: const Locale('en', 'GB'),
      );

      final arguments = shown.single;
      expect(arguments['mode'], 'dateAndTime');
      expect(arguments['style'], 'inline');
      expect(
        arguments['initial'],
        DateTime(1990, 5, 17, 10, 45).millisecondsSinceEpoch,
      );
      expect(arguments['minimum'], DateTime(1900).millisecondsSinceEpoch);
      expect(arguments['maximum'], DateTime(2010).millisecondsSinceEpoch);
      expect(arguments['minuteInterval'], 15);
      expect(arguments['tint'], 0xFF009DD6);
      expect(arguments['locale'], 'en-GB');
      expect(arguments['title'], 'Birthday');
      expect(arguments['closeLabel'], 'Close');
      expect(arguments['confirmLabel'], 'OK');
      expect(arguments['isDark'], isFalse);
      expect(arguments['rtl'], isFalse);
    });

    testWidgets('the date picked comes back as the mode has it', (
      tester,
    ) async {
      final picked = DateTime(1991, 2, 3, 14, 45);
      answer = (_) async => picked.millisecondsSinceEpoch.toDouble();
      final expected = {
        CupertinoDatePickerMode.date: DateTime(1991, 2, 3),
        CupertinoDatePickerMode.monthYear: DateTime(1991, 2),
        CupertinoDatePickerMode.time: picked,
        CupertinoDatePickerMode.dateAndTime: picked,
      };
      for (final MapEntry(key: mode, value: date) in expected.entries) {
        final result = await open(tester, mode: mode);
        expect(await result, date, reason: '$mode');
      }
      expect(shown.map((arguments) => arguments['mode']), [
        'date',
        'yearAndMonth',
        'time',
        'dateAndTime',
      ]);
    });

    testWidgets('a sheet closed without a date picks nothing', (tester) async {
      final result = await open(tester);
      expect(await result, isNull);
    });

    testWidgets('the page under the sheet stays in front', (tester) async {
      final picked = Completer<Object?>();
      answer = (_) => picked.future;
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (c) {
              context = c;
              return const Text('Form');
            },
          ),
        ),
      );
      final result = AdaptiveDatePicker.show(
        context: context,
        initialDate: DateTime(1990, 5, 17),
      );
      await tester.pumpAndSettle();

      expect(shown, hasLength(1));
      // Nothing came over it, so its bar keeps its backdrop.
      expect(ModalRoute.of(context)!.isCurrent, isTrue);
      expect(navigator.currentState!.canPop(), isFalse);

      picked.complete(DateTime(1991, 2, 3).millisecondsSinceEpoch.toDouble());
      expect(await result, DateTime(1991, 2, 3));
    });

    testWidgets('a text field gives up the keyboard before the sheet comes '
        'up', (tester) async {
      var keyboardUp = true;
      answer = (_) async {
        keyboardUp = tester.testTextInput.isVisible;
        return null;
      };
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const TextField(autofocus: true);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      final result = AdaptiveDatePicker.show(
        context: context,
        initialDate: DateTime(1990, 5, 17),
      );
      await tester.pump(Duration.zero);
      await result;

      expect(shown, hasLength(1));
      expect(keyboardUp, isFalse);
    });

    testWidgets('without a native sheet, the Cupertino picker comes up', (
      tester,
    ) async {
      answer = (_) async => throw MissingPluginException();
      final result = await open(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await result, DateTime(1990, 5, 17));
    });

    testWidgets('with nothing to present the native sheet from, the '
        'Cupertino picker comes up', (tester) async {
      answer = (_) async => throw PlatformException(code: 'unavailable');
      final result = await open(tester);
      await tester.pumpAndSettle();

      expect(shown, hasLength(1));
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}
