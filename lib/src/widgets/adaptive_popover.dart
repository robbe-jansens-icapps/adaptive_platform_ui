import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../chrome/adaptive_chrome.dart';
import '../toolbar/duo_vertical_bar.dart';
import '../toolbar/fold_scope.dart';
import 'adaptive_glass.dart';
import 'ios26/ios26_popup_menu_button.dart';

/// Where a popover goes relative to the control that opens it.
enum AdaptivePopoverPlacement {
  /// Next to the control: below it, or above it where there is no room. On a
  /// window narrower than [AdaptivePopover.compactWidth] it opens as a sheet
  /// from the bottom instead, as popovers do on an iPhone.
  beside,

  /// In the control's place, on a window of any size: it grows out of the
  /// control and covers it, from the control's edge nearest the window's
  /// (one in a bar along the bottom opens upwards from it). For content a
  /// bar opens out of itself, such as a menu of everything behind a tab.
  over,
}

/// Content anchored to the control that opened it, as a popover on iPad:
/// filters next to their button, a menu next to an action, a preview next
/// to a row.
///
/// Drawn by Flutter, it looks the same on every platform: in the custom
/// chrome's popover surface ([AdaptiveChrome.popoverBuilder]) or else on
/// [AdaptiveGlass]. Its surface grows out of the control and shrinks back
/// into it, as the system's popovers and menus do, and its content fades in
/// as the surface opens. It keeps to the half of a partly open foldable that
/// holds its anchor, clear of the fold, and out of the iPhone Duo's vertical
/// bar, opening beside it for a control in it.
abstract final class AdaptivePopover {
  /// Narrower than this, a popover opens as a sheet.
  static const double compactWidth = 600;

  /// Room kept between the popover and its anchor, and the window's edges.
  static const double gap = 8;

  /// Shows [builder]'s content anchored to [anchor], a control on screen,
  /// or to [anchorRect] in global coordinates. Resolves to what the content
  /// pops with.
  ///
  /// [navigator] is for content opened from a control above the navigator,
  /// such as the toolbar host's bars: the page's navigator, whose root
  /// navigator shows it.
  static Future<T?> show<T>({
    required BuildContext anchor,
    required WidgetBuilder builder,
    Rect? anchorRect,
    NavigatorState? navigator,
    Size maxSize = const Size(400, 560),
    bool barrierDismissible = true,
    Color barrierColor = const Color(0x14000000),
    String? barrierLabel,
    Object? chromeData,
    AdaptivePopoverPlacement placement = AdaptivePopoverPlacement.beside,
  }) {
    final root = navigator != null
        ? Navigator.of(navigator.context, rootNavigator: true)
        : Navigator.of(anchor, rootNavigator: true);
    final rect = anchorRect ?? rectOf(anchor);
    final overlayContext = root.overlay?.context ?? root.context;
    final compact =
        placement == AdaptivePopoverPlacement.beside &&
        MediaQuery.sizeOf(overlayContext).width < compactWidth;
    if (compact || rect == null) {
      return showModalBottomSheet<T>(
        context: root.context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: const Color(0x00000000),
        elevation: 0,
        barrierLabel: barrierLabel,
        builder: (context) => _Surface(
          sheet: true,
          data: chromeData,
          child: SafeArea(top: false, child: builder(context)),
        ),
      );
    }
    final overlay = overlayContext.findRenderObject() as RenderBox?;
    final local = overlay == null
        ? rect
        : Rect.fromPoints(
            overlay.globalToLocal(rect.topLeft),
            overlay.globalToLocal(rect.bottomRight),
          );
    return root.push<T>(
      _PopoverRoute<T>(
        anchor: local,
        builder: builder,
        maxSize: maxSize,
        dismissible: barrierDismissible,
        color: barrierColor,
        data: chromeData,
        placement: placement,
        label:
            barrierLabel ??
            MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
      ),
    );
  }

  /// Shows [items] as a menu anchored to [anchor], and resolves to the index
  /// of the item picked, or null.
  static Future<int?> showMenu({
    required BuildContext anchor,
    required List<AdaptivePopupMenuEntry> items,
    Rect? anchorRect,
    NavigatorState? navigator,
    Object? chromeData,
  }) {
    return show<int>(
      anchor: anchor,
      anchorRect: anchorRect,
      navigator: navigator,
      chromeData: chromeData,
      maxSize: const Size(320, 560),
      builder: (context) => _PopoverMenu(items: items),
    );
  }

  /// Where the control at [context] is on screen, in global coordinates, to
  /// anchor a popover or a share sheet to. Null before it is laid out.
  static Rect? rectOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// The surface a popover or its sheet sits on: the custom chrome's, or
/// glass.
class _Surface extends StatelessWidget {
  const _Surface({required this.sheet, this.child, this.data});

