import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../toolbar/fold_scope.dart';

/// Two panes of a page that fills the window, laid out around the fold of a
/// partly open foldable as Material's two pane layouts and the system's
/// apps are: on either side of a fold that runs down the window (the device
/// held as a book), and above and below one that runs across it (the device
/// standing on a table, a video above the fold and its controls or chat
/// below). Without a fold the panes share the window along [direction] by
/// [proportion].
///
/// Without [end], [start] fills the window, fold or not. Both keep their
/// state as the device folds and unfolds, and as [end] comes and goes.
///
/// The fold comes in window coordinates (`FoldScope.foldOf`) and the panes
/// meet it where it runs through this widget, wherever that is laid out: a
/// page that fills the window, such as a full screen player, or one in a
/// column of a split view or beside a bar. A fold that does not run through
/// it, such as one beside the column it is in, leaves the panes to
/// [proportion]. Where the widget is laid out is followed after each frame,
/// leaving out where it is only painted (a page sliding in): placed
/// somewhere else, it meets the fold a frame later.
class AdaptiveTwoPane extends StatelessWidget {
  const AdaptiveTwoPane({
    required this.start,
    this.end,
    this.direction = Axis.horizontal,
    this.proportion = 0.5,
    this.followsCrease = false,
    super.key,
  }) : assert(proportion > 0 && proportion < 1);

  /// The pane above or before the other: the leading one side by side.
  final Widget start;

  /// The pane below or after [start]; none leaves the window to [start].
  final Widget? end;

  /// How the panes share a window without a fold: side by side for
  /// [Axis.horizontal], one above the other for [Axis.vertical]. A fold
  /// decides this itself.
  final Axis direction;

  /// The part of a window without a fold that [start] takes.
  final double proportion;

  /// Whether the panes also meet where the fold runs while the device lies
  /// flat (`FoldScope.creaseOf`), as they do around a partly open fold: the
  /// two halves of the iPhone Duo's inner display, or of an unfolded Android
  /// foldable, each hold one. Without a partly open fold or such a crease,
  /// they share the window by [proportion]. Off by default.
  final bool followsCrease;

  /// Whether a fold runs across the window here, as on a foldable standing
  /// on a table, so a page can offer what goes below it.
  static bool hasFoldAcross(BuildContext context) {
    final fold = FoldScope.foldOf(context);
    return fold != null && fold.width > fold.height;
  }

  @override
  Widget build(BuildContext context) {
    final fold = end == null
        ? null
        : followsCrease
        ? FoldScope.creaseOf(context)
        : FoldScope.foldOf(context);
    final across = fold == null
        ? direction == Axis.vertical
        : fold.width > fold.height;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return _TwoPaneLayoutBox(
      delegate: _TwoPaneLayout(
        fold: fold,
        across: across,
        proportion: proportion,
        rtl: rtl,
      ),
      children: [
        LayoutId(
          id: _Pane.start,
          child: _PaneMediaQuery(
            alone: end == null,
            across: across,
            first: true,
            rtl: rtl,
            child: start,
          ),
        ),
        if (end case final end?)
          LayoutId(
            id: _Pane.end,
            child: _PaneMediaQuery(
              alone: false,
              across: across,
              first: false,
              rtl: rtl,
              child: end,
            ),
          ),
      ],
    );
  }
}

enum _Pane { start, end }

/// Takes the window's padding away on the side a pane shares with the
/// other: a pane above the fold has no home indicator below it.
class _PaneMediaQuery extends StatelessWidget {
  const _PaneMediaQuery({
    required this.alone,
    required this.across,
    required this.first,
    required this.rtl,
    required this.child,
  });

  final bool alone;
  final bool across;
  final bool first;
  final bool rtl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onLeft = first != rtl;
    return MediaQuery.removePadding(
      context: context,
      removeTop: !alone && across && !first,
      removeBottom: !alone && across && first,
      removeLeft: !alone && !across && !onLeft,
      removeRight: !alone && !across && onLeft,
      child: child,
    );
  }
}

/// Lays the panes out with [_TwoPaneLayout], telling it where it is laid out
/// in the window.
class _TwoPaneLayoutBox extends CustomMultiChildLayout {
  const _TwoPaneLayoutBox({
    required _TwoPaneLayout super.delegate,
    super.children,
  });

