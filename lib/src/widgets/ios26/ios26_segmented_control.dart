import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'native_view_settle.dart';

/// Native iOS 26 segmented control implementation using platform views
class IOS26SegmentedControl extends StatefulWidget {
  const IOS26SegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.icons,
    this.iconSize,
    this.iconColor,
    this.textColor,
    this.selectedTextColor,
  });

  /// Segment labels to display, in order
  final List<String> labels;

  /// The index of the selected segment
  final int selectedIndex;

  /// Called when the user selects a segment
  final ValueChanged<int> onValueChanged;

  /// Whether the control is interactive
  final bool enabled;

  /// Tint color for the selected segment
  final Color? color;

  /// Height of the control
  final double height;

  /// Whether the control should shrink to fit content
  final bool shrinkWrap;

  /// Optional SF Symbol names for icons (iOS only)
  final List<dynamic>? icons;

  /// Icon size (when using icons)
  final double? iconSize;

  /// Icon color (when using icons)
  final Color? iconColor;

  /// Optional text color for unselected segments.
  final Color? textColor;

  /// Optional text color for the selected segment.
  final Color? selectedTextColor;

  /// Takes the native control's path in a test, where there is no UIKit.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26SegmentedControl> createState() => _IOS26SegmentedControlState();
}

class _IOS26SegmentedControlState extends State<IOS26SegmentedControl>
    with
        SingleTickerProviderStateMixin,
        NativeViewSettle<IOS26SegmentedControl> {
  static int _nextId = 0;

  static bool get _hasUIKit =>
      IOS26SegmentedControl.debugHasUIKitOverride ??
      (!kIsWeb && Platform.isIOS);

  /// The stand-in's opacity: 1 while it stands in for the native control, and
  /// fading out over it once that is back.
  late final AnimationController _standIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addStatusListener((_) => mounted ? setState(() {}) : null);

  late final int _id;
  late final MethodChannel _channel;
  bool? _lastIsDark;
  int? _lastTintColor;
  int? _lastTextColor;
  int? _lastSelectedTextColor;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel(
      'adaptive_platform_ui/ios26_segmented_control_$_id',
    );
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasUIKit) followRoute();
    _syncThemeIfNeeded();
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
    // The native control is back on screen with the next frame; the stand-in
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

  Brightness _effectiveBrightness() {
    return CupertinoTheme.of(context).brightness ??
        Theme.of(context).brightness;
  }

  Future<void> _syncThemeIfNeeded() async {
    final isDark = _effectiveBrightness() == Brightness.dark;
    final themeParams = _buildThemeParams();
    final tintColor = widget.color != null ? _colorToARGB(widget.color!) : null;
    final textColor = themeParams['textColor'] as int;
    final selectedTextColor = themeParams['selectedTextColor'] as int;

    if (_lastIsDark != isDark ||
        _lastTintColor != tintColor ||
        _lastTextColor != textColor ||
        _lastSelectedTextColor != selectedTextColor) {
      try {
        await _channel.invokeMethod('setBrightness', {
          'isDark': isDark,
          if (tintColor != null) 'tintColor': tintColor,
          ...themeParams,
        });
        _lastIsDark = isDark;
        _lastTintColor = tintColor;
        _lastTextColor = textColor;
        _lastSelectedTextColor = selectedTextColor;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final index = call.arguments['index'] as int;
      final itemCount = (widget.icons != null && widget.icons!.isNotEmpty)
          ? widget.icons!.length
          : widget.labels.length;

      if (index >= 0 && index < itemCount && widget.enabled) {
        widget.onValueChanged(index);
      }
    }
  }

  @override
  void didUpdateWidget(IOS26SegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _channel.invokeMethod('setSelectedIndex', {
        'index': widget.selectedIndex,
      });
    }

    _syncThemeIfNeeded();
  }

  int _colorToARGB(Color color) {
    return ((color.a * 255.0).round() & 0xff) << 24 |
        ((color.r * 255.0).round() & 0xff) << 16 |
        ((color.g * 255.0).round() & 0xff) << 8 |
        ((color.b * 255.0).round() & 0xff);
  }

  Map<String, dynamic> _buildThemeParams() {
    final cupertinoTheme = CupertinoTheme.of(context);
    final brightness = _effectiveBrightness();

    final baseTextStyle = DefaultTextStyle.of(context).style;
    final themeTextStyle = cupertinoTheme.textTheme.textStyle;

    final effectiveTextColor =
        widget.textColor ??
        baseTextStyle.color ??
        themeTextStyle.color ??
        (brightness == Brightness.dark
            ? CupertinoColors.white
            : CupertinoColors.black);

    final effectiveSelectedTextColor =
        widget.selectedTextColor ??
        (widget.color != null ? CupertinoColors.white : effectiveTextColor);

    return <String, dynamic>{
      'textColor': _colorToARGB(effectiveTextColor),
      'selectedTextColor': _colorToARGB(effectiveSelectedTextColor),
    };
  }

  Map<String, dynamic> _buildCreationParams() {
    final bool isDark = _effectiveBrightness() == Brightness.dark;

    final params = <String, dynamic>{
      'id': _id,
      'labels': widget.labels,
      'selectedIndex': widget.selectedIndex,
      'enabled': widget.enabled,
      'isDark': isDark,
      ..._buildThemeParams(),
    };

    // Add SF symbols if provided
    if (widget.icons != null && widget.icons!.isNotEmpty) {
      params['sfSymbols'] = widget.icons!;
    }

    // Add color if provided
    if (widget.color != null) {
      params['tintColor'] = _colorToARGB(widget.color!);
    }

    // Add icon size if provided
    if (widget.iconSize != null) {
      params['iconSize'] = widget.iconSize!;
    }

    // Add icon color if provided
    if (widget.iconColor != null) {
      params['iconColor'] = _colorToARGB(widget.iconColor!);
    }

    return params;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasUIKit) {
      // Laid out all along, so the native view is made once; on screen only
      // while its page holds still in front. Left on screen under a dialog or
      // a page sliding over it, iOS composited what came after it only within
      // the clip around it: a sheet's shape. A stand-in takes its place.
      final platformView = IgnorePointer(
        ignoring: !settled,
        child: Opacity(
          opacity: settled ? 1 : 0,
          child: UiKitView(
            viewType: 'adaptive_platform_ui/ios26_segmented_control',
            creationParams: _buildCreationParams(),
            creationParamsCodec: const StandardMessageCodec(),
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
              Factory<HorizontalDragGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
              ),
              Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
            },
          ),
        ),
      );
      final themeParams = _buildThemeParams();
      final standIn = !settled || _standIn.value > 0
          ? FadeTransition(
              opacity: _standIn,
              child: _SegmentedControlStandIn(
                labels: widget.labels,
                selectedIndex: widget.selectedIndex,
                tint: widget.color,
                textColor: Color(themeParams['textColor'] as int),
                selectedTextColor: Color(
                  themeParams['selectedTextColor'] as int,
                ),
              ),
            )
          : const SizedBox.shrink();
      // The same children in every state, so the native view stays put.
      Widget control = SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(child: platformView),
            Positioned.fill(child: standIn),
          ],
        ),
      );

      // Center if shrinkWrap is true (but don't use IntrinsicWidth with UiKitView)
      if (widget.shrinkWrap) {
        control = Center(child: control);
      }

      return control;
    }

    // Fallback for non-iOS (should not reach here in normal usage)
    final Map<int, Widget> children = {};
    for (int i = 0; i < widget.labels.length; i++) {
      children[i] = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          widget.labels[i],
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      );
    }

    Widget control = CupertinoSegmentedControl<int>(
      children: children,
      groupValue: widget.selectedIndex,
      onValueChanged: widget.enabled ? widget.onValueChanged : (_) {},
    );

    if (widget.shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return SizedBox(height: widget.height, child: control);
  }
}

/// What shows for the native segmented control while its page is covered or
/// moves: its segments on a capsule track, the one selected on a thumb in its
/// tint, as UIKit draws them. It takes no touches.
class _SegmentedControlStandIn extends StatelessWidget {
  const _SegmentedControlStandIn({
    required this.labels,
    required this.selectedIndex,
    required this.tint,
    required this.textColor,
    required this.selectedTextColor,
  });

  final List<String> labels;
  final int selectedIndex;
  final Color? tint;
  final Color textColor;
  final Color selectedTextColor;

  @override
  Widget build(BuildContext context) {
    final track = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final thumb =
        tint ??
        CupertinoDynamicColor.resolve(
          const CupertinoDynamicColor.withBrightness(
            color: CupertinoColors.white,
            darkColor: Color(0xFF636366),
          ),
          context,
        );
    return IgnorePointer(
      child: DecoratedBox(
        decoration: ShapeDecoration(color: track, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              for (final (i, label) in labels.indexed)
                Expanded(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: i == selectedIndex ? thumb : null,
                      shape: const StadiumBorder(),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == selectedIndex
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: i == selectedIndex
                              ? selectedTextColor
                              : textColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
