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
/// The fold is in window coordinates (`FoldScope.foldOf`), so the panes
/// line up with it only for a page that fills the window, such as a full
/// screen player.
class AdaptiveTwoPane extends StatelessWidget {
  const AdaptiveTwoPane({
    required this.start,
    this.end,
    this.direction = Axis.horizontal,
    this.proportion = 0.5,
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

  /// Whether a fold runs across the window here, as on a foldable standing
  /// on a table, so a page can offer what goes below it.
  static bool hasFoldAcross(BuildContext context) {
    final fold = FoldScope.foldOf(context);
    return fold != null && fold.width > fold.height;
  }

  @override
  Widget build(BuildContext context) {
    final fold = end == null ? null : FoldScope.foldOf(context);
    final across = fold == null
        ? direction == Axis.vertical
        : fold.width > fold.height;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return CustomMultiChildLayout(
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

class _TwoPaneLayout extends MultiChildLayoutDelegate {
  _TwoPaneLayout({
    required this.fold,
    required this.across,
    required this.proportion,
    required this.rtl,
  });

  final Rect? fold;
  final bool across;
  final double proportion;
  final bool rtl;

  @override
  void performLayout(Size size) {
    if (!hasChild(_Pane.end)) {
      layoutChild(_Pane.start, BoxConstraints.tight(size));
      positionChild(_Pane.start, Offset.zero);
      return;
    }
    final extent = across ? size.height : size.width;
    final fold = this.fold;
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
