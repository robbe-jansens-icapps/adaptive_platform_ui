import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../chrome/adaptive_chrome.dart';
import '../toolbar/duo_vertical_bar.dart';
import '../toolbar/fold_scope.dart';
import 'adaptive_glass.dart';
import 'ios26/ios26_popup_menu_button.dart';

/// Content anchored to the control that opened it, as a popover on iPad:
/// filters next to their button, a menu next to an action, a preview next
/// to a row.
///
/// Drawn by Flutter, it looks the same on every platform: in the custom
/// chrome's popover surface ([AdaptiveChrome.popoverBuilder]) or else on
/// [AdaptiveGlass]. It keeps to the half of a partly open foldable that
/// holds its anchor, clear of the fold, and out of the iPhone Duo's vertical
/// bar, opening beside it for a control in it. On a window narrower than
/// [compactWidth] it opens as a sheet from the bottom instead, as popovers
/// do on an iPhone.
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
  }) {
    final root = navigator != null
        ? Navigator.of(navigator.context, rootNavigator: true)
        : Navigator.of(anchor, rootNavigator: true);
    final rect = anchorRect ?? rectOf(anchor);
    final overlayContext = root.overlay?.context ?? root.context;
    final compact = MediaQuery.sizeOf(overlayContext).width < compactWidth;
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
  const _Surface({required this.sheet, required this.child, this.data});

  final bool sheet;
  final Widget child;
  final Object? data;

  @override
  Widget build(BuildContext context) {
    final content = Material(type: MaterialType.transparency, child: child);
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
    this.data,
  });

  final Object? data;
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
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

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
      child: CustomSingleChildLayout(
        delegate: _PopoverLayout(
          anchor: anchor,
          maxSize: maxSize,
          padding: MediaQuery.paddingOf(context),
          band: pose == null
              ? null
              : (onLeft: pose.onLeft, width: pose.bandWidth),
          fold: _foldOf(context),
        ),
        child: _Surface(
          sheet: false,
          data: data,
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
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      ),
    );
  }

  /// The fold of a partly open foldable: the iPhone Duo's from the toolbar
  /// host, an Android hinge or half-opened fold from the media query.
  static Rect? _foldOf(BuildContext context) {
    final hinge = FoldScope.hingeOf(context);
    if (hinge != null) return hinge;
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type == DisplayFeatureType.hinge ||
          (feature.type == DisplayFeatureType.fold &&
              feature.state == DisplayFeatureState.postureHalfOpened)) {
        return feature.bounds;
      }
    }
    return null;
  }
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
  });

  final Rect anchor;
  final Size maxSize;
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
    double clampX(double x) =>
        x.clamp(region.left, math.max(region.left, region.right - childSize.width));
    double clampY(double y) => y.clamp(
      region.top,
      math.max(region.top, region.bottom - childSize.height),
    );
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
      maxSize != oldDelegate.maxSize ||
      padding != oldDelegate.padding ||
      band != oldDelegate.band ||
      fold != oldDelegate.fold;
}

/// A menu of [items] in a popover: a row per item, which pops the popover
/// with its index.
class _PopoverMenu extends StatelessWidget {
  const _PopoverMenu({required this.items});

  final List<AdaptivePopupMenuEntry> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
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
