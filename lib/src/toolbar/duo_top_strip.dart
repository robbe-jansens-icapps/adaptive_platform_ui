import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import '../widgets/ios26/ios26_glass_capsule.dart';
import 'duo_vertical_bar.dart';

/// Height of the navigation bar in the strip, as elsewhere.
const double kDuoTopStripBarHeight = 44.0;

/// Room kept for the camera and status cluster at the right end of the strip
/// until the system has reported where they are.
const double kDuoStatusClusterFallbackWidth = 120.0;

/// The iPhone Duo inner display held upright: the hardware strip runs along
/// the top of the window, and the system sets the navigation bar in it, beside
/// the camera and status cluster, rather than below it.
@immutable
class DuoTopStrip {
  const DuoTopStrip({
    required this.height,
    this.clusterLeft = 0,
    this.clusterRight = 0,
  });

  /// Height of the strip: the window's top inset.
  final double height;

  /// Room the camera and status cluster take at the left end of the bar.
  final double clusterLeft;

  /// Room the camera and status cluster take at the right end of the bar.
  final double clusterRight;

  /// Top of the bar: centred where the vertical bar's first control is in
  /// the other poses, level with the status cluster.
  static const double barTop =
      kDuoBarEdgeMargin +
      IOS26GlassCapsule.width / 2 -
      kDuoTopStripBarHeight / 2;

  static const double barBottom = barTop + kDuoTopStripBarHeight;

  /// How far the bar reaches below the strip, which the page's content clears.
  double get overhang => math.max(0, barBottom - height);

  /// This strip over a part of the window that reaches only one of its sides,
  /// such as a column of a split view: the cluster at the other side is not
  /// over it.
  DuoTopStrip within({required bool left, required bool right}) => DuoTopStrip(
    height: height,
    clusterLeft: left ? clusterLeft : 0,
    clusterRight: right ? clusterRight : 0,
  );

  /// The strip of a window, or null where the bar stays below the top inset:
  /// on any device without a hinge, and on the iPhone Duo wherever its strip
  /// is at a side ([DuoLayout.barSide]).
  static DuoTopStrip? resolve({
    required EdgeInsets viewPadding,
    required Size size,
    required FoldableData? fold,
  }) {
    if (fold == null || !fold.isFoldable) return null;
    if (viewPadding.top == 0 || viewPadding.left > 0 || viewPadding.right > 0) {
      return null;
    }
    // A reading from the previous pose can still be around while the device
    // rotates; its regions lie outside this window.
    final regions = fold.regions.where(
      (r) =>
          r.kind == ReservedRegionKind.occlusion &&
          r.isActive &&
          r.bounds.right <= size.width + 1 &&
          r.bounds.bottom <= size.height + 1,
    );
    if (regions.isEmpty) {
      return DuoTopStrip(
        height: viewPadding.top,
        clusterRight: kDuoStatusClusterFallbackWidth,
      );
    }
    var left = 0.0;
    var right = 0.0;
    for (final region in regions) {
      final bounds = region.bounds;
      if (bounds.top >= viewPadding.top) continue;
      if (bounds.center.dx < size.width / 2) {
        left = math.max(left, bounds.right);
      } else {
        right = math.max(right, size.width - bounds.left);
      }
    }
    return DuoTopStrip(
      height: viewPadding.top,
      clusterLeft: left,
      clusterRight: right,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DuoTopStrip &&
      other.height == height &&
      other.clusterLeft == clusterLeft &&
      other.clusterRight == clusterRight;

  @override
  int get hashCode => Object.hash(height, clusterLeft, clusterRight);

  @override
  String toString() =>
      'top strip ${height.toStringAsFixed(0)}pt (cluster '
      '${clusterLeft.toStringAsFixed(0)}/${clusterRight.toStringAsFixed(0)})';
}

/// Hands the [DuoTopStrip] down to the bars, so the fixed toolbar, a page's
/// own bar and the page body agree on where the bar is.
class DuoTopStripScope extends InheritedWidget {
  const DuoTopStripScope({
    super.key,
    required this.strip,
    required super.child,
  });

  /// The strip in effect, or null where the bar stays below the top inset.
  final DuoTopStrip? strip;

  /// The nearest scope, or null when there is none. Tells "no scope" apart
  /// from a scope without a strip.
  static DuoTopStripScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoTopStripScope>();

  /// The strip in effect here; null without a scope.
  static DuoTopStrip? of(BuildContext context) => maybeOf(context)?.strip;

  @override
  bool updateShouldNotify(DuoTopStripScope oldWidget) =>
      strip != oldWidget.strip;
}