  final bool sheet;

  /// The content; none for the surface of a popover, which grows on its own
  /// with the content drawn over it.
  final Widget? child;
  final Object? data;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    final content = child == null
        ? const SizedBox.expand()
        : Material(type: MaterialType.transparency, child: child);
    final builder = AdaptiveChromeScope.chromeOf(context)?.popoverBuilder;
    if (builder != null) {
      return builder(
        context,
        AdaptivePopoverSpec(sheet: sheet, data: data),
        content,
      );
    }
    return AdaptiveGlass(
      shape: RoundedRectangleBorder(
        borderRadius: sheet
            ? const BorderRadius.vertical(top: Radius.circular(28))
            : BorderRadius.circular(20),
      ),
      child: content,
    );
  }
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.maxSize,
    required this.dismissible,
    required this.color,
    required this.label,
    required this.placement,
    this.data,
  });

  final Object? data;
  final AdaptivePopoverPlacement placement;
  final Rect anchor;
  final WidgetBuilder builder;
  final Size maxSize;
  final bool dismissible;
  final Color color;
  final String label;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color? get barrierColor => color;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final pose = DuoPoseScope.of(context);
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: false,
      child: _PopoverMorph(
        animation: animation,
        anchor: anchor,
        reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
        layout: _PopoverLayout(
          anchor: anchor,
          maxSize: maxSize,
          placement: placement,
          padding: MediaQuery.paddingOf(context),
          band: pose == null
              ? null
              : (onLeft: pose.onLeft, width: pose.bandWidth),
          fold: FoldScope.foldOf(context),
        ),
        surface: _Surface(sheet: false, data: data),
        content: Material(
          type: MaterialType.transparency,
          child: Builder(builder: builder),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

}

/// Places a popover next to its anchor: below it, or above it when there is
/// no room below, centred on it and kept on screen, out of the iPhone Duo's
/// vertical bar and on the anchor's side of a fold. For an anchor in the
/// vertical bar it opens beside the bar instead.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({
    required this.anchor,
    required this.maxSize,
    required this.padding,
    required this.band,
    required this.fold,
    this.placement = AdaptivePopoverPlacement.beside,
  });

  final Rect anchor;
  final Size maxSize;
  final AdaptivePopoverPlacement placement;
  final EdgeInsets padding;
  final ({bool onLeft, double width})? band;
  final Rect? fold;

  static const double _gap = AdaptivePopover.gap;

  /// Where the popover may go in a window of [size].
  Rect _region(Size size) {
    var region = Rect.fromLTRB(
      math.max(padding.left, _gap),
      math.max(padding.top, _gap),
      size.width - math.max(padding.right, _gap),
      size.height - math.max(padding.bottom, _gap),
    );
    final band = this.band;
    if (band != null) {
      region = band.onLeft
          ? Rect.fromLTRB(
              math.max(region.left, band.width + _gap),
              region.top,
              region.right,
              region.bottom,
            )
          : Rect.fromLTRB(
              region.left,
              region.top,
              math.min(region.right, size.width - band.width - _gap),
              region.bottom,
            );
    }
    // Over its control it may take the control's own room above and below,
    // which a bar along the top or bottom has within the window's padding.
    if (placement == AdaptivePopoverPlacement.over) {
      region = Rect.fromLTRB(
        region.left,
        math.min(region.top, anchor.top),
        region.right,
        math.max(region.bottom, anchor.bottom),
      );
    }
    final fold = this.fold;
    if (fold != null) {
      if (fold.height >= fold.width) {
        region = anchor.center.dx < fold.center.dx
            ? Rect.fromLTRB(
                region.left,
                region.top,
                math.min(region.right, fold.left - _gap),
                region.bottom,
              )
            : Rect.fromLTRB(
                math.max(region.left, fold.right + _gap),
                region.top,
                region.right,
                region.bottom,
              );
      } else {
        region = anchor.center.dy < fold.center.dy
            ? Rect.fromLTRB(
                region.left,
                region.top,
                region.right,
                math.min(region.bottom, fold.top - _gap),
              )
            : Rect.fromLTRB(
                region.left,
                math.max(region.top, fold.bottom + _gap),
                region.right,
                region.bottom,
              );
      }
    }
    return region;
  }

  bool _inBand(Size size) {
    final band = this.band;
    if (band == null) return false;
    return band.onLeft
        ? anchor.center.dx <= band.width
        : anchor.center.dx >= size.width - band.width;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final region = _region(constraints.biggest);
    return BoxConstraints.loose(
      Size(
        math.max(0, math.min(maxSize.width, region.width)),
        math.max(0, math.min(maxSize.height, region.height)),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final region = _region(size);
    double clampX(double x) => x.clamp(
      region.left,
      math.max(region.left, region.right - childSize.width),
    );
    double clampY(double y) => y.clamp(
      region.top,
      math.max(region.top, region.bottom - childSize.height),
    );
    if (placement == AdaptivePopoverPlacement.over) {
      // From the control's edge nearest the window's: upwards from a bar
      // along the bottom, downwards from one along the top.
      final x = _inBand(size)
          ? (band!.onLeft ? region.left : region.right - childSize.width)
          : clampX(anchor.center.dx - childSize.width / 2);
      final upwards = anchor.center.dy > size.height / 2;
      return Offset(
        x,
        clampY(upwards ? anchor.bottom - childSize.height : anchor.top),
      );
    }
    if (_inBand(size)) {
      // Beside the vertical bar, level with the control.
      final x = band!.onLeft ? region.left : region.right - childSize.width;
      return Offset(x, clampY(anchor.center.dy - childSize.height / 2));
    }
    final x = clampX(anchor.center.dx - childSize.width / 2);
    final below = anchor.bottom + _gap;
    if (below + childSize.height <= region.bottom) return Offset(x, below);
    final above = anchor.top - _gap - childSize.height;
    if (above >= region.top) return Offset(x, above);
    // No room either way: where there is more, kept on screen.
    final roomBelow = region.bottom - anchor.bottom;
    final roomAbove = anchor.top - region.top;
    return Offset(x, clampY(roomBelow >= roomAbove ? below : above));
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      placement != oldDelegate.placement ||
      maxSize != oldDelegate.maxSize ||
      padding != oldDelegate.padding ||
      band != oldDelegate.band ||
      fold != oldDelegate.fold;
}

/// A popover's [surface] growing out of its anchor into the place
/// [layout] gives the [content], and shrinking back into it, with the
/// content fading in as the surface opens.
///
/// The content is laid out once, at its own size, and only clipped to the
/// growing surface, so it is not laid out again on every frame.
class _PopoverMorph extends MultiChildRenderObjectWidget {
  _PopoverMorph({
    required this.animation,
    required this.anchor,
    required this.layout,
    required this.reduceMotion,
    required Widget surface,
    required Widget content,
  }) : super(children: <Widget>[surface, content]);

  final Animation<double> animation;
  final Rect anchor;
  final _PopoverLayout layout;

  /// Fades the popover in and out in place instead.
  final bool reduceMotion;

  @override
  _RenderPopoverMorph createRenderObject(BuildContext context) =>
      _RenderPopoverMorph(
        animation: animation,
        anchor: anchor,
        layout: layout,
        reduceMotion: reduceMotion,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPopoverMorph renderObject,
  ) {
    renderObject
      ..animation = animation
      ..anchor = anchor
      ..placement = layout
      ..reduceMotion = reduceMotion;
  }
}

class _MorphParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPopoverMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MorphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MorphParentData> {
  _RenderPopoverMorph({
    required Animation<double> animation,
    required Rect anchor,
    required _PopoverLayout layout,
    required bool reduceMotion,
  }) : _animation = animation,
       _anchor = anchor,
       _layout = layout,
       _reduceMotion = reduceMotion;

  /// The surface overshoots its place a little and settles, as the system's
  /// popovers do; it closes without.
  static const Curve _grow = Cubic(0.2, 0.9, 0.3, 1.06);
  static const Curve _shrink = Curves.easeInCubic;

  /// The corners the content is clipped to while the surface grows.
  static const double _radius = 20;

  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    if (attached) _animation.removeListener(markNeedsLayout);
    _animation = value;
    if (attached) _animation.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  Rect _anchor;
  set anchor(Rect value) {
    if (value == _anchor) return;
    _anchor = value;
    markNeedsLayout();
  }

  _PopoverLayout _layout;
  set placement(_PopoverLayout value) {
    if (identical(value, _layout)) return;
    final relayout = value.shouldRelayout(_layout);
    _layout = value;
    if (relayout) markNeedsLayout();
  }

  bool _reduceMotion;
  set reduceMotion(bool value) {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    markNeedsLayout();
  }

  Rect _target = Rect.zero;
  Rect _surface = Rect.zero;

  final LayerHandle<ClipRRectLayer> _clip = LayerHandle<ClipRRectLayer>();
  final LayerHandle<TransformLayer> _transform = LayerHandle<TransformLayer>();
  final LayerHandle<OpacityLayer> _opacity = LayerHandle<OpacityLayer>();

  double get _t => _animation.value.clamp(0.0, 1.0);

  bool get _closing => _animation.status == AnimationStatus.reverse;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphParentData) {
      child.parentData = _MorphParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final surface = firstChild!;
    final content = childAfter(surface)!;
    content.layout(
      _layout.getConstraintsForChild(BoxConstraints.loose(size)),
      parentUsesSize: true,
    );
    final offset = _layout.getPositionForChild(size, content.size);
    (content.parentData! as _MorphParentData).offset = offset;
    _target = offset & content.size;
    final progress = (_closing ? _shrink : _grow).transform(_t);
    _surface = _reduceMotion ? _target : Rect.lerp(_anchor, _target, progress)!;
    surface.layout(
      BoxConstraints.tight(
        Size(math.max(0, _surface.width), math.max(0, _surface.height)),
      ),
    );
    (surface.parentData! as _MorphParentData).offset = _surface.topLeft;
  }

  /// Where the content grows from: the point of its place nearest the
  /// anchor.
  Offset get _origin => Offset(
    _anchor.center.dx.clamp(_target.left, _target.right),
    _anchor.center.dy.clamp(_target.top, _target.bottom),
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    final surface = firstChild!;
    final content = childAfter(surface)!;
    final t = _t;
    if (t == 0) {
      _clip.layer = null;
      _transform.layer = null;
      _opacity.layer = null;
      return;
    }
    final surfaceData = surface.parentData! as _MorphParentData;
    final contentData = content.parentData! as _MorphParentData;
    if (_reduceMotion) {
      context.paintChild(surface, offset + surfaceData.offset);
      _clip.layer = null;
      _transform.layer = null;
      _opacity.layer = context.pushOpacity(
        offset,
        (t * 255).round(),
        (context, offset) =>
            context.paintChild(content, offset + contentData.offset),
        oldLayer: _opacity.layer,
      );
      return;
    }
    context.paintChild(surface, offset + surfaceData.offset);
    final reveal = _closing
        ? Curves.easeIn.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0))
        : Curves.easeOut.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
    if (reveal == 0) {
      _clip.layer = null;
      _transform.layer = null;
      _opacity.layer = null;
      return;
    }
    final radius = math.min(_radius, _surface.shortestSide / 2);
    final scale = 0.92 + 0.08 * Curves.easeOut.transform(t);
    final origin = _origin;
    final matrix = Matrix4.identity()
      ..translateByDouble(origin.dx, origin.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      _surface,
      RRect.fromRectAndRadius(_surface, Radius.circular(radius)),
      (context, offset) {
        _transform.layer = context.pushTransform(
          needsCompositing,
          offset,
          matrix,
          (context, offset) {
            _opacity.layer = context.pushOpacity(
              offset,
              (reveal * 255).round(),
              (context, offset) =>
                  context.paintChild(content, offset + contentData.offset),
              oldLayer: _opacity.layer,
            );
          },
          oldLayer: _transform.layer,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestSelf(Offset position) => _surface.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Only the open popover's content takes taps; on its way in or out the
    // surface takes them, so they reach neither the content nor what is
    // behind it.
    if (_animation.status != AnimationStatus.completed) return false;
    final content = lastChild!;
    final data = content.parentData! as _MorphParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (result, transformed) =>
          content.hitTest(result, position: transformed),
    );
  }
}

/// A menu of [items] in a popover: a row per item, which pops the popover
/// with its index.
class _PopoverMenu extends StatelessWidget {
  const _PopoverMenu({required this.items});

  final List<AdaptivePopupMenuEntry> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                switch (items[i]) {
                  final AdaptivePopupMenuItem<dynamic> item => _row(
                    context,
                    item,
                    i,
                    textStyle,
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Divider(height: 1),
                  ),
                },
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AdaptivePopupMenuItem<dynamic> item,
    int index,
    TextStyle textStyle,
  ) {
    final color = !item.enabled
        ? textStyle.color?.withValues(alpha: 0.38)
        : item.isDestructive
        ? Theme.of(context).colorScheme.error
        : textStyle.color;
    final icon = switch (item.icon) {
      final IconData data => Icon(data, size: 20, color: color),
      final Widget widget => widget,
      _ => null,
    };
    return Semantics(
      button: true,
      enabled: item.enabled,
      selected: item.selected,
      child: InkWell(
        onTap: item.enabled ? () => Navigator.of(context).pop(index) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: textStyle.copyWith(color: color)),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: textStyle.copyWith(
                          fontSize: (textStyle.fontSize ?? 16) - 3,
                          color: color?.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              if (item.selected)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(Icons.check, size: 18, color: color),
                ),
              if (icon != null)
                Padding(padding: const EdgeInsets.only(left: 12), child: icon),
            ],
          ),
        ),
      ),
    );
  }
}
