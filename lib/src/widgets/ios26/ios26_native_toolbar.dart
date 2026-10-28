import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, MaterialLocalizations;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../toolbar/chrome_barrier.dart';
import '../../toolbar/duo_top_strip.dart';
import '../../utils/animation.dart';
import '../adaptive_app_bar_action.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/adaptive_native_view.dart';

/// Native iOS 26 UINavigationBar widget using platform views
/// Implements Liquid Glass design with native blur effects
class IOS26NativeToolbar extends StatefulWidget {
  const IOS26NativeToolbar({
    super.key,
    this.title,
    this.leading,
    this.leadingText,
    this.actions,
    this.onLeadingTap,
    this.onActionTap,
    this.titleWidget,
    this.tintColor,
    this.height = 44.0,
    this.showNativeView = true,
    this.showsGradient = true,
    this.reservesLeading,
    this.leadingInset = 0,
    this.coveredBy,
    this.chrome = false,
  });

  final String? title;
  final Widget? leading;
  final String? leadingText;
  final List<AdaptiveAppBarAction>? actions;
  final VoidCallback? onLeadingTap;
  final ValueChanged<int>? onActionTap;

  /// Custom widget overlaid at the title position.
  /// When set, the native title is hidden and this widget is centered instead,
  /// clear of the controls on both sides, as the system's title: a long title
  /// ends in an ellipsis before it reaches them.
  final Widget? titleWidget;

  /// Tint color for bar button items (action buttons and back button)
  ///
  /// When set, this color is applied to the UINavigationBar's tintColor,
  /// which colors all UIBarButtonItem instances.
  /// If null, the system default tint color is used.
  final Color? tintColor;

  final double height;
  final bool showNativeView;

  /// Whether the native view draws the readability gradient behind the bar.
  /// The fixed toolbar host turns it off and draws one gradient of its own
  /// behind all page layers.
  final bool showsGradient;

  /// Whether a control sits at the leading edge of the bar, which
  /// [titleWidget] keeps clear of, such as a back button the host draws over
  /// the bar. Null: whether there is a [leading] or a [leadingText].
  final bool? reservesLeading;

  /// How much further in than usual the leading control sits, such as clear
  /// of the window controls of an iPad window.
  final double leadingInset;

  /// A dialog or a sheet over the page, whose barrier the bar lays over its
  /// items, as it lies over the page: the bar sits above the navigator, out
  /// of the barrier's reach. A title the native bar draws itself, without
  /// glass, is left as it is.
  final Route<Object?>? coveredBy;

  /// Whether the native bar is shown over the Flutter view rather than as a
  /// platform view, with [AdaptiveNativeChrome.enabled]. Flutter's [leading]
  /// and [titleWidget] then lie under it, where it is clear, and a dialog's
  /// barrier over its items is laid on by iOS.
  final bool chrome;

  @override
  State<IOS26NativeToolbar> createState() => _IOS26NativeToolbarState();
}

