import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../style/glass_button_glyph.dart';
import '../../style/sf_symbol.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/adaptive_native_view.dart';
import 'native_view_settle.dart';

/// iOS 26 native button styles (Liquid Glass design)
enum IOS26ButtonStyle {
  /// Filled button with solid background (primary action)
  filled,

  /// Tinted button with translucent background
  tinted,

  /// Gray button with subtle background
  gray,

  /// Bordered button with outline
  bordered,

  /// Plain text button without background
  plain,

  /// Glass effect button with translucent blur
  glass,

  /// Prominent glass button with enhanced blur effect
  prominentGlass,
}

/// iOS 26 button size presets matching native design
enum IOS26ButtonSize {
  /// Small button (height: 28)
  small,

  /// Medium button (height: 36) - default
  medium,

  /// Large button (height: 44)
  large,
}

/// Native iOS 26 button implementation using platform views
///
/// This button uses UIKit platform views to render native iOS 26 Liquid Glass
/// designs. It communicates with the native iOS side via platform channels.
///
/// Features:
/// - Native Liquid Glass visual effects
/// - iOS 26 button styles and animations
/// - Haptic feedback
/// - Native gesture handling
/// - Automatic light/dark mode support
///
/// Note: For complex layouts with custom widgets, use the AdaptiveButton.child() constructor
/// which will overlay the widget on top of the native iOS 26 button.
///
/// The native button is on screen only while its page holds still in front,
/// as the glass surfaces are ([IOS26GlassSurface]): under a dialog or a sheet,
/// and while pages move, a Flutter stand-in takes its place, with the glyph as
/// iOS shows it in the native button ([GlassButtonGlyph]).
class IOS26Button extends StatefulWidget {
  /// Creates an iOS 26 style button with a text label
  const IOS26Button({
    super.key,
    required this.onPressed,
    required this.label,
    this.style = IOS26ButtonStyle.filled,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.textColor,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
    this.chrome = false,
    this.dim,
  }) : child = null,
       isChildMode = false,
       sfSymbol = null;

  /// Creates an iOS 26 style button with a custom child widget
  /// The child will be overlaid on top of the native button background
  const IOS26Button.child({
    super.key,
    required this.onPressed,
    required this.child,
    this.style = IOS26ButtonStyle.filled,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
  }) : label = '',
       textColor = null,
       isChildMode = true,
       sfSymbol = null,
       chrome = false,
       dim = null;

  /// Creates an iOS 26 style button with a native SF Symbol icon
  const IOS26Button.sfSymbol({
    super.key,
    required this.onPressed,
    required this.sfSymbol,
    this.style = IOS26ButtonStyle.glass,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
    this.chrome = false,
    this.dim,
  }) : label = '',
       textColor = null,
       child = null,
       isChildMode = false;

  /// The callback that is called when the button is tapped
  final VoidCallback? onPressed;

  /// The text label of the button
  final String label;

  /// The custom child widget (used in .child() constructor)
  final Widget? child;

  /// The SF Symbol to display (used in .sfSymbol() constructor)
  final SFSymbol? sfSymbol;

  /// Whether this is child mode
  final bool isChildMode;

  /// The visual style of the button
  final IOS26ButtonStyle style;

  /// The size preset for the button
  final IOS26ButtonSize size;

  /// The color of the button (uses system blue if not specified)
  final Color? color;

  /// The color of the button text
  final Color? textColor;

  /// Whether the button is enabled
  final bool enabled;

  /// The amount of space to surround the child inside the button
  final EdgeInsetsGeometry? padding;

  /// The border radius of the button
  final BorderRadius? borderRadius;

  /// The minimum size of the button
  final Size? minSize;

  /// Whether to use smooth rectangle border (iOS 26+ only)
  /// When false, uses perfectly circular/capsule shape
  /// Default is true for smooth rectangle, set to false for circular
  final bool useSmoothRectangleBorder;

  /// Whether the native button is shown over the Flutter view rather than as
  /// a platform view, with [AdaptiveNativeChrome.enabled]. Not for a button
  /// with a Flutter [child], which Flutter draws on top of it.
  final bool chrome;

  /// A dialog's barrier over a button shown over the Flutter view ([chrome]),
  /// which Flutter cannot draw over it: iOS lays it over the button's glass in
  /// this colour.
  final ValueListenable<Color?>? dim;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26Button> createState() => _IOS26ButtonState();
}

