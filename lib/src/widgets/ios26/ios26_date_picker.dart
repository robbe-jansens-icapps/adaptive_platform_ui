import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// How [IOS26DatePicker] shows its dates.
enum IOS26DatePickerStyle {
  /// The calendar of iOS, which switches to month and year wheels from its
  /// header.
  inline,

  /// The wheels of iOS.
  wheels,
}

/// Drives an [IOS26DatePicker] from outside it.
class IOS26DatePickerController {
  _IOS26DatePickerState? _state;

  /// While the picker's calendar shows its month and year wheels, goes back to
  /// its days, as a tap on its header does, and completes with true. False
  /// when it shows its days already, has no calendar, or has no UIKit: a
  /// button that confirms can then confirm.
  Future<bool> showDays() async => await _state?._showDays() ?? false;
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
    this.controller,
    this.deferNative = false,
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

  final IOS26DatePickerController? controller;

  /// While true, a Flutter stand-in takes the native picker's place and the
  /// native picker is not made yet: UIKit takes a while to make it, which
  /// stalls an animation running meanwhile, such as the sheet it comes up in.
  /// Once false, it is made and fades in over the stand-in: the system's
  /// wheels over Flutter's, the calendar into its room.
  final bool deferNative;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26DatePicker> createState() => _IOS26DatePickerState();
}

class _IOS26DatePickerState extends State<IOS26DatePicker> {
  static const _fade = Duration(milliseconds: 150);

  /// How long the native picker may take to say its height before it shows
  /// all the same.
  static const _heightAtLatest = Duration(milliseconds: 300);

  /// The heights native pickers needed, by style, mode, display width and
  /// text size: the next one starts at its height rather than growing to it.
  static final _knownHeights = <String, double>{};

  MethodChannel? _channel;

  /// The height the native picker needs at the width it has, once it said.
  double? _height;

  /// Whether the native picker is made, and whether it shows, drawn at its
  /// height: until then the stand-in does.
  bool _made = false;
  bool _shown = false;
  bool _standInGone = false;
  Timer? _showAtLatest;

  static bool get _hasUIKit =>
      IOS26DatePicker.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(IOS26DatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _channel?.setMethodCallHandler(null);
    _showAtLatest?.cancel();
    super.dispose();
  }

  String _heightKey(BuildContext context) =>
      '${widget.style.name} $_mode ${MediaQuery.sizeOf(context).width.round()} '
      '${MediaQuery.textScalerOf(context).scale(17)}';

  /// Shows the native picker once the frame with it at its height is drawn.
  void _show() {
    _showAtLatest?.cancel();
    if (_shown) return;
    SchedulerBinding.instance.endOfFrame.then((_) {
      if (mounted && !_shown) setState(() => _shown = true);
    });
  }

  Future<bool> _showDays() async {
    final channel = _channel;
    if (channel == null || widget.style != IOS26DatePickerStyle.inline) {
      return false;
    }
    try {
      return await channel.invokeMethod<bool>('showDays') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  String get _mode => switch (widget.mode) {
    CupertinoDatePickerMode.time => 'time',
    CupertinoDatePickerMode.dateAndTime => 'dateAndTime',
    CupertinoDatePickerMode.monthYear => 'yearAndMonth',
    _ => 'date',
  };

  void _onCreated(int id) {
    _showAtLatest = Timer(_heightAtLatest, _show);
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
              _knownHeights[_heightKey(context)] = height;
              setState(() => _height = height);
            }
            if (mounted) _show();
        }
      });
  }

  /// The wheels as Flutter draws them, where there is no UIKit, and in place
  /// of the system's wheels until they show.
  Widget _cupertinoWheels() => SizedBox(
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

  @override
  Widget build(BuildContext context) {
    if (!_hasUIKit) return _cupertinoWheels();
    _made = _made || !widget.deferNative;
    final tint = widget.tint;
    final firstDate = widget.firstDate;
    final lastDate = widget.lastDate;
    final inline = widget.style == IOS26DatePickerStyle.inline;
    return SizedBox(
      height:
          _height ?? _knownHeights[_heightKey(context)] ?? (inline ? 360 : 216),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_made)
            AnimatedOpacity(
              key: const ValueKey('native'),
              // Faint rather than out until it shows: iOS lays it out, and
              // it says its height, only once it is on screen.
              opacity: _shown ? 1 : 0.01,
              duration: _fade,
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
                  'locale': ?Localizations.maybeLocaleOf(
                    context,
                  )?.toLanguageTag(),
                  'isDark':
                      MediaQuery.maybePlatformBrightnessOf(context) ==
                      Brightness.dark,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onCreated,
                // Its wheels and its calendar take every touch on them.
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                },
              ),
            ),
          if (!_standInGone)
            IgnorePointer(
              key: const ValueKey('stand-in'),
              child: AnimatedOpacity(
                opacity: _shown ? 0 : 1,
                duration: _fade,
                onEnd: () => setState(() => _standInGone = true),
                child: inline ? const SizedBox.shrink() : _cupertinoWheels(),
              ),
            ),
        ],
      ),
    );
  }
}
