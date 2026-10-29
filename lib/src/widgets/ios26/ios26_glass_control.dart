import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ios26_glass_surface.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/adaptive_native_view.dart';
import 'native_chrome/native_snapshot.dart';
import 'native_view_settle.dart';

/// A Liquid Glass capsule with an icon, a label and a trailing icon, all drawn
/// by iOS over the Flutter view ([AdaptiveNativeChrome.enabled]): a search
/// field's capsule, a filter chip, a round button over a map.
///
/// A glass surface with Flutter content on it ([IOS26GlassSurface]) needs a
/// platform view, as the content has to be above the glass. Here iOS draws the
/// content too: the label in the app font (`AdaptiveNativeFonts`), [leading]
/// and [trailing] from images of the widgets Flutter draws for them. Flutter
/// lays the control out as a row of them, which it keeps out of sight, and
/// iOS puts each where Flutter laid it out.
///
/// While its page moves or something covers it, the control is drawn by
/// Flutter, on the glass's stand-in. Without [AdaptiveNativeChrome.enabled],
/// or off iOS, it is a row on an [IOS26GlassSurface].
class IOS26GlassControl extends StatefulWidget {
  const IOS26GlassControl({
    super.key,
    required this.onPressed,
    this.leading,
    this.label,
    this.labelStyle,
    this.trailing,
    this.onTrailingPressed,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.spacing = 10,
    this.trailingSpacing = 8,
    this.expands = false,
    this.semanticLabel,
  });

  /// Called on a tap on the control, beside [trailing]; null for a control
  /// that takes no touches.
  final VoidCallback? onPressed;

  /// An icon before the label, drawn as an image of this widget.
  final Widget? leading;

  final String? label;

  /// The label's style, over the ambient [DefaultTextStyle]: its size,
  /// weight and colour reach iOS.
  final TextStyle? labelStyle;

  /// An icon after the label, drawn as an image of this widget: a tap on it
  /// calls [onTrailingPressed].
  final Widget? trailing;
  final VoidCallback? onTrailingPressed;

  /// The glass's tint.
  final Color? tint;

  final EdgeInsets padding;

  /// The room between [leading] and the label.
  final double spacing;

  /// The room before [trailing].
  final double trailingSpacing;

  /// Whether the label takes all the width the control is given, rather than
  /// what it needs.
  final bool expands;

  /// What VoiceOver reads for the control; [label] by default.
  final String? semanticLabel;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26GlassControl> createState() => _IOS26GlassControlState();
}