class _IOS26ButtonState extends State<IOS26Button>
    with SingleTickerProviderStateMixin, NativeViewSettle<IOS26Button> {
  static int _nextId = 0;
  late final int _id;
  late final MethodChannel _channel;
  bool? _lastIsDark;

  static bool get _hasUIKit =>
      IOS26Button.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  /// The stand-in's opacity: 1 while it stands in for the native button, and
  /// fading out over it once that is back.
  late final AnimationController _standIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addStatusListener(_onStandInStatus);

  /// The glyph of an SF Symbol button, once iOS has handed it over, and what
  /// it was asked for with.
  GlassButtonGlyph? _glyph;
  Object? _glyphKey;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel('adaptive_platform_ui/ios26_button_$_id');
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasUIKit) {
      followRoute();
      _loadGlyph();
    }
    _syncBrightnessIfNeeded();
  }

  @override
  void dispose() {
    _standIn.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  bool get followsRouteOverFlutter =>
      widget.chrome &&
      !widget.isChildMode &&
      AdaptiveNativeChrome.enabled &&
      routeIsFollowed;

  @override
  void didChangeSettled(bool settled) {
    if (!settled) {
      _standIn.value = 1;
      return;
    }
    if (_standIn.value == 0) return;
    // The native button is back on screen with the next frame; the stand-in
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

  // Gone once faded out.
  void _onStandInStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  /// Has iOS hand over the glyph of an SF Symbol button, for the stand-in,
  /// at the size the button is laid out at: long before a dialog or a page
  /// comes over it.
  void _loadGlyph() {
    final symbol = widget.sfSymbol;
    if (symbol == null) return;
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(symbol, widget.sfSymbol)) return;
      final box = context.findRenderObject();
      final laidOut = box is RenderBox && box.hasSize && !box.size.isEmpty;
      final side = laidOut ? box.size.shortestSide : _height;
      final key = (symbol.name, symbol.size, symbol.weight, side, dark);
      if (key == _glyphKey) return;
      _glyphKey = key;
      GlassButtonGlyph.load(symbol, context, side: side, dark: dark).then((
        glyph,
      ) {
        if (!mounted || key != _glyphKey) return;
        setState(() => _glyph = glyph);
      });
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
      case 'pressed':
        if (widget.enabled && widget.onPressed != null) {
          widget.onPressed!();
        }
        break;
    }
  }

  @override
  void didUpdateWidget(IOS26Button oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update native side if properties changed
    if (oldWidget.style != widget.style) {
      _channel.invokeMethod('setStyle', {
        'style': _styleToString(widget.style),
      });
    }

    // A missing onPressed disables the button just like enabled: false.
    if (oldWidget.enabled != widget.enabled ||
        (oldWidget.onPressed == null) != (widget.onPressed == null)) {
      _channel.invokeMethod('setEnabled', {
        'enabled': widget.enabled && widget.onPressed != null,
      });
    }

    if (oldWidget.label != widget.label) {
      _channel.invokeMethod('setLabel', {'label': widget.label});
    }

    if (oldWidget.color != widget.color) {
      _channel.invokeMethod('setColor', {
        'color': widget.color != null ? _colorToHex(widget.color!) : null,
      });
    }

    if (oldWidget.useSmoothRectangleBorder != widget.useSmoothRectangleBorder) {
      _channel.invokeMethod('setUseSmoothRectangleBorder', {
        'useSmoothRectangleBorder': widget.useSmoothRectangleBorder,
      });
    }

    // Update SF Symbol if changed
    if (oldWidget.sfSymbol?.name != widget.sfSymbol?.name ||
        oldWidget.sfSymbol?.size != widget.sfSymbol?.size ||
        oldWidget.sfSymbol?.color != widget.sfSymbol?.color ||
        oldWidget.sfSymbol?.weight != widget.sfSymbol?.weight) {
      if (_hasUIKit) _loadGlyph();
      if (widget.sfSymbol != null) {
        _channel.invokeMethod('setIcon', {
          'iconName': widget.sfSymbol!.name,
          'iconSize': widget.sfSymbol!.size,
          if (widget.sfSymbol!.weight != null)
            'iconWeight': widget.sfSymbol!.weight!.value,
          if (widget.sfSymbol!.color != null)
            'iconColor': _colorToARGB(widget.sfSymbol!.color!),
        });
      }
    }
  }

  Map<String, dynamic> _buildCreationParams() {
    return {
      'id': _id,
      'label': widget.label,
      'style': _styleToString(widget.style),
      'size': _sizeToString(widget.size),
      'enabled': widget.enabled && widget.onPressed != null,
      'color': widget.color != null ? _colorToHex(widget.color!) : null,
      'textColor': widget.textColor != null
          ? _colorToHex(widget.textColor!)
          : null,
      'isDark': MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      'useSmoothRectangleBorder': widget.useSmoothRectangleBorder,
      if (widget.sfSymbol != null) 'iconName': widget.sfSymbol!.name,
      if (widget.sfSymbol != null) 'iconSize': widget.sfSymbol!.size,
      if (widget.sfSymbol?.weight != null)
        'iconWeight': widget.sfSymbol!.weight!.value,
      if (widget.sfSymbol?.color != null)
        'iconColor': _colorToARGB(widget.sfSymbol!.color!),
    };
  }

  String _styleToString(IOS26ButtonStyle style) {
    switch (style) {
      case IOS26ButtonStyle.filled:
        return 'filled';
      case IOS26ButtonStyle.tinted:
        return 'tinted';
      case IOS26ButtonStyle.gray:
        return 'gray';
      case IOS26ButtonStyle.bordered:
        return 'bordered';
      case IOS26ButtonStyle.plain:
        return 'plain';
      case IOS26ButtonStyle.glass:
        return 'glass';
      case IOS26ButtonStyle.prominentGlass:
        return 'prominentGlass';
    }
  }

  String _sizeToString(IOS26ButtonSize size) {
    switch (size) {
      case IOS26ButtonSize.small:
        return 'small';
      case IOS26ButtonSize.medium:
        return 'medium';
      case IOS26ButtonSize.large:
        return 'large';
    }
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  int _colorToARGB(Color color) {
    return (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
  }

  double get _height {
    switch (widget.size) {
      case IOS26ButtonSize.small:
        return 28.0;
      case IOS26ButtonSize.medium:
        return 36.0;
      case IOS26ButtonSize.large:
        return 44.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only use native implementation on iOS
    if (_hasUIKit) {
      // Laid out all along, so the button keeps its size and the native view
      // is made once; painted only while its page holds still in front.
      final platformView = IgnorePointer(
        ignoring: !settled,
        child: Opacity(
          opacity: settled ? 1 : 0,
          child: AdaptiveNativeView(
            viewType: 'adaptive_platform_ui/ios26_button',
            creationParams: _buildCreationParams(),
            chrome: widget.chrome,
            dim: widget.dim,
          ),
        ),
      );
      final standIn = !settled || _standIn.value > 0
          ? FadeTransition(
              opacity: _standIn,
              child: _ButtonStandIn(button: widget, glyph: _glyph),
            )
          : const SizedBox.shrink();
      // The same children in every state, so the native view stays put.
      Widget withStandIn(Widget? content) => Stack(
        children: [
          Positioned.fill(child: platformView),
          Positioned.fill(child: standIn),
          ?content,
        ],
      );

      // Wrap in SizedBox for height constraint. In child mode the Flutter-drawn
      // child gives the button its intrinsic width; [padding] surrounds it so
      // the native pill extends past the label like the native title mode does.
      Widget buttonWidget = SizedBox(
        height: _height,
        child: withStandIn(
          widget.isChildMode
              ? Center(
                  child: IgnorePointer(
                    child: Padding(
                      padding:
                          widget.padding ??
                          const EdgeInsets.symmetric(horizontal: 16.0),
                      child: widget.child!,
                    ),
                  ),
                )
              : null,
        ),
      );

      // Apply width constraint if minSize is provided.
      if (widget.minSize != null) {
        buttonWidget = widget.isChildMode
            // Child mode sizes itself to its content, so treat minSize as a
            // minimum — matching ConstrainedBox semantics used by the other
            // platform implementations. A fixed SizedBox here would collapse
            // the button to width 0 for callers passing Size(0, h).
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: widget.minSize!.width,
                  minHeight: widget.minSize!.height,
                ),
                child: buttonWidget,
              )
            // Title mode draws the label natively, so Flutter has no intrinsic
            // width for it — keep the explicit size.
            : SizedBox(
                width: widget.minSize!.width,
                height: _height,
                child: withStandIn(null),
              );
      }

      return buttonWidget;
    }

    // Fallback to CupertinoButton on other platforms
    return _buildFallbackButton();
  }

  Widget _buildFallbackButton() {
    final buttonColor = widget.color ?? CupertinoColors.systemBlue;
    final textStyle = TextStyle(
      color: widget.textColor ?? CupertinoColors.white,
    );

    // If child mode, use the child widget
    final buttonChild = widget.isChildMode
        ? widget.child!
        : Text(widget.label, style: textStyle);

    switch (widget.style) {
      case IOS26ButtonStyle.filled:
        return CupertinoButton.filled(
          onPressed: widget.enabled ? widget.onPressed : null,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: buttonChild,
        );

      case IOS26ButtonStyle.plain:
        return CupertinoButton(
          onPressed: widget.enabled ? widget.onPressed : null,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: widget.isChildMode
              ? widget.child!
              : Text(
                  widget.label,
                  style: TextStyle(color: widget.textColor ?? buttonColor),
                ),
        );

      default:
        return CupertinoButton(
          onPressed: widget.enabled ? widget.onPressed : null,
          color: buttonColor,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: buttonChild,
        );
    }
  }
}