class _IOS26NativeToolbarState extends State<IOS26NativeToolbar> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;
  List<AdaptiveAppBarAction>? _lastActions;

  /// Where the native bar's buttons, its leading button and its title are in
  /// its view, as it last told, for their semantics over it.
  final _items =
      ValueNotifier<({List<Rect?> actions, Rect? leading, Rect? title})?>(null);

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  int _colorToARGB(Color color) {
    // Resolve CupertinoDynamicColor if needed
    Color resolvedColor = color;
    if (color is CupertinoDynamicColor) {
      final brightness = MediaQuery.platformBrightnessOf(context);
      resolvedColor = brightness == Brightness.dark
          ? color.darkColor
          : color.color;
    }

    return ((resolvedColor.a * 255.0).round() & 0xff) << 24 |
        ((resolvedColor.r * 255.0).round() & 0xff) << 16 |
        ((resolvedColor.g * 255.0).round() & 0xff) << 8 |
        ((resolvedColor.b * 255.0).round() & 0xff);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _items.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(IOS26NativeToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();

    if (widget.title != oldWidget.title) {
      final ch = _channel;
      // Skip when a titleWidget overlay is shown — the native title stays hidden
      if (ch != null && widget.title != null && widget.titleWidget == null) {
        ch.invokeMethod('updateTitle', {'title': widget.title!});
      }
    }
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    // Sync brightness
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      try {
        await ch.invokeMethod('setBrightness', {'isDark': isDark});
        _lastIsDark = isDark;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }

    // Sync actions (per-action tint, prominent, etc.). A null list and an
    // empty one both mean "no actions", so going from null to a real list
    // (or back) has to reach the native bar too (#84).
    final actions = widget.actions;
    if (!_actionsEqual(_lastActions, actions)) {
      try {
        final params = <String, dynamic>{
          if (actions != null && actions.isNotEmpty)
            'actions': actions.map((a) => a.toNativeMap()).toList(),
        };
        await ch.invokeMethod('updateActions', params);
        _lastActions = actions != null ? List.of(actions) : null;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }

    // Sync tint color
    final tint = widget.tintColor != null
        ? _colorToARGB(widget.tintColor!)
        : null;
    if (_lastTint != tint) {
      try {
        await ch.invokeMethod('setStyle', {'tint': tint});
        _lastTint = tint;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }
  }

  bool _actionsEqual(
    List<AdaptiveAppBarAction>? a,
    List<AdaptiveAppBarAction>? b,
  ) {
    if (identical(a, b)) return true;
    a ??= const <AdaptiveAppBarAction>[];
    b ??= const <AdaptiveAppBarAction>[];
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Whether the bar is shown over the Flutter view, where Flutter cannot
  /// draw over its items.
  bool get _overChrome => widget.chrome && AdaptiveNativeChrome.enabled;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return _buildFallbackToolbar();
    }

    // In the iPhone Duo's top strip the bar sits in the strip, beside the
    // status cluster, rather than below it.
    final strip = DuoTopStripScope.of(context);
    final safePadding = strip != null
        ? DuoTopStrip.barTop
        : MediaQuery.paddingOf(context).top;
    final clusterLeft = strip?.clusterLeft ?? 0;
    final clusterRight = strip?.clusterRight ?? 0;
    final titleInset = _titleInset(clusterLeft, clusterRight);

    final creationParams = <String, dynamic>{
      // Hide native title when a titleWidget overlay is provided
      if (widget.title != null && widget.titleWidget == null)
        'title': widget.title!,
      if (widget.leading == null && widget.leadingText != null)
        'leading': widget.leadingText!,
      if (widget.actions != null && widget.actions!.isNotEmpty)
        'actions': widget.actions!.map((a) => a.toNativeMap()).toList(),
      'isDark': _isDark,
      if (!widget.showsGradient) 'showsGradient': false,
      if (widget.tintColor != null) 'tint': _colorToARGB(widget.tintColor!),
      'barHeight': widget.height,
    };

    return AnimatedContainer(
      height: widget.height + safePadding,
      duration: const Duration(milliseconds: 1000),
      curve: const IOSSpringCurve(),
      child: Stack(
        children: [
          if (widget.showNativeView)
            Positioned(
              left: clusterLeft,
              right: clusterRight,
              top: 0,
              bottom: 0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // VoiceOver passes over a platform view, which has no label
                  // or action of its own, to what lies under it, such as a
                  // list scrolled under the bar: the items' own nodes take
                  // the native bar's place.
                  ExcludeSemantics(
                    child: AdaptiveNativeView(
                      viewType: 'adaptive_platform_ui/ios26_toolbar',
                      creationParams: creationParams,
                      onPlatformViewCreated: _onPlatformViewCreated,
                      hitTestBehavior: PlatformViewHitTestBehavior.translucent,
                      chrome: widget.chrome,
                      dim: _overChrome
                          ? chromeBarrierOf(
                              widget.coveredBy,
                              showsThrough: kGlassShowsThrough,
                            )
                          : null,
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _items,
                    builder: (context, items, _) => _itemSemantics(
                      context,
                      items,
                      top: safePadding,
                      clusterLeft: clusterLeft,
                      clusterRight: clusterRight,
                      titleInset: titleInset,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.leading != null)
            // Centred in the bar, below the status bar.
            Positioned(
              left: _edgeInset(clusterLeft),
              top: safePadding,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: ChromeBarrierTint(
                  barrier: chromeBarrierOf(widget.coveredBy),
                  child: widget.leading!,
                ),
              ),
            ),
          if (widget.titleWidget != null)
            Positioned(
              left: titleInset,
              right: titleInset,
              top: safePadding,
              bottom: 0,
              child: Center(
                child: ChromeBarrierTint(
                  barrier: chromeBarrierOf(widget.coveredBy),
                  child: widget.titleWidget!,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A node for each of the native bar's items where it shows them, or,
  /// until it told where, where it lays them out: in the native view's
  /// coordinates. They take no touches: those go on to the native bar.
  Widget _itemSemantics(
    BuildContext context,
    ({List<Rect?> actions, Rect? leading, Rect? title})? items, {
    required double top,
    required double clusterLeft,
    required double clusterRight,
    required double titleInset,
  }) {
    final actions = widget.actions ?? const <AdaptiveAppBarAction>[];
    final title = widget.titleWidget == null ? widget.title : null;
    final leadingText = widget.leading == null ? widget.leadingText : null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Rect mirrored(Rect rect) => rtl
            ? Rect.fromLTRB(
                width - rect.right,
                rect.top,
                width - rect.left,
                rect.bottom,
              )
            : rect;
        final laidOut = _actionRects(actions, width: width, top: top);
        final localizations =
            Localizations.of<MaterialLocalizations>(
              context,
              MaterialLocalizations,
            ) ??
            const DefaultMaterialLocalizations();
        // Over each native item's glass, which Flutter cannot dim itself.
        final barrier = chromeBarrierOf(
          widget.coveredBy,
          showsThrough: kGlassShowsThrough,
        );
        final item = barrier == null || _overChrome
            ? const SizedBox.expand()
            : ChromeBarrierBox(barrier: barrier, shape: const StadiumBorder());
        final leadingRect = leadingText == null
            ? null
            : items?.leading ??
                  mirrored(
                    Rect.fromLTWH(
                      _margin + widget.leadingInset,
                      top,
                      leadingText.isEmpty
                          ? _controlSize
                          : _textButtonWidth(leadingText),
                      widget.height,
                    ),
                  );
        final titleRect = title == null
            ? null
            : items?.title ??
                  Rect.fromLTRB(
                    titleInset - clusterLeft,
                    top,
                    width + clusterRight - titleInset,
                    top + widget.height,
                  );
        return Stack(
          children: [
            if (titleRect != null)
              Positioned.fromRect(
                rect: titleRect,
                child: Semantics(
                  container: true,
                  header: true,
                  label: title,
                  child: const SizedBox.expand(),
                ),
              ),
            if (leadingRect != null)
              Positioned.fromRect(
                rect: leadingRect,
                child: Semantics(
                  container: true,
                  button: true,
                  label: leadingText!.isEmpty
                      ? localizations.backButtonTooltip
                      : leadingText,
                  onTap: widget.onLeadingTap,
                  child: item,
                ),
              ),
            for (var i = 0; i < actions.length; i++)
              Positioned.fromRect(
                rect:
                    (items != null && i < items.actions.length
                        ? items.actions[i]
                        : null) ??
                    mirrored(laidOut[i]),
                child: Semantics(
                  container: true,
                  button: true,
                  label: actions[i].effectiveLabel,
                  onTap: () => _activate(i),
                  child: item,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Where the bar lays [actions] out, about: in from its trailing end, as
  /// wide as [_titleInset] reckons them.
  List<Rect> _actionRects(
    List<AdaptiveAppBarAction> actions, {
    required double width,
    required double top,
  }) {
    final rects = List<Rect>.filled(actions.length, Rect.zero);
    var right = width - _margin;
    for (var i = actions.length - 1; i >= 0; i--) {
      if (i < actions.length - 1 &&
          actions[i].spacerAfter == ToolbarSpacerType.fixed) {
        right -= 12;
      }
      final actionWidth = _actionWidth(actions[i]);
      rects[i] = Rect.fromLTWH(
        right - actionWidth,
        top,
        actionWidth,
        widget.height,
      );
      right -= actionWidth;
    }
    return rects;
  }

  /// Taps action [index] as a finger would: one with a menu opens it, the
  /// native one, or Flutter's where the native bar cannot.
  Future<void> _activate(int index) async {
    final action = widget.actions![index];
    if (!action.hasMenu) {
      widget.onActionTap?.call(index);
      return;
    }
    bool? opened;
    try {
      opened = await _channel?.invokeMethod<bool>('activateAction', {
        'index': index,
      });
    } on MissingPluginException {
      opened = false;
    } on PlatformException {
      opened = false;
    }
    if (opened != true && mounted) action.press(context);
  }

  static const _margin = 16.0;
  static const _gap = 8.0;

  /// Where the bar's controls start: 16 points from its edge, or from the
  /// iPhone Duo's status cluster at that edge.
  static double _edgeInset(double cluster) => cluster + _margin;

  /// How far [IOS26NativeToolbar.titleWidget] keeps from both sides of the
  /// bar: 16 points from its edges or the status cluster at them, and 8 from
  /// the controls, the same on both sides so it stays centred.
  double _titleInset(double clusterLeft, double clusterRight) {
    final leadingText = widget.leadingText;
    final reservesLeading =
        widget.reservesLeading ??
        (widget.leading != null || leadingText != null);
    final leadingWidth = !reservesLeading
        ? 0.0
        : widget.leading == null && leadingText != null
        ? _textButtonWidth(leadingText)
        : _controlSize;
    final leading =
        _edgeInset(clusterLeft) +
        widget.leadingInset +
        (reservesLeading ? leadingWidth + _gap : 0);
    final actions = widget.actions ?? const <AdaptiveAppBarAction>[];
    var actionsWidth = 0.0;
    for (final action in actions) {
      actionsWidth += _actionWidth(action);
      if (action.spacerAfter != ToolbarSpacerType.none) actionsWidth += 12;
    }
    final trailing =
        _edgeInset(clusterRight) + (actions.isEmpty ? 0 : actionsWidth + _gap);
    return math.max(leading, trailing);
  }

  static const _controlSize = 44.0;

  /// About as wide as the system draws [action]'s bar button.
  static double _actionWidth(AdaptiveAppBarAction action) {
    final title = action.title;
    final iconOnly =
        action.iosSymbol != null ||
        action.icon != null ||
        action.iconWidget != null ||
        title == null;
    return iconOnly ? _controlSize : _textButtonWidth(title);
  }

  /// About as wide as the system draws a bar button with [text].
  static double _textButtonWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return math.max(_controlSize, width + 28);
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('adaptive_platform_ui/ios26_toolbar_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    // Told of every change after this, but maybe laid out before it listened.
    channel.invokeMethod<Object?>('getItemFrames').then((frames) {
      if (mounted && identical(channel, _channel)) _onItemFrames(frames);
    }, onError: (Object _) {});
    _lastIsDark = _isDark;
    _lastTint = widget.tintColor != null
        ? _colorToARGB(widget.tintColor!)
        : null;
    _lastActions = widget.actions != null ? List.of(widget.actions!) : null;
  }

  void _onItemFrames(Object? frames) {
    if (frames is! Map) return;
    final actions = frames['actions'];
    _items.value = (
      actions: actions is List
          ? [for (final frame in actions) _rectOf(frame)]
          : const [],
      leading: _rectOf(frames['leading']),
      title: _rectOf(frames['title']),
    );
  }

  static Rect? _rectOf(Object? frame) {
    if (frame is! Map) return null;
    final x = frame['x'], y = frame['y'];
    final width = frame['width'], height = frame['height'];
    if (x is! num || y is! num || width is! num || height is! num) return null;
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'itemFramesChanged':
        _onItemFrames(call.arguments);
        break;
      case 'onLeadingTapped':
        widget.onLeadingTap?.call();
        break;
      case 'onMenuItemTapped':
        if (call.arguments is Map) {
          final args = call.arguments as Map;
          final actionIndex = args['action'] as int?;
          final itemIndex = args['item'] as int?;
          final actions = widget.actions;
          if (actions != null &&
              actionIndex != null &&
              itemIndex != null &&
              actionIndex >= 0 &&
              actionIndex < actions.length) {
            actions[actionIndex].selectMenuItem(itemIndex);
          }
        }
        break;
      case 'onActionTapped':
        if (call.arguments is Map) {
          final index = (call.arguments as Map)['index'] as int?;
          if (index != null) widget.onActionTap?.call(index);
        }
        break;
    }
  }

  Widget _buildFallbackToolbar() {
    return CupertinoNavigationBar(
      middle:
          widget.titleWidget ??
          (widget.title != null ? Text(widget.title!) : null),
      leading: widget.leading,
      trailing: widget.actions != null && widget.actions!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.actions!.map((action) {
                return Builder(
                  builder: (context) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => action.press(context),
                    child: action.wrapWithBadge(
                      action.icon != null
                          ? Icon(action.icon)
                          : Text(action.title ?? ''),
                    ),
                  ),
                );
              }).toList(),
            )
          : null,
    );
  }
}
