import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _scrolls =
    SemanticsAction.scrollUp.index |
    SemanticsAction.scrollDown.index |
    SemanticsAction.scrollLeft.index |
    SemanticsAction.scrollRight.index;

/// The node VoiceOver lands on for a finger at [point], in logical pixels, as
/// the iOS engine finds it (`search:` in SemanticsObject.mm): the first in
/// hit-test order that holds the point and has a label, value, hint or an
/// action other than scrolling. It passes over a platform view's node, which
/// has none of them, to what lies under the view.
SemanticsNode? voiceOverHit(WidgetTester tester, Offset point) {
  final root = _root(tester);
  final physical = point * tester.view.devicePixelRatio;
  return _search(root, physical, Matrix4.identity());
}

SemanticsNode? _search(SemanticsNode node, Offset point, Matrix4 parent) {
  final transform = parent.clone();
  if (node.transform case final own?) transform.multiply(own);
  if (!MatrixUtils.transformRect(transform, node.rect).contains(point)) {
    return null;
  }
  if (!node.mergeAllDescendantsIntoThisNode) {
    final children = <SemanticsNode>[];
    node.visitChildren((child) {
      children.add(child);
      return true;
    });
    // Hit-test order is paint order reversed.
    for (final child in children.reversed) {
      if (_search(child, point, transform) case final hit?) return hit;
    }
  }
  final data = node.getSemanticsData();
  final focusable =
      (data.flagsCollection.hasImplicitScrolling &&
          data.flagsCollection.isHidden) ||
      data.label.isNotEmpty ||
      data.value.isNotEmpty ||
      data.hint.isNotEmpty ||
      data.actions & ~_scrolls != 0;
  return focusable ? node : null;
}

/// Where [node] is on the screen, in logical pixels.
Rect globalRectOf(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform case final transform?) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  final ratio = tester.view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}

/// Every node in the tree.
List<SemanticsNode> allSemanticsNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(_root(tester));
  return nodes;
}

SemanticsNode _root(WidgetTester tester) =>
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!;
