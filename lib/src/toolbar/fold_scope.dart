import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

/// The fold of an iPhone Duo, from the `AdaptiveToolbarHost` above: iOS does
/// not report it in `MediaQuery.displayFeatures`, as Android does.
///
/// Only where the fold runs, not how far the device is open: pages that lay
/// themselves out around the fold are not built again as the angle changes.
class FoldScope extends InheritedModel<String> {
  const FoldScope({
    required this.hinge,
    this.crease,
    required super.child,
    super.key,
  });

  /// Where the fold runs in the window, while the device is partly open.
  final Rect? hinge;

  /// Where the fold runs through the window whether the device lies flat or
  /// is partly open ([creaseFrom]); null where none does.
  final Rect? crease;

  static const String _hingeAspect = 'hinge';
  static const String _creaseAspect = 'crease';

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

  /// Where the fold of [fold] runs through a window of [size], whether the
  /// device lies flat or is partly open: the iPhone Duo's division, which
  /// the system reports while it is inactive (the device flat) too.
  ///
  /// Only one that divides the window counts: it runs nearly all the way
  /// through it, not along its edge. A reading from the previous pose, which
  /// can still be around while the device rotates, folds or unfolds, has its
  /// division elsewhere; so has a Split View pane that ends at the fold. None
  /// on a device without a hinge, and until the system has reported where
  /// the fold is, a moment after launch and after each pose change.
  static Rect? creaseFrom(FoldableData? fold, Size size) {
    if (fold == null || !fold.isFoldable) return null;
    for (final region in fold.regions) {
      if (region.kind == ReservedRegionKind.division &&
          _divides(region.bounds, size)) {
        return region.bounds;
      }
    }
    return null;
  }

  /// Whether [bounds] runs through a window of [size]: inside it, give or
  /// take a point, along most of its length, and away from its edges.
  static bool _divides(Rect bounds, Size size) {
    if (bounds.longestSide <= 0 ||
        bounds.left < -1 ||
        bounds.top < -1 ||
        bounds.right > size.width + 1 ||
        bounds.bottom > size.height + 1) {
      return false;
    }
    final down = bounds.height >= bounds.width;
    final length = down ? bounds.height : bounds.width;
    final across = down ? size.width : size.height;
    final at = down ? bounds.center.dx : bounds.center.dy;
    return length >= (down ? size.height : size.width) * 0.9 &&
        at > 1 &&
        at < across - 1;
  }

  /// [hinge] of the scope around [context].
  static Rect? hingeOf(BuildContext context) =>
      InheritedModel.inheritFrom<FoldScope>(
        context,
        aspect: _hingeAspect,
      )?.hinge;

  /// The fold of a partly open foldable, in window coordinates: the iPhone
  /// Duo's from the toolbar host, an Android hinge or half-opened fold from
  /// the media query. Null while the device lies flat or has no fold; see
  /// [creaseOf] for where the fold runs then.
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

  /// Where a fold runs through the window, in window coordinates, whether
  /// the device lies flat or is partly open ([foldOf]): for a layout that
  /// keeps to the two halves of an unfolded display, such as two columns
  /// that meet at the fold rather than beside it. The iPhone Duo's from the
  /// toolbar host ([creaseFrom]), an Android fold or hinge in any state from
  /// the media query. Null on a display without one, such as the iPhone
  /// Duo's cover display.
  static Rect? creaseOf(BuildContext context) {
    final fold = foldOf(context);
    if (fold != null) return fold;
    final crease = InheritedModel.inheritFrom<FoldScope>(
      context,
      aspect: _creaseAspect,
    )?.crease;
    if (crease != null) return crease;
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if ((feature.type == DisplayFeatureType.fold ||
              feature.type == DisplayFeatureType.hinge) &&
          feature.bounds.longestSide > 0) {
        return feature.bounds;
      }
    }
    return null;
  }

  @override
  bool updateShouldNotify(FoldScope oldWidget) =>
      hinge != oldWidget.hinge || crease != oldWidget.crease;

  @override
  bool updateShouldNotifyDependent(
    FoldScope oldWidget,
    Set<String> dependencies,
  ) =>
      (dependencies.contains(_hingeAspect) && hinge != oldWidget.hinge) ||
      (dependencies.contains(_creaseAspect) && crease != oldWidget.crease);
}
