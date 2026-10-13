import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lets the page's scroll view run underneath the bars that float over it,
/// like a UIKit scroll view with content insets: at rest its content starts
/// below [top] and ends above [bottom], and as it scrolls it passes
/// underneath both. For a page laid out under the fixed iOS 26 toolbar and a
/// floating tab bar.
///
/// It works for any vertical [ScrollView] (a list, a grid, a custom scroll
/// view) that scrolls with the [PrimaryScrollController], whatever padding
/// the scroll view has, and that starts at the top of [child]: see
/// [appliesTo]. Lay [child] out from the top of the page, under the bars.
/// Not for a [SingleChildScrollView], which keeps its offset within its
/// content: add the bars to its padding instead.
class AdaptiveScrollInsets extends StatefulWidget {
  /// Room the bars take at the top (the toolbar) and at the bottom (the tab bar or the home indicator).
  final double top;
  final double bottom;
  final Widget child;

  const AdaptiveScrollInsets({
    required this.top,
    required this.bottom,
    required this.child,
    super.key,
  });

  /// Whether [child] starts with a scroll view that this can inset: vertical,
  /// scrolling with the primary scroll controller, and at the top of [child].
  /// It looks through widgets that only wrap their child (padding, safe
  /// areas, inherited widgets, `Expanded`) and into the first child of a
  /// column that starts at the top. A shrink-wrapped scroll view counts too,
  /// as long as it is given all the room: it then fills it like any other.
  static bool appliesTo(Widget child) => switch (child) {
    ScrollView(:final controller, :final primary, :final scrollDirection) =>
      controller == null &&
          primary != false &&
          scrollDirection == Axis.vertical,
    SingleChildScrollView() => false,
    Flex(
      :final direction,
      :final children,
      :final mainAxisAlignment,
      :final verticalDirection,
    ) =>
      direction == Axis.vertical &&
          verticalDirection == VerticalDirection.down &&
          mainAxisAlignment == MainAxisAlignment.start &&
          children.isNotEmpty &&
          children.first is Flexible &&
          appliesTo(children.first),
    SafeArea(:final child) => appliesTo(child),
    KeyedSubtree(:final child) => appliesTo(child),
    // Wrappers that lay their child out where they are: padding, decoration,
    // inherited data (`MediaQuery`, `ScrollConfiguration`, `Expanded`).
    Padding(:final child?) ||
    ColoredBox(:final child?) ||
    DecoratedBox(:final child?) ||
    RepaintBoundary(:final child?) ||
    ProxyWidget(:final child) => appliesTo(child),
    _ => false,
  };

  @override
  State<AdaptiveScrollInsets> createState() => _AdaptiveScrollInsetsState();
}

class _AdaptiveScrollInsetsState extends State<AdaptiveScrollInsets> {
  late final _InsetScrollController _controller = _InsetScrollController(
    top: widget.top,
    bottom: widget.bottom,
  );

  @override
  void didUpdateWidget(AdaptiveScrollInsets oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.updateInsets(top: widget.top, bottom: widget.bottom);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      // On every platform, so that the page's scroll view always picks it up.
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}

class _InsetScrollController extends ScrollController {
  double top;
  double bottom;

  _InsetScrollController({required this.top, required this.bottom});

  void updateInsets({required double top, required double bottom}) {
    if (top == this.top && bottom == this.bottom) return;
    final oldTop = this.top;
    this.top = top;
    this.bottom = bottom;
    // The scroll views lay out again, with the new range. One not laid out yet,
    // such as on a page that came in covered, has no range to update: it only
    // moves to where it now rests.
    for (final position in positions) {
      if (position.hasContentDimensions) {
        position.notifyListeners();
      } else if (position.pixels == -oldTop) {
        position.correctPixels(-top);
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _InsetScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

/// Scrolls from `-top`, where the content rests below the top bar, to where its end clears the bottom bar.
class _InsetScrollPosition extends ScrollPositionWithSingleContext {
  final _InsetScrollController controller;

  /// The start of the scroll range at the last layout, to keep a page that rests at its top there when the insets
  /// change, e.g. on rotation.
  double? _lastMin;

  _InsetScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
    super.debugLabel,
  }) : super(initialPixels: -controller.top);

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final min = minScrollExtent - controller.top;
    // Content that overflows the viewport scrolls until its end clears the bottom inset. Content that fits may still
    // reach under the bars once moved down by the top inset, so it gets the scrolling that takes.
    final contentExtent = maxScrollExtent > minScrollExtent
        ? null
        : _contentExtent();
    final max = contentExtent == null
        ? maxScrollExtent + controller.bottom
        : math.max(
            min,
            minScrollExtent +
                contentExtent +
                controller.bottom -
                viewportDimension,
          );
    final lastMin = _lastMin;
    final keepAtTop =
        lastMin != null && lastMin != min && (pixels - lastMin).abs() < 0.5;
    if (keepAtTop) correctPixels(min);
    _lastMin = min;
    final accepted = super.applyContentDimensions(min, math.max(min, max));
    // Moved: the viewport lays out once more at the new offset.
    return accepted && !keepAtTop;
  }

  /// How far the content reaches along the scroll axis, read from the viewport that is laying out right now.
  double? _contentExtent() {
    final root = context.notificationContext?.findRenderObject();
    if (root == null) return null;
    RenderAbstractViewport? viewport;
    void visit(RenderObject object) {
      if (viewport != null) return;
      if (object is RenderAbstractViewport) {
        viewport = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    final found = viewport;
    if (found is! RenderViewportBase) return null;
    var extent = 0.0;
    for (
      var sliver = found.firstChild;
      sliver != null;
      sliver = found.childAfter(sliver)
    ) {
      extent += sliver.geometry?.scrollExtent ?? 0;
    }
    return extent;
  }
}
