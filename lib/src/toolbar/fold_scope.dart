import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

/// The fold of an iPhone Duo that is partly open, from the
/// `AdaptiveToolbarHost` above: iOS does not report it in
/// `MediaQuery.displayFeatures`, as Android does.
///
/// Only where the fold runs, not how far the device is open: pages that lay
/// themselves out around the fold are not built again as the angle changes.
class FoldScope extends InheritedWidget {
  const FoldScope({required this.hinge, required super.child, super.key});

  /// Where the fold runs in the window, while the device is partly open.
  final Rect? hinge;

  /// The fold of [fold] to lay out around: none while the device lies flat
  /// or is closed. The hinge status is the one to trust: the fold region can
  /// still read active for a moment after the device lies flat.
  static Rect? hingeFrom(FoldableData? fold) {
    if (fold == null || !fold.isPartiallyOpen) return null;
    for (final division in fold.activeDivisions) {
      if (division.bounds.longestSide > 0) return division.bounds;
    }
    return null;
  }

  static Rect? hingeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FoldScope>()?.hinge;

  /// The fold of a partly open foldable, in window coordinates: the iPhone
  /// Duo's from the toolbar host, an Android hinge or half-opened fold from
  /// the media query. Null while the device lies flat or has no fold.
  static Rect? foldOf(BuildContext context) {
    final hinge = hingeOf(context);
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

  @override
  bool updateShouldNotify(FoldScope oldWidget) => hinge != oldWidget.hinge;
}