  @override
  _RenderTwoPane createRenderObject(BuildContext context) =>
      _RenderTwoPane(delegate: delegate as _TwoPaneLayout);
}

class _RenderTwoPane extends RenderCustomMultiChildLayoutBox {
  _RenderTwoPane({required _TwoPaneLayout super.delegate});

  /// Where this box was laid out in the window as of its last layout.
  Offset _origin = Offset.zero;

  bool _checkScheduled = false;

  bool get _hasFold => (delegate as _TwoPaneLayout).fold != null;

  @override
  void performLayout() {
    // Its ancestors place it after it is laid out: where they put it in the
    // last frame, or nowhere yet. Checked again once this frame is done.
    if (_hasFold) {
      _origin = _layoutOrigin();
      _scheduleCheck();
    }
    (delegate as _TwoPaneLayout).origin = _origin;
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Moved without being laid out again: a column that moved over.
    if (_hasFold) _scheduleCheck();
    super.paint(context, offset);
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (attached && _hasFold && _layoutOrigin() != _origin) markNeedsLayout();
    });
  }

  /// Where this box is laid out in the window: the offsets its ancestors lay
  /// it out at, leaving out what they only paint it moved by, such as a page
  /// sliding in, so the panes hold still in it.
  Offset _layoutOrigin() {
    var origin = Offset.zero;
    RenderObject child = this;
    for (
      var parent = child.parent;
      parent != null && parent is! RenderView;
      child = parent, parent = parent.parent
    ) {
      final data = child.parentData;
      if (data is BoxParentData) {
        origin += data.offset;
      } else if (child is! RenderBox || parent is! RenderBox) {
        // In a scroll view: where it is painted.
        final transform = Matrix4.identity();
        parent.applyPaintTransform(child, transform);
        origin += MatrixUtils.getAsTranslation(transform) ?? Offset.zero;
      }
    }
    return origin;
  }
}

class _TwoPaneLayout extends MultiChildLayoutDelegate {
  _TwoPaneLayout({
    required this.fold,
    required this.across,
    required this.proportion,
    required this.rtl,
  });

  /// The fold, in window coordinates.
  final Rect? fold;
  final bool across;
  final double proportion;
  final bool rtl;

  /// Where the box is laid out in the window, set by it before each layout.
  Offset origin = Offset.zero;

  @override
  void performLayout(Size size) {
    if (!hasChild(_Pane.end)) {
      layoutChild(_Pane.start, BoxConstraints.tight(size));
      positionChild(_Pane.start, Offset.zero);
      return;
    }
    final extent = across ? size.height : size.width;
    var fold = this.fold?.shift(-origin);
    // A fold beside this box, rather than through it, has nothing to say.
    if (fold != null &&
        (across
            ? fold.bottom <= 0 || fold.top >= extent
            : fold.right <= 0 || fold.left >= extent)) {
      fold = null;
    }
    final double from;
    final double to;
    if (fold == null) {
      from = to = extent * (rtl && !across ? 1 - proportion : proportion);
    } else {
      from = (across ? fold.top : fold.left).clamp(0.0, extent);
      to = (across ? fold.bottom : fold.right).clamp(from, extent);
    }
    if (across) {
      layoutChild(_Pane.start, BoxConstraints.tight(Size(size.width, from)));
      positionChild(_Pane.start, Offset.zero);
      layoutChild(
        _Pane.end,
        BoxConstraints.tight(Size(size.width, extent - to)),
      );
      positionChild(_Pane.end, Offset(0, to));
      return;
    }
    final leading = rtl ? _Pane.end : _Pane.start;
    final trailing = rtl ? _Pane.start : _Pane.end;
    layoutChild(leading, BoxConstraints.tight(Size(from, size.height)));
    positionChild(leading, Offset.zero);
    layoutChild(trailing, BoxConstraints.tight(Size(extent - to, size.height)));
    positionChild(trailing, Offset(to, 0));
  }

  @override
  bool shouldRelayout(_TwoPaneLayout oldDelegate) =>
      fold != oldDelegate.fold ||
      across != oldDelegate.across ||
      proportion != oldDelegate.proportion ||
      rtl != oldDelegate.rtl;
}
