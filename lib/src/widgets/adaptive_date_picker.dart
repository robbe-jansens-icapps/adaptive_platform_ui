import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import '../style/sf_symbol.dart';
import 'adaptive_button.dart';
import 'adaptive_time_picker.dart';
import 'ios26/ios26_date_picker.dart';
import 'ios26/ios26_glass_surface.dart';
import 'minute_interval.dart';

/// An adaptive date picker that renders platform-specific styles
///
/// On iOS 26+: Shows the system's date picker (its calendar by default) in a
/// sheet floating on Liquid Glass, with a close button and a checkmark that
/// confirms, as iOS 26 sheets do
/// On older iOS: Shows CupertinoDatePicker in a modal bottom sheet
/// On Android: Shows Material DatePickerDialog
class AdaptiveDatePicker {
  AdaptiveDatePicker._();

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
      return showCupertinoModalPopup<DateTime>(
        context: context,
        builder: (context) => _IOS26DatePickerSheet(
          initialDate: initialDate,
          firstDate: effectiveFirstDate,
          lastDate: effectiveLastDate,
          mode: mode,
          style: iosStyle,
          title: title,
          tint: tintColor,
          minuteInterval: minuteInterval,
          use24HourFormat: use24HourFormat,
        ),
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
        initialDatePickerMode:
            isMonthYear ? DatePickerMode.year : initialDatePickerMode,
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

/// The date picker of iOS 26 in a sheet floating 8 points from the edges on
/// Liquid Glass, its corners concentric with the display's: a close button on
/// one side, a checkmark that confirms on the other.
class _IOS26DatePickerSheet extends StatefulWidget {
  const _IOS26DatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.mode,
    required this.style,
    required this.title,
    required this.tint,
    required this.minuteInterval,
    required this.use24HourFormat,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final CupertinoDatePickerMode mode;
  final IOS26DatePickerStyle style;
  final String? title;
  final Color? tint;
  final int minuteInterval;
  final bool use24HourFormat;

  @override
  State<_IOS26DatePickerSheet> createState() => _IOS26DatePickerSheetState();
}

class _IOS26DatePickerSheetState extends State<_IOS26DatePickerSheet> {
  static const _inset = 8.0;
  static const _cornerRadius = 34.0;

  late DateTime _selected = alignDateTimeToInterval(
    widget.initialDate,
    widget.minuteInterval,
  );

  final _picker = IOS26DatePickerController();

  /// Confirms the date, or, while the calendar shows its month and year
  /// wheels, goes back to its days first: a month and a year are not a date
  /// yet, and the checkmark is where one would confirm them.
  Future<void> _onConfirm() async {
    if (await _picker.showDays()) return;
    if (mounted) Navigator.of(context).pop(_result);
  }

  DateTime get _result => switch (widget.mode) {
    CupertinoDatePickerMode.date => DateTime(
      _selected.year,
      _selected.month,
      _selected.day,
    ),
    CupertinoDatePickerMode.monthYear => DateTime(
      _selected.year,
      _selected.month,
    ),
    _ => _selected,
  };

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final tint = widget.tint ?? CupertinoTheme.of(context).primaryColor;
    final title = widget.title;
    final localizations = MaterialLocalizations.of(context);
    // The rounder the display's corners, the rounder the sheet's bottom ones,
    // and the more room the picker keeps above them.
    final cornerRoom =
        (IOS26GlassSurface.concentricRadius(
              inset: _inset,
              minimum: _cornerRadius,
            ) -
            _cornerRadius) *
        0.4;
    return SafeArea(
      top: false,
      bottom: false,
      minimum: const EdgeInsets.symmetric(horizontal: _inset),
      child: Padding(
        padding: const EdgeInsets.only(bottom: _inset),
        child: IOS26GlassSurface(
          cornerRadius: _cornerRadius,
          corners: GlassSurfaceCorners.concentric,
          tint: dark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                child: Row(
                  children: [
                    _SheetButton(
                      label: localizations.closeButtonTooltip,
                      symbol: const SFSymbol(
                        'xmark',
                        size: 17,
                        weight: FontWeight.w600,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: title == null
                          ? const SizedBox.shrink()
                          : Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CupertinoTheme.of(
                                context,
                              ).textTheme.navTitleTextStyle,
                            ),
                    ),
                    _SheetButton(
                      label: localizations.okButtonLabel,
                      symbol: const SFSymbol(
                        'checkmark',
                        size: 17,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      color: tint,
                      prominent: true,
                      onPressed: _onConfirm,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  12 + (cornerRoom > 0 ? cornerRoom : 0),
                ),
                child: IOS26DatePicker(
                  initialDate: _selected,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  mode: widget.mode,
                  style: widget.style,
                  tint: tint,
                  minuteInterval: widget.minuteInterval,
                  use24HourFormat: widget.use24HourFormat,
                  controller: _picker,
                  onChanged: (date) => _selected = date,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round button of the sheet, as tall as a toolbar button.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.symbol,
    required this.onPressed,
    this.color,
    this.prominent = false,
  });

  final String label;
  final SFSymbol symbol;
  final VoidCallback onPressed;
  final Color? color;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: 44,
        child: AdaptiveButton.sfSymbol(
          onPressed: onPressed,
          sfSymbol: symbol,
          color: color,
          style: prominent
              ? AdaptiveButtonStyle.prominentGlass
              : AdaptiveButtonStyle.glass,
          // A capsule, which is a circle at this size.
          useSmoothRectangleBorder: false,
        ),
      ),
    );
  }
}
