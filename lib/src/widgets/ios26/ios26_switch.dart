import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'native_view_settle.dart';

/// Native iOS 26 switch implementation using platform views
///
/// This switch uses UIKit platform views to render native iOS 26 UISwitch
/// designs. It communicates with the native iOS side via platform channels.
///
/// Features:
/// - Native iOS 26 switch animations
/// - Haptic feedback
/// - Native gesture handling
/// - Automatic light/dark mode support
class IOS26Switch extends StatefulWidget {
  /// Creates an iOS 26 style switch
  const IOS26Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  /// Whether this switch is on or off
  final bool value;

  /// Called when the user toggles the switch on or off
  final ValueChanged<bool>? onChanged;

  /// The color to use when this switch is on
  final Color? activeColor;

  /// The color of the thumb (handle)
  final Color? thumbColor;

  /// Takes the native switch's path in a test, where there is no UIKit.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26Switch> createState() => _IOS26SwitchState();
}

class _IOS26SwitchState extends State<IOS26Switch>
    with SingleTickerProviderStateMixin, NativeViewSettle<IOS26Switch> {
  static int _nextId = 0;

  static bool get _hasUIKit =>
      IOS26Switch.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  /// The stand-in's opacity: 1 while it stands in for the native switch, and
  /// fading out over it once that is back.
  late final AnimationController _standIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addStatusListener((_) => mounted ? setState(() {}) : null);

  late final int _id;
  late final MethodChannel _channel;
  bool? _lastIsDark;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel('adaptive_platform_ui/ios26_switch_$_id');
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasUIKit) followRoute();
    _syncBrightnessIfNeeded();
  }

  @override
  void dispose() {
    _standIn.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeSettled(bool settled) {
    if (!settled) {
      _standIn.value = 1;
      return;
    }
    if (_standIn.value == 0) return;
    // The native switch is back on screen with the next frame; the stand-in
    // makes way once it is.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !this.settled) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _standIn.value = 0;
      } else {
        _standIn.reverse(from: 1);
      }
    });
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (_lastIsDark != isDark) {
      try {
        await _channel.invokeMethod('setBrightness', {'isDark': isDark});
        _lastIsDark = isDark;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'valueChanged':
        final value = call.arguments['value'] as bool;
        if (widget.onChanged != null) {
          widget.onChanged!(value);
        }
        break;
    }
  }

  @override
  void didUpdateWidget(IOS26Switch oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update native side if properties changed
    if (oldWidget.value != widget.value) {
      _channel.invokeMethod('setValue', {'value': widget.value});
    }

    if (oldWidget.activeColor != widget.activeColor &&
        widget.activeColor != null) {
      _channel.invokeMethod('setActiveColor', {
        'color': _colorToARGB(widget.activeColor!),
      });
    }

    if (oldWidget.thumbColor != widget.thumbColor &&
        widget.thumbColor != null) {
      _channel.invokeMethod('setThumbColor', {
        'color': _colorToARGB(widget.thumbColor!),
      });
    }

    // Update enabled state
    if ((oldWidget.onChanged == null) != (widget.onChanged == null)) {
      _channel.invokeMethod('setEnabled', {
        'enabled': widget.onChanged != null,
      });
    }
  }

  Map<String, dynamic> _buildCreationParams() {
    return {
      'id': _id,
      'value': widget.value,
      'enabled': widget.onChanged != null,
      if (widget.activeColor != null)
        'activeColor': _colorToARGB(widget.activeColor!),
      if (widget.thumbColor != null)
        'thumbColor': _colorToARGB(widget.thumbColor!),
      'isDark': MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  int _colorToARGB(Color color) {
    return (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
  }

  @override
  Widget build(BuildContext context) {
    // Only use native implementation on iOS
    if (_hasUIKit) {
      // Laid out all along, so the native view is made once; on screen only
      // while its page holds still in front and it is clear of the bars'
      // frost. A stand-in takes its place in between.
      final platformView = IgnorePointer(
        ignoring: !settled,
        child: Opacity(
          opacity: settled ? 1 : 0,
          child: UiKitView(
            viewType: 'adaptive_platform_ui/ios26_switch',
            creationParams: _buildCreationParams(),
            creationParamsCodec: const StandardMessageCodec(),
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<HorizontalDragGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
              ),
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            },
          ),
        ),
      );
      final standIn = !settled || _standIn.value > 0
          ? FadeTransition(
              opacity: _standIn,
              child: _SwitchStandIn(
                value: widget.value,
                enabled: widget.onChanged != null,
                activeColor: widget.activeColor,
                thumbColor: widget.thumbColor,
                isDark:
                    MediaQuery.platformBrightnessOf(context) == Brightness.dark,
              ),
            )
          : const SizedBox.shrink();

      // The same children in every state, so the native view stays put.
      return SizedBox(
        width: 63, // Standard iOS switch width
        height: 29, // Standard iOS switch height
        child: Stack(
          children: [
            Positioned.fill(child: platformView),
            Positioned.fill(child: standIn),
          ],
        ),
      );
    }

    // Fallback to CupertinoSwitch on other platforms
    return CupertinoSwitch(
      value: widget.value,
      onChanged: widget.onChanged,
      activeTrackColor: widget.activeColor,
      thumbColor: widget.thumbColor ?? CupertinoColors.white,
    );
  }
}

/// What shows for the native switch while its page is covered or moves, or
/// while it is under a bar's frost: its track and thumb as UIKit draws them on
/// iOS 26, a track 63 by 28 points and a thumb 37 by 24 points, 2 points in.
/// It takes no touches.
class _SwitchStandIn extends StatelessWidget {
  const _SwitchStandIn({
    required this.value,
    required this.enabled,
    required this.activeColor,
    required this.thumbColor,
    required this.isDark,
  });

  final bool value;
  final bool enabled;
  final Color? activeColor;
  final Color? thumbColor;

  /// As the native switch is told ([MediaQuery.platformBrightnessOf]).
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final track = value
        ? activeColor ??
              (isDark
                  ? CupertinoColors.systemGreen.darkColor
                  : CupertinoColors.systemGreen.color)
        : isDark
        ? const Color.fromRGBO(235, 235, 245, 0.3)
        : const Color.fromRGBO(60, 60, 67, 0.3);
    return IgnorePointer(
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Center(
          child: SizedBox(
            width: 63,
            height: 28,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: track,
                shape: const StadiumBorder(),
              ),
              child: Align(
                alignment: value
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SizedBox(
                    width: 37,
                    height: 24,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: thumbColor ?? CupertinoColors.white,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