class _IOS26GlassControlState extends State<IOS26GlassControl>
    with NativeViewSettle<IOS26GlassControl> {
  static bool get _hasUIKit =>
      IOS26GlassControl.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  final GlobalKey _controlKey = GlobalKey();
  final GlobalKey _leadingKey = GlobalKey();
  final GlobalKey _labelKey = GlobalKey();
  final GlobalKey _trailingKey = GlobalKey();

  MethodChannel? _channel;
  Map<String, Object?>? _sent;
  final Map<String, (Uint8List, double)> _images = {};

  bool get _native => _hasUIKit && AdaptiveNativeChrome.enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_native) followRoute();
  }

  @override
  bool get followsRouteOverFlutter => _native && routeIsFollowed;

  @override
  void didChangeSettled(bool settled) => setState(() {});

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onCreated(int id) {
    final channel = MethodChannel(
      'adaptive_platform_ui/ios26_glass_control_$id',
    )..setMethodCallHandler(_handle);
    _channel = channel;
    _sent = null;
    _sendLayout();
    for (final MapEntry(key: slot, value: (bytes, scale)) in _images.entries) {
      channel.invokeMethod<void>('setImage', {
        'slot': slot,
        'bytes': bytes,
        'scale': scale,
      });
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'pressed':
        widget.onPressed?.call();
      case 'trailingPressed':
        (widget.onTrailingPressed ?? widget.onPressed)?.call();
    }
    return null;
  }

  /// Where Flutter laid out the icons and the label, and how the label looks,
  /// for iOS to draw them there; after every frame that may have moved them.
  void _sendLayout() {
    final channel = _channel;
    final control = _controlKey.currentContext?.findRenderObject();
    if (channel == null || control is! RenderBox || !control.hasSize) return;
    List<double>? frameOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: control);
      return [topLeft.dx, topLeft.dy, box.size.width, box.size.height];
    }

    final style = DefaultTextStyle.of(context).style.merge(widget.labelStyle);
    final params = <String, Object?>{
      'isDark':
          MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark,
      'interactive': widget.onPressed != null,
      'tint': widget.tint?.toARGB32(),
      'label': widget.label,
      'labelColor': (style.color ?? const Color(0xFF000000)).toARGB32(),
      'fontSize': MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14),
      'fontWeight': (style.fontWeight ?? FontWeight.w400).value,
      'leading': frameOf(_leadingKey),
      'labelFrame': frameOf(_labelKey),
      'trailing': frameOf(_trailingKey),
    };
    if (_paramsEqual(params, _sent)) return;
    _sent = params;
    channel.invokeMethod<void>('update', params);
  }

  static bool _paramsEqual(Map<String, Object?> a, Map<String, Object?>? b) {
    if (b == null || a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      final other = b[key];
      if (value is List<double> && other is List<double>) {
        if (!listEquals(value, other)) return false;
      } else if (value != other) {
        return false;
      }
    }
    return true;
  }

  void _onImage(String slot, Uint8List bytes, double scale) {
    _images[slot] = (bytes, scale);
    _channel?.invokeMethod<void>('setImage', {
      'slot': slot,
      'bytes': bytes,
      'scale': scale,
    });
  }

  @override
  Widget build(BuildContext context) {
    final native = _native;
    final leading = widget.leading;
    final label = widget.label;
    final trailing = widget.trailing;
    final row = Row(
      mainAxisSize: widget.expands ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (leading != null)
          KeyedSubtree(
            key: _leadingKey,
            child: NativeSnapshot(
              enabled: native,
              onImage: (bytes, scale) => _onImage('leading', bytes, scale),
              child: leading,
            ),
          ),
        if (leading != null && label != null) SizedBox(width: widget.spacing),
        if (label != null)
          Flexible(
            fit: widget.expands ? FlexFit.tight : FlexFit.loose,
            child: Text(
              label,
              key: _labelKey,
              style: widget.labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (trailing != null) ...[
          SizedBox(width: widget.trailingSpacing),
          KeyedSubtree(
            key: _trailingKey,
            child: NativeSnapshot(
              enabled: native,
              onImage: (bytes, scale) => _onImage('trailing', bytes, scale),
              child: native
                  ? trailing
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTrailingPressed ?? widget.onPressed,
                      child: trailing,
                    ),
            ),
          ),
        ],
      ],
    );
    final content = Align(
      alignment: label == null
          ? Alignment.center
          : AlignmentDirectional.centerStart,
      widthFactor: widget.expands ? null : 1,
      heightFactor: 1,
      child: Padding(padding: widget.padding, child: row),
    );
    final semantics = widget.semanticLabel ?? label;

    if (!native) {
      return Semantics(
        button: widget.onPressed != null,
        label: semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: IOS26GlassSurface(
            corners: GlassSurfaceCorners.capsule,
            interactive: widget.onPressed != null,
            tint: widget.tint,
            child: ExcludeSemantics(child: content),
          ),
        ),
      );
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendLayout();
    });
    return Semantics(
      container: true,
      button: widget.onPressed != null,
      label: semantics,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Stack(
          key: _controlKey,
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              // Painted only while it holds still in front: the stand-in and
              // the row take its place meanwhile.
              child: Opacity(
                opacity: settled ? 1 : 0,
                child: AdaptiveNativeView(
                  viewType: 'adaptive_platform_ui/ios26_glass_control',
                  chrome: true,
                  interactive: widget.onPressed != null,
                  onPlatformViewCreated: _onCreated,
                ),
              ),
            ),
            if (!settled)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) => DecoratedBox(
                    decoration: glassStandInDecoration(
                      context,
                      tint: widget.tint,
                      borderRadius: BorderRadius.circular(
                        constraints.biggest.shortestSide / 2,
                      ),
                    ),
                  ),
                ),
              ),
            IgnorePointer(
              child: NativeOutOfSight(visible: !settled, child: content),
            ),
          ],
        ),
      ),
    );
  }
}
