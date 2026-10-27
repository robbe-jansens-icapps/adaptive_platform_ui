import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/platform_info.dart';
import 'adaptive_time_picker.dart';
import 'ios26/ios26_date_picker.dart';
import 'minute_interval.dart';

/// An adaptive date picker that renders platform-specific styles
///
/// On iOS 26+: Shows the system's date picker (its calendar by default) in a
/// native sheet floating on Liquid Glass, with a close button and a checkmark
/// that confirms, as iOS 26 sheets do. UIKit presents it over the Flutter
/// view: it slides up with the picker drawn, and the page under it stays as
/// it is, dimmed
/// On older iOS: Shows CupertinoDatePicker in a modal bottom sheet
/// On Android: Shows Material DatePickerDialog
class AdaptiveDatePicker {
  AdaptiveDatePicker._();

  static const MethodChannel _sheet = MethodChannel(
    'adaptive_platform_ui/date_picker_sheet',
  );

  /// Shows a platform-adaptive date picker
  ///
  /// Returns the selected [DateTime] or null if cancelled
  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    CupertinoDatePickerMode mode = CupertinoDatePickerMode.date,
    DatePickerMode initialDatePickerMode = DatePickerMode.day,
    bool use24HourFormat = false,
    int minuteInterval = 1,
    String? title,
    Color? tintColor,
    IOS26DatePickerStyle iosStyle = IOS26DatePickerStyle.inline,
  }) async {
    final effectiveFirstDate = firstDate ?? DateTime(1900);
    final effectiveLastDate = lastDate ?? DateTime(2100);

    if (PlatformInfo.isIOS26OrHigher()) {
      return _showNativeSheet(
        context: context,
        initialDate: initialDate,
        firstDate: effectiveFirstDate,
        lastDate: effectiveLastDate,
        mode: mode,
        style: iosStyle,
        title: title,
        tint: tintColor,
        minuteInterval: minuteInterval,
        use24HourFormat: use24HourFormat,
      );
    }

    if (PlatformInfo.isIOS) {
      return _showCupertinoDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: effectiveFirstDate,
        lastDate: effectiveLastDate,
        mode: mode,
        use24HourFormat: use24HourFormat,
        minuteInterval: minuteInterval,
      );
    }

    return _showMaterialDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: effectiveFirstDate,
      lastDate: effectiveLastDate,
      mode: mode,
      use24HourFormat: use24HourFormat,
      initialDatePickerMode: initialDatePickerMode,
      minuteInterval: minuteInterval,
    );
  }

  /// The system's date picker in a sheet that UIKit presents over the Flutter
  /// view, rather than in a Flutter route: UIKit makes the picker before the
  /// sheet moves and slides it up on its own, so it keeps every frame while
  /// the main thread, which Dart shares, is busy making the picker; and no
  /// route covers the page, whose bar keeps its backdrop. Where no sheet can
  /// be presented, the Cupertino picker comes up instead.
  static Future<DateTime?> _showNativeSheet({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required CupertinoDatePickerMode mode,
    required IOS26DatePickerStyle style,
    required String? title,
    required Color? tint,
    required int minuteInterval,
    required bool use24HourFormat,
  }) async {
    final localizations = MaterialLocalizations.of(context);
    final arguments = <String, Object>{
      'mode': switch (mode) {
        CupertinoDatePickerMode.time => 'time',
        CupertinoDatePickerMode.dateAndTime => 'dateAndTime',
        CupertinoDatePickerMode.monthYear => 'yearAndMonth',
        _ => 'date',
      },
      'style': style.name,
      // The picker only offers dates on the interval's grid.
      'initial': alignDateTimeToInterval(
        initialDate,
        minuteInterval,
      ).millisecondsSinceEpoch,
      'minimum': firstDate.millisecondsSinceEpoch,
      'maximum': lastDate.millisecondsSinceEpoch,
      'tint': (tint ?? CupertinoTheme.of(context).primaryColor).toARGB32(),
      'minuteInterval': minuteInterval,
      'locale': ?Localizations.maybeLocaleOf(context)?.toLanguageTag(),
      'isDark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'title': ?title,
      'closeLabel': localizations.closeButtonTooltip,
      'confirmLabel': localizations.okButtonLabel,
      // How much room the picker keeps from the sheet's round bottom corners.
      'displayCornerRadius': PlatformInfo.displayCornerRadius,
    };
    // A route pushed over the page took the focus from a text field there,
    // and the keyboard with it; a sheet of UIKit's does neither. The
    // keyboard is told to go a moment after the focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    try {
      final picked = await _sheet.invokeMethod<num>('show', arguments);
      if (picked == null) return null;
      return _asMode(mode, DateTime.fromMillisecondsSinceEpoch(picked.round()));
    } on MissingPluginException {
      // No sheet: below.
    } on PlatformException {
      // No sheet: below.
    }
    if (!context.mounted) return null;
    final picked = await _showCupertinoDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      mode: mode,
      use24HourFormat: use24HourFormat,
      minuteInterval: minuteInterval,
    );
    return picked == null ? null : _asMode(mode, picked);
  }

  /// [date] without what [mode] does not pick: a date has no time of day,
  /// a month no day.
  static DateTime _asMode(CupertinoDatePickerMode mode, DateTime date) =>
      switch (mode) {
        CupertinoDatePickerMode.date => DateTime(
          date.year,
          date.month,
          date.day,
        ),
        CupertinoDatePickerMode.monthYear => DateTime(date.year, date.month),
        _ => date,
      };

  static Future<DateTime?> _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required CupertinoDatePickerMode mode,
    required bool use24HourFormat,
    required int minuteInterval,
  }) async {
    // CupertinoDatePicker asserts the initial value already sits on the grid.
    final alignedInitial = alignDateTimeToInterval(initialDate, minuteInterval);
    DateTime selectedDate = alignedInitial;

    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return _CupertinoDatePickerContent(
          initialDate: alignedInitial,
          firstDate: firstDate,
          lastDate: lastDate,
          mode: mode,
          use24HourFormat: use24HourFormat,
          minuteInterval: minuteInterval,
          onDateSelected: (date) => selectedDate = date,
        );
      },
    ).then((result) => result != null ? selectedDate : null);
  }

  static Future<DateTime?> _showMaterialDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required CupertinoDatePickerMode mode,
    required bool use24HourFormat,
    required DatePickerMode initialDatePickerMode,
    required int minuteInterval,
  }) async {
    DateTime date = initialDate;
    if (mode != CupertinoDatePickerMode.time) {
      // Material has no native month-year picker; force year-only entry and
      // normalize to the 1st so callers still get a usable DateTime.
      final isMonthYear = mode == CupertinoDatePickerMode.monthYear;
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        initialDatePickerMode: isMonthYear
            ? DatePickerMode.year
            : initialDatePickerMode,
      );
      if (picked == null) return null;
      date = isMonthYear ? DateTime(picked.year, picked.month, 1) : picked;
    }
    if (mode == CupertinoDatePickerMode.date ||
        mode == CupertinoDatePickerMode.monthYear) {
      return DateTime(date.year, date.month, date.day);
    }
    if (!context.mounted) return null;
    final time = await AdaptiveTimePicker.show(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      use24HourFormat: use24HourFormat,
      minuteInterval: minuteInterval,
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

/// Internal widget that properly updates when theme changes
class _CupertinoDatePickerContent extends StatefulWidget {
  const _CupertinoDatePickerContent({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.mode,
    required this.use24HourFormat,
    required this.minuteInterval,
    required this.onDateSelected,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final CupertinoDatePickerMode mode;
  final bool use24HourFormat;
  final int minuteInterval;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<_CupertinoDatePickerContent> createState() =>
      _CupertinoDatePickerContentState();
}

class _CupertinoDatePickerContentState
    extends State<_CupertinoDatePickerContent> {
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    // Use CupertinoTheme to get dynamic colors that update with theme changes
    final backgroundColor = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final separatorColor = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );

    return Container(
      height: 280,
      color: backgroundColor,
      child: Column(
        children: [
          // Header with Done button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: separatorColor, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    PlatformInfo.isIOS
                        ? CupertinoLocalizations.of(context).cancelButtonLabel
                        : MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).pop(selectedDate),
                  child: Text(
                    MaterialLocalizations.of(context).okButtonLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // Date picker
          Expanded(
            child: CupertinoDatePicker(
              mode: widget.mode,
              use24hFormat: widget.use24HourFormat,
              minuteInterval: widget.minuteInterval,
              initialDateTime: widget.initialDate,
              minimumDate: widget.firstDate,
              maximumDate: widget.lastDate,
              onDateTimeChanged: (DateTime newDate) {
                setState(() {
                  selectedDate = newDate;
                });
                widget.onDateSelected(newDate);
              },
            ),
          ),
        ],
      ),
    );
  }
}