/// The button without a native view, for while its page is covered or moves:
/// the button's background in its style, the glass as the glass surfaces stand
/// in for theirs, and its label or glyph where it shows them. In child mode
/// the child is drawn over it, as over the native button.
class _ButtonStandIn extends StatelessWidget {
  const _ButtonStandIn({required this.button, required this.glyph});

  final IOS26Button button;
  final GlassButtonGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final tint = button.color ?? CupertinoColors.systemBlue;
    final glass = button.style == IOS26ButtonStyle.glass;
    final (fill, side, foreground) = switch (button.style) {
      IOS26ButtonStyle.filled => (tint, BorderSide.none, CupertinoColors.white),
      IOS26ButtonStyle.prominentGlass => (
        tint,
        BorderSide.none,
        CupertinoColors.white,
      ),
      IOS26ButtonStyle.tinted => (
        tint.withValues(alpha: 0.15),
        BorderSide.none,
        tint,
      ),
      IOS26ButtonStyle.gray => (
        CupertinoColors.systemGrey5.resolveFrom(context),
        BorderSide.none,
        tint,
      ),
      IOS26ButtonStyle.bordered => (
        null,
        BorderSide(color: tint, width: 1.5),
        tint,
      ),
      IOS26ButtonStyle.plain => (null, BorderSide.none, tint),
      IOS26ButtonStyle.glass => (
        dark ? const Color(0xE6303034) : const Color(0xE6FAFAFC),
        BorderSide(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
          width: 0.5,
        ),
        tint,
      ),
    };
    final color = button.textColor ?? foreground;
    final radius = switch (button.size) {
      IOS26ButtonSize.small => 8.0,
      IOS26ButtonSize.medium => 10.0,
      IOS26ButtonSize.large => 12.0,
    };
    final ShapeBorder shape = button.useSmoothRectangleBorder
        ? RoundedSuperellipseBorder(
            borderRadius: button.borderRadius ?? BorderRadius.circular(radius),
            side: side,
          )
        : StadiumBorder(side: side);
    final symbol = button.sfSymbol;
    final glyph = this.glyph;
    final Widget? content = button.isChildMode
        ? null
        : symbol != null
        ? glyph == null
              ? null
              // Where, how large and in what colour the native button shows it.
              : Transform.translate(
                  offset: glyph.offset,
                  child: Image(
                    image: glyph.image,
                    color: symbol.color ?? color,
                    colorBlendMode: BlendMode.srcIn,
                    gaplessPlayback: true,
                  ),
                )
        : button.label.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              button.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: switch (button.size) {
                  IOS26ButtonSize.small => 13,
                  IOS26ButtonSize.medium => 15,
                  IOS26ButtonSize.large => 17,
                },
                fontWeight: button.size == IOS26ButtonSize.large
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          );
    final enabled = button.enabled && button.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: button.label.isEmpty ? null : button.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? button.onPressed : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: fill,
              shape: shape,
              shadows: glass
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: content == null
                ? const SizedBox.expand()
                : Center(child: ExcludeSemantics(child: content)),
          ),
        ),
      ),
    );
  }
}
