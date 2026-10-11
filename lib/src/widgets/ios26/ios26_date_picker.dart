import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// How [IOS26DatePicker] shows its dates.
enum IOS26DatePickerStyle {
  /// The calendar of iOS, which switches to month and year wheels from its
  /// header.
  inline,

  /// The wheels of iOS.
  wheels,
}

/// The system's date picker (`UIDatePicker`), as iOS 26 draws it. Where there
/// is no UIKit (other platforms, widget tests), a [CupertinoDatePicker] stands
/// in.
class IOS26DatePicker extends StatefulWidget {
  const IOS26DatePicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.mode = CupertinoDatePickerMode.date,
    this.style = IOS26DatePickerStyle.inline,
    this.tint,
    this.minuteInterval = 1,
    this.use24HourFormat = false,
  });

  final DateTime initialDate;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final CupertinoDatePickerMode mode;
  final IOS26DatePickerStyle style;

  /// The color of the selected day and of the controls.
  final Color? tint;
  final int minuteInterval;

  /// Only for the stand-in: the system follows the device's setting.
  final bool use24HourFormat;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26DatePicker> createState() => _IOS26DatePickerState();
}

class _IOS26DatePickerState extends State<IOS26DatePicker> {
  MethodChannel? _channel;

  /// The height the native picker needs at the width it has, once it said.
  double? _height;

  static bool get _hasUIKit =>
      IOS26DatePicker.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  String get _mode => switch (widget.mode) {
    CupertinoDatePickerMode.time => 'time',
    CupertinoDatePickerMode.dateAndTime => 'dateAndTime',
    CupertinoDatePickerMode.monthYear => 'yearAndMonth',
    _ => 'date',
  };

  void _onCreated(int id) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_date_picker_$id')
      ..setMethodCallHandler((call) async {
        final arguments = call.arguments as Map<Object?, Object?>?;
        switch (call.method) {
          case 'changed':
            final millis = (arguments?['date'] as num?)?.round();
            if (millis != null) {
              widget.onChanged(DateTime.fromMillisecondsSinceEpoch(millis));
            }
          case 'height':
            final height = (arguments?['height'] as num?)?.toDouble();
            if (mounted && height != null && height > 0 && height != _height) {
              setState(() => _height = height);
            }
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUIKit) {
      return SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          initialDateTime: widget.initialDate,
          minimumDate: widget.firstDate,
          maximumDate: widget.lastDate,
          mode: widget.mode,
          minuteInterval: widget.minuteInterval,
          use24hFormat: widget.use24HourFormat,
          onDateTimeChanged: widget.onChanged,
        ),
      );
    }
    final tint = widget.tint;
    final firstDate = widget.firstDate;
    final lastDate = widget.lastDate;
    return SizedBox(
      height:
          _height ?? (widget.style == IOS26DatePickerStyle.inline ? 360 : 216),
      child: UiKitView(
        viewType: 'adaptive_platform_ui/ios26_date_picker',
        creationParams: <String, Object>{
          'mode': _mode,
          'style': widget.style.name,
          'initial': widget.initialDate.millisecondsSinceEpoch,
          'minimum': ?firstDate?.millisecondsSinceEpoch,
          'maximum': ?lastDate?.millisecondsSinceEpoch,
          'tint': ?tint?.toARGB32(),
          'minuteInterval': widget.minuteInterval,
          'locale': ?Localizations.maybeLocaleOf(context)?.toLanguageTag(),
          'isDark':
              MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        // Its wheels and its calendar take every touch on them.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }
}
