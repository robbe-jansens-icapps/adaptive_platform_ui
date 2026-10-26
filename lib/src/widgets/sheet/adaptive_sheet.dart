import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../chrome/adaptive_chrome.dart';
import '../../chrome/scroll_edge_effect.dart' show AdaptiveBarBackdrop;
import '../../platform/platform_info.dart';
import '../../toolbar/duo_vertical_bar.dart';
import '../../toolbar/hosted_tab_bar.dart' show NativeAccessoryGlass;
import '../../toolbar/hosted_top_toolbar.dart'
    show kHostedToolbarBottomPadding, kHostedToolbarHeight;
import '../../toolbar/toolbar_blend.dart' show kToolbarItemSwapDuration;
import '../../toolbar/toolbar_chrome_scope.dart';
import '../../toolbar/toolbar_registry.dart';
import '../../utils/outside_layout.dart';
import '../../utils/size_reporter.dart';
import '../accessory_makes_way.dart';
import '../adaptive_accessory_scope.dart';
import '../adaptive_glass.dart';
import '../adaptive_scaffold.dart' show AdaptiveBottomBarInset;
import '../ios26/ios26_glass_surface.dart';
import '../material_tab_accessory.dart' show MaterialTabAccessoryLink;
import 'adaptive_sheet_detent.dart';

/// Moves an [AdaptiveSheet] between its detents and tells where it is.
class AdaptiveSheetController extends ChangeNotifier {
  _AdaptiveSheetState? _sheet;
  final ProxyAnimation _extent = ProxyAnimation(kAlwaysDismissedAnimation);

  /// The visible height of the sheet, from the bottom of its area, following
  /// every drag and animation.
  Animation<double> get extent => _extent;

  /// The detent the sheet rests at or is settling to; null until it shows.
  AdaptiveSheetDetent? get detent => _sheet?._target;

  /// Whether the sheet is shown as a side panel right now.
  bool get isSidePanel => _sheet?._metrics?.sidePanel ?? false;

  /// Springs the sheet to [detent], which need not be one of its detents.
  Future<void> animateTo(AdaptiveSheetDetent detent) =>
      _sheet?._settleTo(detent) ?? Future<void>.value();

  void _attach(_AdaptiveSheetState sheet) {
    _sheet = sheet;
    _extent.parent = sheet._extent;
  }

  void _detach(_AdaptiveSheetState sheet) {
    if (_sheet != sheet) return;
    _sheet = null;
    _extent.parent = kAlwaysDismissedAnimation;
  }

  void _onDetentChanged() => notifyListeners();
}

/// The radius of the top corners of a sheet that floats over its page with
/// the native chrome (iOS 26); those along the bottom follow the display's.
const double kAdaptiveSheetCornerRadius = 30;

/// A sheet that floats over the content of a page, like the ones in Find My
/// and Maps on iOS 26: a grabber, a [header] that stays in view, and [child]
/// below it, scrolled by the sheet when it does not fit.
///
/// Drag the grabber, the header or the content to move it between its
/// [detents]; a fling picks the next one. Place it over the page in a
/// `Stack`, filling the area it may cover: it keeps its content clear of the
/// bottom padding of that area (a floating tab bar), and stays below the top
/// padding.
///
/// - iOS: native Liquid Glass. Below [AdaptiveSheetDetent.large] the sheet
///   floats, inset, with corners concentric with the display, and grows edge
///   to edge at the large detent.
/// - Android: a Material 3 standard bottom sheet, with a drag handle.
///
/// From 600 points wide (iPad, the iPhone Duo inner display, tablets) it
/// becomes a floating panel along the leading edge, like Find My on iPad.
class AdaptiveSheet extends StatefulWidget {
  const AdaptiveSheet({
    super.key,
    required this.child,
    this.header,
    this.detents = const [
      AdaptiveSheetDetent.collapsed,
      AdaptiveSheetDetent.fitContent,
    ],
    this.initialDetent = AdaptiveSheetDetent.fitContent,
    this.controller,
    this.onDetentChanged,
    this.onSettled,
    this.sidePanel,
    this.sidePanelWidth = 380,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.floatingMargin,
    this.grabberSemanticsLabel = 'Sheet grabber',
    this.showsGrabber = true,
    this.scrollable = true,
    this.onDismissed,
    this.glassFill,
    this.contentDragsSheet = false,
    this.modal = false,
    this.keepsContentClearOfBars = false,
    this.opensFromAccessory = false,
    this.liftsAccessory = false,
    this.accessory,
    this.showsHeaderBackdrop = false,
  });

  /// The content below the header. It is laid out at its natural height and
  /// scrolled by the sheet when that does not fit, so it must not scroll
  /// itself.
  final Widget child;

  /// Stays in view at every detent, below the grabber: what the collapsed
  /// detent shows.
  final Widget? header;

  /// Where the sheet may come to rest. Drags and flings only pick these.
  final List<AdaptiveSheetDetent> detents;

  final AdaptiveSheetDetent initialDetent;
  final AdaptiveSheetController? controller;

  /// Called when the sheet starts settling at another detent.
  final ValueChanged<AdaptiveSheetDetent>? onDetentChanged;

  /// The part of the sheet's area the sheet covers once it rests: from the
  /// bottom while it floats over it, from the leading edge as a side panel.
  /// Reported as soon as it starts settling, so a map can move along.
  final ValueChanged<EdgeInsets>? onSettled;

  /// Whether to show the sheet as a panel along the leading edge. Null decides
  /// from the width: 600 points and up.
  final bool? sidePanel;

  final double sidePanelWidth;

  /// Around [child].
  final EdgeInsets padding;

  /// Where the floating iOS sheet sits in its area: how far it keeps from the
  /// left, the right and the bottom, to line it up with the page's own
  /// controls (the top is not used). The sheet then keeps no further room for
  /// the bottom padding of the area: its content ends [padding] above its
  /// bottom edge, as it does [padding] from its sides. By default the sheet
  /// floats 8 points from the sides, beyond the iPhone Duo vertical bar, and
  /// from the bottom, and its content stays clear of the bottom padding. It
  /// still grows edge to edge at the large detent.
  final EdgeInsets? floatingMargin;

  final String grabberSemanticsLabel;

  /// Whether to show the grabber. Without it the sheet keeps no room above
  /// its content either: the content's own padding decides where it starts.
  final bool showsGrabber;

  /// Whether [child] scrolls inside the sheet when it does not fit. When
  /// false it never scrolls, and a drag anywhere on the sheet moves the sheet.
  final bool scrollable;

  /// Lets the sheet be dragged down out of view, after which it calls this.
  /// Without it, a drag below the lowest detent springs back.
  final VoidCallback? onDismissed;

  /// Laid over the iOS glass, under the content (see
  /// [IOS26GlassSurface.fill]): a light, partly opaque one lets less of the
  /// page show through, so text on the sheet reads better over a busy page
  /// such as a map, while the glass keeps its edge and its blur. The Material
  /// sheet is opaque already and has none.
  final Color? glassFill;

  /// Whether content with nothing to scroll leaves every drag to the sheet,
  /// which then follows the finger at once rather than the content bouncing;
  /// and whether a sheet that can be dismissed follows a drag down on its
  /// content from its lowest detent all the way out, rather than moving one
  /// step and handing the rest of the drag to its content.
  final bool contentDragsSheet;

  /// Whether the sheet is the page of a popup route of its own: it then
  /// slides down out of view with the route as it goes, however it is popped
  /// (the barrier tapped, a button, back), and at its tallest stops below the
  /// toolbar the toolbar host draws over the page under it, which stays in
  /// sight above it.
  final bool modal;

  /// Whether, with a collapsed detent, only the header shows there, the
  /// content fading in as the sheet is pulled up, as with Find My; and
  /// whether, with tabs floating over its bottom, its content ends where they
  /// begin rather than running on under what they carry (a tab accessory on
  /// the sheet). For a sheet that holds the tabs at its smallest.
  final bool keepsContentClearOfBars;

  /// Whether the sheet is what the tab accessory on it opens into, where the
  /// tabs hold their accessory on the sheet
  /// (`AdaptiveTabAccessoryLayout.onSheet`), as a ride's controls open from
  /// its row above the tabs. At its collapsed detent only the accessory
  /// shows on its glass, above the tabs. Pulled up, or opened through the
  /// accessory's scope (`AdaptiveAccessoryScope.expansionOf`), the
  /// accessory makes way as the content fades in, and stops taking touches;
  /// a drag up on the accessory pulls the sheet up with it. Its content then
  /// runs on into the room the accessory takes, and ends where the tabs
  /// begin, as it would with no accessory, while the pages keep their
  /// padding. With the native iOS tab bar, and with the Material one, which
  /// holds the accessory in a band above its destinations
  /// (`AdaptiveScaffold` on Android); no effect on a side panel or with
  /// custom chrome. Turned off or on, the accessory eases in or
  /// out rather than jumping, as the sheet changes what it shows.
  final bool opensFromAccessory;

  /// Whether the tab accessory on the sheet
  /// (`AdaptiveTabAccessoryLayout.onSheet`) stands apart from the sheet's
  /// content while that lies above it, on a Liquid Glass capsule of its own,
  /// as an accessory floats above the tabs elsewhere: a station's details,
  /// say, above a ride's row. The capsule comes in as the content comes up
  /// above the accessory and goes as it goes down, and stays away where the
  /// content comes up into the accessory's place instead
  /// ([opensFromAccessory]). With the native iOS tab bar, along the bottom;
  /// the Material bar holds the accessory on a band of its own already, the
  /// sheet coming up from behind it. Off by default.
  final bool liftsAccessory;

  /// An accessory the sheet holds at its bottom itself, where no tab bar
  /// along the bottom holds the tab accessory on it
  /// ([AdaptiveTabAccessoryLayout.onSheet]): in the iPhone Duo's vertical bar
  /// pose, whose bar shows the tab accessory as a key, a ride's row on the
  /// map's sheet. It sits round with the sheet's corners, at the collapsed
  /// detent the sheet's glass around it alone. With [opensFromAccessory] the
  /// content comes up into its place as it makes way, and a drag on it moves
  /// the sheet; other content ends above it, and with [liftsAccessory] it
  /// stands apart on a capsule of its own. [AdaptiveAccessoryScope] tells it
  /// it is on a page's sheet, along the bottom. Floating sheets with the
  /// native chrome only: not on a side panel, on Android or with custom
  /// chrome. One with nothing to show takes no room.
  final Widget? accessory;

  /// Whether the content scrolls on under the grabber and the [header], as a
  /// page's content does under its bar, and they then get the bar's
  /// background as soon as it does: on iOS a frost in the colour of
  /// [glassFill] (white without one) with a hairline below
  /// ([AdaptiveBarBackdrop]), on Android the colour of a Material 3 app bar
  /// scrolled under. The content fades out within a few points of going
  /// under them. Off by default: the content ends below the header, fading
  /// out along its top edge once scrolled. Only for a [scrollable] sheet.
  final bool showsHeaderBackdrop;

  /// From this width on the sheet becomes a side panel by default.
  static const double sidePanelMinWidth = 600;

  @override
  State<AdaptiveSheet> createState() => _AdaptiveSheetState();
}

/// What the sheet lays itself out from.
@immutable
class _Metrics {
  const _Metrics({
    required this.size,
    required this.padding,
    required this.sidePanel,
    required this.material,
    required this.rtl,
    this.sides = EdgeInsets.zero,
    this.toolbar = 0,
    this.accessoryBand = 0,
    this.ownAccessory = 0,
    this.ownAccessoryRoom = 0,
  });

  final Size size;
  final EdgeInsets padding;
  final bool sidePanel;
  final bool material;
  final bool rtl;

  /// Room the sheet leaves below the top padding at its tallest: the toolbar
  /// the host draws over the page under a modal sheet, which stays in sight
  /// above it, dimmed, rather than the sheet going under it.
  final double toolbar;

  /// Room a floating sheet leaves at its sides: the band of the iPhone Duo
  /// vertical bar, which carries the tab bar and toolbar along that edge.
  final EdgeInsets sides;

  /// The part of the bottom padding that the tab accessory on the sheet
  /// takes, where the sheet opens from it
  /// ([AdaptiveSheet.opensFromAccessory]): its content runs on into it.
  final double accessoryBand;

  /// The band the sheet's own accessory ([AdaptiveSheet.accessory]) and the
  /// room around it take at the bottom of the sheet.
  final double ownAccessory;

  /// What the content keeps of [ownAccessory] below it: all of it, but where
  /// the content opens from the accessory and runs on into its place.
  final double ownAccessoryRoom;

  @override
  bool operator ==(Object other) =>
      other is _Metrics &&
      other.size == size &&
      other.padding == padding &&
      other.sidePanel == sidePanel &&
      other.material == material &&
      other.rtl == rtl &&
      other.sides == sides &&
      other.toolbar == toolbar &&
      other.accessoryBand == accessoryBand &&
      other.ownAccessory == ownAccessory &&
      other.ownAccessoryRoom == ownAccessoryRoom;

  @override
  int get hashCode => Object.hash(
    size,
    padding,
    sidePanel,
    material,
    rtl,
    sides,
    toolbar,
    accessoryBand,
    ownAccessory,
    ownAccessoryRoom,
  );
}

class _AdaptiveSheetState extends State<AdaptiveSheet>
    with TickerProviderStateMixin {
  // iOS sheets settle without overshoot; Material 3 Expressive springs
  // (the default spatial spring) bounce a little.
  static final _cupertinoSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 1,
  );
  static final _materialSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 700,
    ratio: 0.9,
  );
  static const _flingVelocity = 650.0;
  static const _rubberBand = 0.3;

  // Gap around a floating sheet (iOS), and how far an edge-to-edge sheet runs
  // on below the area so its rounded bottom corners stay out of sight.
  static const _floatingGap = 8.0;
  static const _overhang = 48.0;

  /// The most room the home indicator alone takes at the bottom: more is the
  /// tabs floating over the sheet, under which its content ends.
  static const _homeIndicatorRoom = 40.0;

  late final AnimationController _extent = AnimationController.unbounded(
    vsync: this,
  );
  late final _SheetScrollController _scrollController = _SheetScrollController(
    this,
  );
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  _Metrics? _metrics;
  double? _headerHeight;
  double? _contentHeight;
  AdaptiveSheetDetent? _target;
  bool _dragging = false;
  EdgeInsets? _reportedObstruction;

  /// The Material navigation bar's link, told whether the sheet is up along
  /// the bar, which rounds its corners for it.
  MaterialTabAccessoryLink? _barLink;
  bool _reportedUp = false;

  /// The spring the sheet settles on, and when it gets there.
  _RetargetableSpring? _spring;
  TickerFuture? _settling;

  /// The frame the content's height last changed in.
  Duration? _contentChangedAt;

  /// Whether the content sits on the bottom edge of the sheet, rather than
  /// hanging from its top: while the sheet goes along with its content, a
  /// frame late, what is at the bottom of the content stays in place.
  var _contentOnBottomEdge = false;

  /// Whether the side panel was in view as it last built.
  bool _panelInView = false;
  static const _panelResizeDuration = Duration(milliseconds: 300);

  // Opening from the tab accessory --------------------------------------------

  /// How much the sheet opens from the tab accessory on it
  /// ([AdaptiveSheet.opensFromAccessory]): 1 while it does, easing to 0 and
  /// back as it stops and starts, so the accessory eases in and out with it.
  late final AnimationController _opensFromAccessory = AnimationController(
    vsync: this,
    duration: kToolbarItemSwapDuration,
  )..addListener(_updateCovered);

  /// How far the content has come up over the accessory, for the host to
  /// make way: 0 at the collapsed detent, 1 once the content is all in sight.
  late final AnimationController _covered = AnimationController(vsync: this);

  /// What moves the edge the content keeps clear of the accessory at.
  late final Listenable _accessoryEdgeMoves = Listenable.merge([
    _extent,
    _opensFromAccessory,
  ]);

  /// How far the content lies above the accessory where the sheet lifts it
  /// apart ([AdaptiveSheet.liftsAccessory]): 0 with nothing above it, or
  /// where the content comes up into its place, 1 once the content is all in
  /// sight above it.
  late final AnimationController _lifted = AnimationController(vsync: this);

  late final _AccessorySheetLink _link = _AccessorySheetLink(this);

  /// How big the sheet's own accessory ([AdaptiveSheet.accessory]) is, as
  /// last laid out.
  Size _ownAccessorySize = Size.zero;

  void _onOwnAccessorySize(Size size) {
    if (!mounted || size == _ownAccessorySize) return;
    setState(() => _ownAccessorySize = size);
  }

  /// How far the sheet's own accessory keeps from its edges: round with its
  /// corners, a capsule of half the sheet's corner radius in from them.
  double get _ownInset => _ownAccessorySize.isEmpty
      ? 0
      : math.max(
          0.0,
          kAdaptiveSheetCornerRadius - _ownAccessorySize.height / 2,
        );

  /// Whether the sheet holds an accessory of its own as it is now laid out.
  bool _holdsOwnAccessory({required bool sidePanel, required bool material}) =>
      widget.accessory != null &&
      !sidePanel &&
      !material &&
      AdaptiveChromeScope.chromeOf(context) == null;

  /// The registry the sheet is attached to, for the host to set the
  /// accessory on it.
  ToolbarRegistry? _attachedTo;

  /// Whether it opens from the accessory, as last built.
  bool? _opensFromAccessoryAsBuilt;

  /// Whether it lifts the accessory apart from its content, as last built.
  var _liftsAsBuilt = false;

  double get _grabberHeight => !widget.showsGrabber
      ? 0
      : (_metrics?.material ?? false)
      ? 36
      : 16;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    if (widget.header == null) _headerHeight = 0;
    _scrollController.addListener(_onScroll);
    _extent.addListener(_updateCovered);
    _extent.addListener(_reportUp);
    _opensFromAccessory.addStatusListener((_) => _syncLink());
  }

  @override
  void didUpdateWidget(AdaptiveSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.header == null) _headerHeight = 0;
    if (!listEquals(oldWidget.detents, widget.detents)) _onExtentsChanged();
    if (oldWidget.floatingMargin != widget.floatingMargin ||
        oldWidget.padding != widget.padding ||
        oldWidget.showsGrabber != widget.showsGrabber) {
      // The sheet's own room changed: it settles again once laid out anew.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onExtentsChanged());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final barLink = MaterialTabAccessoryLink.maybeOf(context);
    if (barLink != _barLink) {
      final old = _barLink;
      if (_reportedUp) {
        runOutsideLayout(
          () => old?.setSheetUp(this, up: false),
          mounted: () => true,
        );
      }
      _barLink = barLink;
      _reportedUp = false;
      _reportUp();
    }
    // A sheet that is a popup route of its own (a modal sheet) slides out of
    // view as the route goes, however it is popped: the barrier tapped, a
    // button, back. A page's own sheet stays with its page.
    final route = ModalRoute.of(context);
    final popup = widget.modal && route is PopupRoute<Object?> ? route : null;
    if (popup == _route) return;
    _route?.animation?.removeStatusListener(_onRouteStatus);
    _route?.animation?.removeListener(_followRouteOut);
    _route = popup;
    popup?.animation?.addStatusListener(_onRouteStatus);
  }

  @override
  void dispose() {
    if (_reportedUp) {
      final link = _barLink;
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => link?.setSheetUp(this, up: false),
      );
    }
    _route?.animation?.removeStatusListener(_onRouteStatus);
    _route?.animation?.removeListener(_followRouteOut);
    widget.controller?._detach(this);
    _attachedTo?.detachAccessorySheet(_link);
    _attachedTo = null;
    _scrollController.dispose();
    _scrolled.dispose();
    _extent.dispose();
    _opensFromAccessory.dispose();
    _covered.dispose();
    _lifted.dispose();
    super.dispose();
  }

  void _reportUp() {
    final link = _barLink;
    if (link == null) return;
    final m = _metrics;
    final up = m != null && m.material && !m.sidePanel && _extent.value > 0.5;
    if (up == _reportedUp) return;
    _reportedUp = up;
    runOutsideLayout(() => link.setSheetUp(this, up: up), mounted: () => true);
  }

  /// Whether the sheet may hold the tab accessory as it is now laid out:
  /// along the bottom, under the native tab bar or the Material one, not
  /// with custom chrome.
  bool _holdsAccessory(_Metrics m) =>
      !m.sidePanel && AdaptiveChromeScope.chromeOf(context) == null;

  /// Starts or stops lifting the accessory apart, after the frame that
  /// changed it.
  void _followLiftsAccessory(bool lifts) {
    if (_liftsAsBuilt == lifts) return;
    _liftsAsBuilt = lifts;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncLink();
      _updateCovered();
    });
  }

  /// Starts or stops opening from the accessory, easing, after the frame
  /// that changed it.
  void _followOpensFromAccessory(bool opens) {
    if (_opensFromAccessoryAsBuilt == opens) return;
    final first = _opensFromAccessoryAsBuilt == null;
    _opensFromAccessoryAsBuilt = opens;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _opensFromAccessoryAsBuilt != opens) return;
      if (first || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _opensFromAccessory.value = opens ? 1 : 0;
        _syncLink();
      } else if (opens) {
        _opensFromAccessory.forward();
      } else {
        _opensFromAccessory.reverse();
      }
    });
  }

  /// Attaches the sheet to the host while the accessory opens into it or
  /// eases out of it, and while it lifts the accessory apart; detaches it
  /// otherwise.
  void _syncLink() {
    if (!mounted) return;
    // A sheet that holds an accessory of its own leaves the host's alone.
    final attach =
        widget.accessory == null &&
            (_liftsAsBuilt ||
                _opensFromAccessory.value > 0 ||
                _opensFromAccessory.isAnimating)
        ? ToolbarRegistry.maybeOf(context)
        : null;
    if (attach == _attachedTo) return;
    _attachedTo?.detachAccessorySheet(_link);
    _attachedTo = attach?..attachAccessorySheet(_link);
  }

  /// Follows the extent with how far the content has come up over the
  /// accessory. Never while widgets build: the host, which follows it, may
  /// have been built already in this frame.
  void _updateCovered() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateCovered();
      });
      return;
    }
    final m = _metrics;
    final live = m == null
        ? 0.0
        : ((_extent.value - _collapsedExtent(m)) / _contentFade).clamp(
            0.0,
            1.0,
          );
    var covered = live * _opensFromAccessory.value;
    // On its way down onto the accessory, as other content gives way to what
    // opens from it, and on its way up from it to other content, which lies
    // above it, the accessory only comes back into sight: it would fade out
    // under content that is going, or that comes up as it stops opening from
    // it, then in again.
    if (m != null &&
        (_isFoldingOntoAccessory(m) || _opensFromAccessoryAsBuilt == false)) {
      covered = math.min(covered, _covered.value);
    }
    if (covered != _covered.value) _covered.value = covered;
    // Above it, where the content does not come up into its place.
    final lifted = _liftsAsBuilt ? live * (1 - _opensFromAccessory.value) : 0.0;
    if (lifted != _lifted.value) _lifted.value = lifted;
  }

  /// Whether the sheet rests at its lowest detent, where only the accessory
  /// shows, or is on its way there.
  bool _isFoldingOntoAccessory(_Metrics m) {
    final target = _target;
    if (target == null || _dragging) return false;
    final points = _restingPoints(m);
    return points.length > 1 && target == points.first.$1;
  }

  /// Opens the sheet from the accessory: to its tallest detent.
  void _openFromAccessory() {
    final m = _metrics;
    if (m == null) return;
    final points = _restingPoints(m);
    if (points.isNotEmpty) _settleTo(points.last.$1);
  }

  /// Closes the sheet onto the accessory: to its lowest detent.
  void _closeOnAccessory() {
    final m = _metrics;
    if (m == null) return;
    final points = _restingPoints(m);
    if (points.isNotEmpty) _settleTo(points.first.$1);
  }

  /// Whether the sheet is open above its lowest detent, or on its way there.
  bool get _isOpenFromAccessory {
    final m = _metrics;
    final target = _target;
    if (m == null || target == null) return false;
    final points = _restingPoints(m);
    return points.isNotEmpty && _extentOf(target, m) > points.first.$2 + 0.5;
  }

  void _onScroll() {
    _scrolled.value =
        _scrollController.hasClients && _scrollController.offset > 0.5;
  }

  // Extents -----------------------------------------------------------------

  bool get _measured => _headerHeight != null && _contentHeight != null;

  /// The gap below a floating sheet: the bottom of
  /// [AdaptiveSheet.floatingMargin] when there is one, 8 points otherwise.
  /// The Material sheet sits on the bottom edge.
  double _bottomGap(_Metrics m) =>
      m.material ? 0 : widget.floatingMargin?.bottom ?? _floatingGap;

  /// Room the content keeps for the bottom padding of the area (a floating
  /// tab bar, the home indicator) beyond the gap below the sheet. None for a
  /// floating sheet placed by [AdaptiveSheet.floatingMargin].
  double _safeBottom(_Metrics m) => !m.material && widget.floatingMargin != null
      ? 0
      : math.max(m.padding.bottom - _bottomGap(m), 0);

  /// Room the content keeps at the bottom for what floats there: all of
  /// [_safeBottom], or for a sheet that opens from the tab accessory on it,
  /// what the tabs take without it, the content running on into its room.
  double _contentBottom(_Metrics m) =>
      math.max(_safeBottom(m) - m.accessoryBand, 0);

  /// Visible height of the content area that the bottom padding takes, inside
  /// the sheet's frame.
  double _bottomSpace(_Metrics m) {
    if (m.sidePanel) return widget.padding.bottom;
    // Above the sheet's own accessory, but where it opens from it.
    return _contentBottom(m) + widget.padding.bottom + m.ownAccessoryRoom;
  }

  /// How far the frame reaches below where a floating sheet rests: growing
  /// to its large detent it goes edge to edge, and on past the bottom, and
  /// its content keeps that much more room at its end to scroll clear of the
  /// tabs.
  double _belowFloating(_Metrics m) => m.material || m.sidePanel
      ? 0
      : math.max(
          0.0,
          _frame(_extent.value, m).bottom - (m.size.height - _bottomGap(m)),
        );

  double _collapsedExtent(_Metrics m) =>
      _grabberHeight +
      (_headerHeight ?? 0) +
      _bottomGap(m) +
      _safeBottom(m) +
      m.ownAccessory;

  double _largeExtent(_Metrics m) =>
      m.size.height -
      m.padding.top -
      m.toolbar -
      (m.material ? 0 : _floatingGap);

  double _fitExtent(_Metrics m) =>
      _bottomGap(m) +
      _grabberHeight +
      (_headerHeight ?? 0) +
      widget.padding.top +
      (_contentHeight ?? 0) +
      _bottomSpace(m);

  double _extentOf(AdaptiveSheetDetent detent, _Metrics m) {
    final large = _largeExtent(m);
    final collapsed = math.min(_collapsedExtent(m), large);
    return detent.resolve(
      collapsed: collapsed,
      fitContent: _fitExtent(m).clamp(collapsed, large),
      large: large,
      available: m.size.height,
    );
  }

  /// The sheet's detents with their extents, lowest first.
  List<(AdaptiveSheetDetent, double)> _restingPoints(_Metrics m) {
    final points = [
      for (final detent in widget.detents)
        if (!detent.isHidden) (detent, _extentOf(detent, m)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return points;
  }

  double get _minExtent {
    final m = _metrics;
    if (m == null) return 0;
    final points = _restingPoints(m);
    return points.isEmpty ? 0 : points.first.$2;
  }

  double get _maxExtent {
    final m = _metrics;
    if (m == null) return 0;
    final points = _restingPoints(m);
    return points.isEmpty ? 0 : points.last.$2;
  }

  bool get _isAtMax => _extent.value >= _maxExtent - 0.5;

  // Settling ----------------------------------------------------------------

  // A side panel takes its height from these as it builds.

  void _onHeaderMeasured(Size size) {
    if (!mounted || _headerHeight == size.height) return;
    setState(() => _headerHeight = size.height);
    _onExtentsChanged();
  }

  void _onContentMeasured(Size size) {
    if (!mounted || _contentHeight == size.height) return;
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final changedAt = _contentChangedAt;
    final previous = _contentHeight;
    _contentChangedAt = now;
    setState(() => _contentHeight = size.height);
    // Content whose height changes frame after frame animates it itself, such
    // as pages of different heights sliding past: the sheet goes along with
    // it, where a spring started anew on every frame would trail and twitch.
    // So does a small change, such as the first step of one of those.
    final follows =
        (changedAt != null && now - changedAt <= _followContentWithin) ||
        (previous != null &&
            (size.height - previous).abs() <= _followContentUpTo);
    if (follows && _followContent()) return;
    _onExtentsChanged();
  }

  static const _followContentWithin = Duration(milliseconds: 50);
  static const _followContentUpTo = 16.0;

  bool _followContent() {
    final m = _metrics;
    final target = _target;
    if (m == null || !_measured || _dragging || target == null) return false;
    if (target.isHidden) return false;
    _extent.stop();
    _extent.value = _extentOf(target, m);
    // A side panel grows down from its top.
    _contentOnBottomEdge = !m.sidePanel;
    _report(target);
    return true;
  }

  void _hangContentFromTop() {
    if (!_contentOnBottomEdge) return;
    _contentOnBottomEdge = false;
    if (mounted) setState(() {});
  }

  /// Something the extents depend on changed: the first measurement shows the
  /// sheet, later ones follow the detent it rests at.
  void _onExtentsChanged() {
    if (!mounted || !_measured || _metrics == null || _dragging) return;
    final target = _target;
    if (target == null) {
      _settleTo(widget.initialDetent);
    } else if (_extent.isAnimating ||
        (_extentOf(target, _metrics!) - _extent.value).abs() > 0.5) {
      _settleTo(target);
    } else {
      _report(target);
    }
  }

  Future<void> _settleTo(AdaptiveSheetDetent detent, {double velocity = 0}) {
    _hangContentFromTop();
    final m = _metrics;
    if (m == null || !_measured) {
      _target = detent;
      return Future<void>.value();
    }
    final changed = _target != detent;
    if (changed) setState(() => _target = detent);
    _dragging = false;
    final to = _extentOf(detent, m);
    _report(detent);
    if (changed) {
      _afterBuild(() {
        widget.onDetentChanged?.call(detent);
        widget.controller?._onDetentChanged();
      });
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _extent.value = to;
      return Future<void>.value();
    }
    // Already on its way, such as content that loads while the sheet comes
    // up: it heads for the new extent from where it is, at the speed it has.
    // A new animation would start from rest, after a frame standing still.
    final spring = _spring;
    final elapsed = _extent.lastElapsedDuration;
    if (_extent.isAnimating && spring != null && elapsed != null) {
      spring.retarget(
        to,
        at: elapsed.inMicroseconds / Duration.microsecondsPerSecond,
      );
      return _settling ?? Future<void>.value();
    }
    final simulation = _spring = _RetargetableSpring(
      m.material ? _materialSpring : _cupertinoSpring,
      start: _extent.value,
      end: to,
      velocity: velocity,
    );
    return _settling = _extent.animateWith(simulation);
  }

  /// Comes to rest at the detent the release suggests: the next one in the
  /// direction of a fling, the nearest one otherwise.
  void _settle({double velocity = 0}) {
    final m = _metrics;
    if (m == null) return;
    final points = _restingPoints(m);
    if (points.isEmpty) return;
    final extent = _extent.value;
    final lowest = points.first.$2;
    final onDismissed = widget.onDismissed;
    // Flung down with no detent below to stop at, or dragged down past a third
    // of the lowest detent.
    if (onDismissed != null &&
        !m.sidePanel &&
        ((velocity <= -_flingVelocity && extent <= lowest + 1) ||
            extent < lowest * 2 / 3)) {
      _settleTo(AdaptiveSheetDetent.hidden, velocity: velocity);
      onDismissed();
      return;
    }
    var target = points.first;
    if (velocity.abs() >= _flingVelocity) {
      target = velocity > 0
          ? points.firstWhere(
              (p) => p.$2 > extent + 1,
              orElse: () => points.last,
            )
          : points.lastWhere(
              (p) => p.$2 < extent - 1,
              orElse: () => points.first,
            );
    } else {
      final projected = extent + velocity * 0.12;
      for (final point in points) {
        if ((point.$2 - projected).abs() < (target.$2 - projected).abs()) {
          target = point;
        }
      }
    }
    _settleTo(target.$1, velocity: velocity);
  }

  void _report(AdaptiveSheetDetent detent) {
    final m = _metrics;
    if (m == null) return;
    final EdgeInsets obstruction;
    if (detent.isHidden) {
      obstruction = EdgeInsets.zero;
    } else if (m.sidePanel) {
      final edge = _sidePanelRect(m).width + _sidePanelInset(m) + _floatingGap;
      obstruction = m.rtl
          ? EdgeInsets.only(right: edge + m.padding.right)
          : EdgeInsets.only(left: edge + m.padding.left);
    } else {
      obstruction = EdgeInsets.only(bottom: _extentOf(detent, m));
    }
    if (obstruction == _reportedObstruction) return;
    _reportedObstruction = obstruction;
    _afterBuild(() {
      if (_reportedObstruction == obstruction) {
        widget.onSettled?.call(obstruction);
      }
    });
  }

  /// Tells the page [tell]: at once, or after the frame where the sheet
  /// settles as the page builds, its detents or its place changing with it
  /// (a sheet that becomes a side panel as a foldable opens): the page may
  /// not be built again in that frame.
  void _afterBuild(VoidCallback tell) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      tell();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) tell();
    });
  }

  // Going with its route ------------------------------------------------------

  /// How tall the toolbar is that the host draws over the pages, for a modal
  /// sheet to stop below it: the title band along the top of the iPhone Duo,
  /// whose other controls are in its vertical bar, or the whole toolbar.
  double _hostedToolbarHeight() {
    final chrome = ToolbarChromeScope.maybeOf(context);
    if (chrome == null) return 0;
    if (chrome.hostsDuoControls) return kDuoTitleBandHeight;
    if (chrome.hostsToolbar) {
      return kHostedToolbarHeight + kHostedToolbarBottomPadding;
    }
    return 0;
  }

  /// The popup route the sheet is the content of, if it is.
  PopupRoute<Object?>? _route;

  /// Where the sheet was as its route started to go: it slides down from
  /// there, with the route's animation, rather than fading where it is.
  double? _leavingFrom;

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.reverse || _leavingFrom != null) return;
    // From where it is, also on its way out after a drag.
    _interrupt();
    _dragging = false;
    _leavingFrom = _extent.value;
    _route?.animation?.addListener(_followRouteOut);
  }

  void _followRouteOut() {
    final from = _leavingFrom;
    final animation = _route?.animation;
    if (from == null || animation == null || !mounted) return;
    // Away at once and easing out, as UIKit's sheets go, so it is all but out
    // of view before what it covered (the tabs) comes back.
    final out = Curves.easeOutCubic.transform(
      (1 - animation.value).clamp(0.0, 1.0),
    );
    _extent.value = from * (1 - out);
  }

  // Dragging ----------------------------------------------------------------

  void _interrupt() {
    if (_extent.isAnimating) _extent.stop();
  }

  void _onDragStart() {
    _interrupt();
    _dragging = true;
    _hangContentFromTop();
  }

  /// Moves the sheet up by [delta] (down when negative), with resistance past
  /// the first and the last detent.
  void _dragBy(double delta) {
    _dragging = true;
    final extent = _extent.value;
    // A sheet that can be dismissed follows the finger down.
    final beyond =
        (delta > 0 && extent >= _maxExtent) ||
        (delta < 0 && extent <= _minExtent && widget.onDismissed == null);
    _extent.value = extent + (beyond ? delta * _rubberBand : delta);
  }

  void _onDragEnd(double velocity) {
    _dragging = false;
    _settle(velocity: velocity);
  }

  /// [child], with vertical drags on it moving the sheet. A touch only takes
  /// the sheet once it moves: alone under a finger, a drag recognizer wins as
  /// soon as the finger comes down, and a tap would stop a sheet on its way.
  Widget _dragsSheet(Widget child) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      VerticalDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(debugOwner: this),
            (recognizer) {
              recognizer.onlyAcceptDragOnThreshold = true;
              recognizer.onStart = (_) => _onDragStart();
              recognizer.onUpdate = (details) =>
                  _dragBy(-details.primaryDelta!);
              recognizer.onEnd = (details) =>
                  _onDragEnd(-(details.primaryVelocity ?? 0));
            },
          ),
    },
    child: child,
  );

  /// Whether a drag on the content moves the sheet rather than scrolling:
  /// only while the content is at its top, and only when the sheet can move
  /// that way. Content with nothing to scroll ([contentFits]) never takes a
  /// drag: the sheet follows the finger at once, past its last detent with
  /// resistance, as a sheet whose content does not scroll does.
  bool _takesDrag({
    required bool expanding,
    required bool contentAtTop,
    bool contentFits = false,
  }) {
    final m = _metrics;
    if (m == null || m.sidePanel) return false;
    if (contentFits && widget.contentDragsSheet) return true;
    if (!contentAtTop) return false;
    final extent = _extent.value;
    final atMin = extent <= _minExtent + 0.5;
    final atMax = extent >= _maxExtent - 0.5;
    if (!atMin && !atMax) return true;
    // One that can be dismissed follows the finger down from its lowest
    // detent too, all the way out.
    if (widget.contentDragsSheet &&
        atMin &&
        !expanding &&
        widget.onDismissed != null) {
      return true;
    }
    return (atMin && expanding) || (atMax && !expanding);
  }

  void _step(int direction) {
    final m = _metrics;
    if (m == null) return;
    final points = _restingPoints(m);
    final index = points.indexWhere((p) => p.$1 == _target);
    final next = (index + direction).clamp(0, points.length - 1);
    _settleTo(points[next].$1);
  }

  // Layout ------------------------------------------------------------------

  double _sidePanelInset(_Metrics m) => 16;

  Rect _sidePanelRect(_Metrics m) {
    final width = math.min(
      widget.sidePanelWidth,
      m.size.width - m.padding.horizontal - 2 * _sidePanelInset(m),
    );
    final top = m.padding.top + _floatingGap;
    final maxHeight = m.size.height - top - m.padding.bottom - _floatingGap;
    // As tall as its content: what fits a bottom sheet, less the gap below a
    // bottom sheet, which a side panel keeps at its top instead.
    final height = _measured
        ? math.min(_fitExtent(m) - _bottomGap(m), maxHeight)
        : maxHeight;
    final left = m.rtl
        ? m.size.width - m.padding.right - _sidePanelInset(m) - width
        : m.padding.left + _sidePanelInset(m);
    return Rect.fromLTWH(left, top, width, math.max(height, 0));
  }

  /// The sheet's frame at [extent]. Lower than its content allows, it runs on
  /// below the area instead of squeezing the content.
  Rect _frame(double extent, _Metrics m) {
    final minHeight = _grabberHeight + (_headerHeight ?? 0);
    final large = _largeExtent(m);
    if (m.material) {
      final width = math.min(m.size.width, 640.0);
      final left = (m.size.width - width) / 2;
      final top = m.size.height - extent;
      return Rect.fromLTWH(left, top, width, math.max(extent, minHeight));
    }
    // 0 while floating, 1 edge to edge at the large detent.
    final points = _restingPoints(m).where((p) => !p.$1.isLarge).toList();
    final morphStart = points.isEmpty
        ? large - 120
        : math.min(points.last.$2, large - 1);
    final t = ((extent - morphStart) / (large - morphStart)).clamp(0.0, 1.0);
    final inset = _floatingGap * (1 - t);
    final bottom = m.size.height - _bottomGap(m) * (1 - t) + _overhang * t;
    final top = m.size.height - extent;
    final height = math.max(bottom - top, minHeight);
    final margin = widget.floatingMargin;
    final left = margin == null
        ? m.sides.left + inset
        : lerpDouble(margin.left, m.sides.left, t)!;
    final right = margin == null
        ? m.sides.right + inset
        : lerpDouble(margin.right, m.sides.right, t)!;
    final width = m.size.width - left - right;
    return Rect.fromLTWH(left, top, width, height);
  }

  /// The band of the iPhone Duo vertical bar, on the side the pose puts it.
  /// Android has no such bar; its landscape cutouts are no reason to move the
  /// sheet.
  static EdgeInsets _sidesOf(BuildContext context, {required bool material}) {
    if (material) return EdgeInsets.zero;
    final pose = DuoPoseScope.of(context);
    if (pose == null) return EdgeInsets.zero;
    return pose.onLeft
        ? EdgeInsets.only(left: pose.bandWidth)
        : EdgeInsets.only(right: pose.bandWidth);
  }

  @override
  Widget build(BuildContext context) {
    // Custom chrome floats the sheet on its own glass on every platform.
    final material =
        PlatformInfo.isAndroid && AdaptiveChromeScope.chromeOf(context) == null;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanel =
            widget.sidePanel ??
            constraints.maxWidth >= AdaptiveSheet.sidePanelMinWidth;
        final ownAccessory =
            _holdsOwnAccessory(sidePanel: sidePanel, material: material) &&
                !_ownAccessorySize.isEmpty
            ? _ownAccessorySize.height + 2 * _ownInset
            : 0.0;
        final metrics = _Metrics(
          size: constraints.biggest,
          padding: MediaQuery.paddingOf(context),
          sidePanel: sidePanel,
          material: material,
          rtl: rtl,
          sides: _sidesOf(context, material: material),
          toolbar: _route == null || material ? 0 : _hostedToolbarHeight(),
          // What the accessory on the sheet takes of the bottom padding, for
          // the content to run on into, where it opens from it.
          accessoryBand: widget.opensFromAccessory && !sidePanel
              ? AdaptiveBottomBarInset.accessoryOf(context)
              : 0,
          ownAccessory: ownAccessory,
          ownAccessoryRoom: widget.opensFromAccessory ? 0 : ownAccessory,
        );
        if (metrics != _metrics) {
          _metrics = metrics;
          // After this layout: settling needs the new metrics in place.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _reportedObstruction = null;
            _onExtentsChanged();
            _updateCovered();
            _reportUp();
          });
        }
        final holds = _holdsAccessory(metrics);
        _followOpensFromAccessory(holds && widget.opensFromAccessory);
        // The Material bar holds the accessory on a band of its own already.
        _followLiftsAccessory(
          holds && !metrics.material && widget.liftsAccessory,
        );
        final body = _buildBody(context, metrics);
        if (sidePanel) {
          final hidden = _target?.isHidden ?? !_measured;
          // In view, the panel grows and shrinks with its content. Coming
          // into view, it slides in at its size.
          final resizes =
              _panelInView &&
              !hidden &&
              !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
          _panelInView = !hidden;
          final rect = _sidePanelRect(metrics);
          // Out of the area it floats in, with room to spare for a shadow,
          // however far from its edge it floats (a vertical bar on that side).
          final away = rect.width > 0
              ? (rtl
                        ? metrics.size.width - rect.left + _floatingGap
                        : -(rect.right + _floatingGap)) /
                    rect.width
              : 0.0;
          final panel = Stack(
            // A clip around the native glass would break it.
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned.fromRect(
                rect: rect,
                duration: resizes ? _panelResizeDuration : Duration.zero,
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: hidden ? Offset(away, 0) : Offset.zero,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(ignoring: hidden, child: body),
                ),
              ),
            ],
          );
          // Material has no glass to break, and its area may not start at the
          // edge of the screen, with a navigation rail beside it: the panel
          // slides out of the area under the rail, not over it. The slide is
          // painted, not laid out, so only a clip of its own cuts it off.
          return material ? ClipRect(child: panel) : panel;
        }
        final own = _holdsOwnAccessory(sidePanel: false, material: material)
            ? _ownAccessory(metrics)
            : null;
        // Across, where the sheet floats at its smallest.
        final across = _frame(_collapsedExtent(metrics), metrics);
        final inset = _ownInset;
        return AnimatedBuilder(
          animation: _extent,
          builder: (context, child) {
            final frame = _frame(_extent.value, metrics);
            return Stack(
              // A clip around the native glass would break it.
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(rect: frame, child: child!),
                // At the bottom of the sheet, wherever the sheet is, and out
                // of view with it.
                if (own != null)
                  Positioned(
                    left: across.left + inset,
                    width: math.max(0.0, across.width - 2 * inset),
                    top:
                        math.max(
                          frame.top,
                          frame.bottom - metrics.ownAccessory,
                        ) +
                        inset,
                    child: own,
                  ),
              ],
            );
          },
          child: body,
        );
      },
    );
  }

  /// How far past its collapsed detent the content is in sight at last.
  static const _contentFade = 56.0;

  /// [content], out of sight at the collapsed detent, where only the header
  /// shows as with Find My, and fading in as the sheet is pulled up from it:
  /// what floats over the bottom of the sheet (the tabs, what they carry)
  /// then never sits on its content. It takes no touches while out of sight.
  ///
  /// The same for a sheet that opens from the tab accessory on it
  /// ([AdaptiveSheet.opensFromAccessory]): only the accessory shows there.
  /// Out of sight, the content's tickers stop (a clock on it).
  ///
  /// Built the same either way, so the content keeps its state as the sheet
  /// starts or stops fading it.
  Widget _fadesAtCollapsed(_Metrics metrics, Widget content) {
    final fades =
        (widget.keepsContentClearOfBars || widget.opensFromAccessory) &&
        !metrics.sidePanel &&
        widget.detents.contains(AdaptiveSheetDetent.collapsed);
    return AnimatedBuilder(
      animation: _extent,
      child: content,
      builder: (context, content) {
        final shown = !fades
            ? 1.0
            : ((_extent.value - _collapsedExtent(metrics)) / _contentFade)
                  .clamp(0.0, 1.0);
        return TickerMode(
          enabled: shown > 0,
          child: IgnorePointer(
            ignoring: shown < 0.05,
            child: Opacity(opacity: shown, child: content),
          ),
        );
      },
    );
  }

  /// How far into the bottom of the grabber and the header content scrolled
  /// under them is in sight, fading out toward their top.
  static const _underTopFade = 14.0;

  /// [content], scrolled on under the grabber and the header, fading out as
  /// it goes under them ([AdaptiveSheet.showsHeaderBackdrop]): their
  /// background frosts it where a blur reaches it, but a blur reaches no
  /// further than the native views below it (the sheet's glass, a map), so
  /// the content would show sharp through it otherwise.
  Widget _fadesUnderTop(bool underTop, Widget content) {
    if (!underTop) return content;
    return ValueListenableBuilder<bool>(
      valueListenable: _scrolled,
      child: content,
      builder: (context, scrolled, content) => _UnderTopFade(
        extent: scrolled ? _grabberHeight + (_headerHeight ?? 0) : 0,
        fade: _underTopFade,
        child: content,
      ),
    );
  }

  Widget _buildBody(BuildContext context, _Metrics metrics) {
    final material = metrics.material;
    final header = widget.header;
    // The content runs on under the grabber and the header, which are laid
    // over it, behind their background once it scrolls under them.
    final underTop = widget.showsHeaderBackdrop && widget.scrollable;
    final contentPadding = EdgeInsets.only(
      left: widget.padding.left,
      top: widget.padding.top,
      right: widget.padding.right,
      bottom: _bottomSpace(metrics),
    );
    final measuredChild = SizeReporter(
      onSizeChanged: _onContentMeasured,
      child: widget.child,
    );
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showsGrabber)
          _Grabber(
            material: material,
            label: widget.grabberSemanticsLabel,
            onIncrease: () => _step(1),
            onDecrease: () => _step(-1),
          ),
        if (header != null)
          SizeReporter(onSizeChanged: _onHeaderMeasured, child: header),
      ],
    );
    final topSlot = LayoutId(
      id: _SheetSlot.top,
      child: _dragsSheet(
        underTop
            ? Stack(
                children: [
                  Positioned.fill(
                    child: _HeaderBackdrop(
                      scrolled: _scrolled,
                      material: material,
                      color: widget.glassFill,
                    ),
                  ),
                  top,
                ],
              )
            : top,
      ),
    );
    Widget content = CustomMultiChildLayout(
      delegate: _SheetBodyLayout(),
      children: [
        // Painted in this order: the top over the content running under it.
        if (!underTop) topSlot,
        LayoutId(
          id: _SheetSlot.content,
          child: _fadesAtCollapsed(
            metrics,
            widget.scrollable
                ? _fadesUnderTop(
                    underTop,
                    _ScrollEdgeFade(
                      scrolled: _scrolled,
                      fadesTop: !underTop,
                      // Under the tabs alone, on glass of their own, it fades
                      // out as it goes on under them; an accessory on the
                      // sheet has none, and the content ends where it begins.
                      fadesUnderTabs:
                          AdaptiveBottomBarInset.accessoryOf(context) <= 0,
                      // Under the tabs and what they carry, wherever the sheet
                      // is: at its tallest it runs on past the bottom. Not
                      // under the home indicator alone.
                      bottomEdge:
                          !widget.keepsContentClearOfBars ||
                              material ||
                              metrics.sidePanel ||
                              metrics.padding.bottom <= _homeIndicatorRoom
                          ? null
                          : () => math.max(
                              0.0,
                              _frame(_extent.value, metrics).bottom -
                                  (metrics.size.height -
                                      metrics.padding.bottom +
                                      metrics.accessoryBand),
                            ),
                      child: AnimatedBuilder(
                        animation: _extent,
                        builder: (context, _) => SingleChildScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: contentPadding.copyWith(
                            bottom:
                                contentPadding.bottom + _belowFloating(metrics),
                          ),
                          // Scrolled, on under the top; the sheet clips it.
                          clipBehavior: underTop ? Clip.none : Clip.hardEdge,
                          child: measuredChild,
                        ),
                      ),
                    ),
                  )
                // Laid out at its natural height, never scrolled: a drag on it
                // moves the sheet.
                : _dragsSheet(
                    OverflowBox(
                      alignment: _contentOnBottomEdge
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: contentPadding,
                        child: measuredChild,
                      ),
                    ),
                  ),
          ),
        ),
        if (underTop) topSlot,
      ],
    );
    // Content scrolled on under the top goes no further than the sheet's
    // edge, whatever the sheet's own shape clips.
    if (underTop) content = ClipRect(child: content);

    if (material) {
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: metrics.sidePanel
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
            : const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    final sidePanel = metrics.sidePanel;
    const radius = kAdaptiveSheetCornerRadius;
    if (AdaptiveChromeScope.chromeOf(context) != null) {
      return AdaptiveGlass(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(sidePanel ? 28 : radius),
        ),
        child: content,
      );
    }
    return IOS26GlassSurface(
      cornerRadius: sidePanel ? 28 : radius,
      corners: sidePanel
          ? GlassSurfaceCorners.fixed
          : GlassSurfaceCorners.concentric,
      fill: widget.glassFill,
      // In the glass's own shape, whose corners near the display's are
      // rounder than radius.
      clipBehavior: Clip.antiAlias,
      child: _ClearOfAccessory(
        bottom: _accessoryEdge(metrics),
        moves: _accessoryEdgeMoves,
        child: content,
      ),
    );
  }

  /// Where the content of a sheet that holds the tab accessory on its glass
  /// ends, in the sheet's own coordinates, while it does not open from it: at
  /// the top of the accessory's band, so that content coming up from below
  /// the accessory, or going down behind it, never shows around it, where it
  /// has no glass of its own to cover it. Null where the content runs on.
  double? Function()? _accessoryEdge(_Metrics m) {
    final own = m.ownAccessory;
    if (m.sidePanel ||
        !_holdsAccessory(m) ||
        !(widget.opensFromAccessory || widget.liftsAccessory) ||
        (own <= 0 && AdaptiveBottomBarInset.accessoryOf(context) <= 0)) {
      return null;
    }
    final edge = m.size.height - m.padding.bottom;
    // From the frame its content stops opening from the accessory, before the
    // accessory has started to ease in, until it opens from it all the way,
    // what goes having eased out. Above the band of the sheet's own
    // accessory, or of the host's.
    return () {
      if (widget.opensFromAccessory && _opensFromAccessory.value >= 1) {
        return null;
      }
      final frame = _frame(_extent.value, m);
      return own > 0 ? frame.height - own : edge - frame.top;
    };
  }

  /// The sheet's own accessory ([AdaptiveSheet.accessory]), told where it is,
  /// making way as the content comes up over it, moving the sheet when
  /// dragged, and on a capsule of its own while the sheet lifts it.
  Widget _ownAccessory(_Metrics m) {
    final across = _frame(_collapsedExtent(m), m);
    final inset = _ownInset;
    final spec = AdaptiveAccessorySpec(
      placement: AdaptiveChromePlacement.bottom,
      compact: false,
      room: math.max(0.0, across.width - 2 * inset),
      layout: AdaptiveTabAccessoryLayout.onSheet,
    );
    // The sheet's glass around it, round with its corners, or its capsule.
    final onSheet = AdaptiveAccessorySurface(
      outsets: EdgeInsets.all(inset),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(kAdaptiveSheetCornerRadius),
      ),
    );
    const onCapsule = AdaptiveAccessorySurface(shape: StadiumBorder());
    return AccessoryMakesWay(
      covered: _covered,
      child: AccessorySheetDrag(
        sheet: _link,
        child: AnimatedBuilder(
          animation: _lifted,
          child: NativeAccessoryGlass(
            glass: false,
            glassOpacity: _lifted,
            child: SizeReporter(
              onSizeChanged: _onOwnAccessorySize,
              child: widget.accessory,
            ),
          ),
          builder: (context, child) => AdaptiveAccessoryScope(
            spec: spec,
            expansion: _link,
            surface: _lifted.value >= 0.5 ? onCapsule : onSheet,
            child: child!,
          ),
        ),
      ),
    );
  }
}

/// [child], cut off at the [bottom] it is told while it is not null: the
/// content of a sheet that holds the tab accessory, kept clear of it. Asks
/// again as the sheet [moves].
class _ClearOfAccessory extends SingleChildRenderObjectWidget {
  const _ClearOfAccessory({
    required this.bottom,
    required this.moves,
    super.child,
  });

  final double? Function()? bottom;
  final Listenable moves;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClearOfAccessory(bottom, moves);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderClearOfAccessory renderObject,
  ) {
    renderObject
      ..bottom = bottom
      ..moves = moves;
  }
}

class _RenderClearOfAccessory extends RenderProxyBox {
  _RenderClearOfAccessory(this._bottom, this._moves);

  double? Function()? _bottom;
  set bottom(double? Function()? value) {
    if (value == null && _bottom == null) return;
    _bottom = value;
    markNeedsPaint();
  }

  Listenable _moves;
  set moves(Listenable value) {
    if (value == _moves) return;
    if (attached) _moves.removeListener(markNeedsPaint);
    _moves = value;
    if (attached) _moves.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moves.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  Rect? get _clipRect {
    final bottom = _bottom?.call();
    if (bottom == null || bottom >= size.height) return null;
    return Rect.fromLTRB(0, 0, size.width, math.max(0.0, bottom));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = child == null ? null : _clipRect;
    if (rect == null) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      rect,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => _clipRect;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final rect = _clipRect;
    if (rect != null && !rect.contains(position)) return false;
    return super.hitTest(result, position: position);
  }
}

/// A spring that can head for another end while it runs: from where it is at
/// that moment, at the speed it has, on the clock of the animation that runs
/// it.
class _RetargetableSpring extends Simulation {
  _RetargetableSpring(
    this._description, {
    required double start,
    required double end,
    required double velocity,
  }) : _spring = SpringSimulation(_description, start, end, velocity);

  final SpringDescription _description;
  SpringSimulation _spring;

  /// When the spring headed for its end, in seconds.
  double _since = 0;

  void retarget(double end, {required double at}) {
    _spring = SpringSimulation(_description, x(at), end, dx(at));
    _since = at;
  }

  @override
  double x(double time) => _spring.x(time - _since);

  @override
  double dx(double time) => _spring.dx(time - _since);

  @override
  bool isDone(double time) => _spring.isDone(time - _since);
}

enum _SheetSlot { top, content }

/// The grabber and the header at their natural height, the content below
/// them in what is left. A sheet lower than its header lets the header run on
/// below its bottom edge (where it is clipped) instead of squeezing it.
class _SheetBodyLayout extends MultiChildLayoutDelegate {
  _SheetBodyLayout();

  @override
  void performLayout(Size size) {
    final top = layoutChild(
      _SheetSlot.top,
      BoxConstraints.tightFor(width: size.width),
    );
    positionChild(_SheetSlot.top, Offset.zero);
    layoutChild(
      _SheetSlot.content,
      BoxConstraints.tightFor(
        width: size.width,
        height: math.max(size.height - top.height, 0),
      ),
    );
    positionChild(_SheetSlot.content, Offset(0, top.height));
  }

  @override
  bool shouldRelayout(_SheetBodyLayout oldDelegate) => false;
}

/// The grabber at the top of the sheet, which also moves it for assistive
/// technologies.
class _Grabber extends StatelessWidget {
  const _Grabber({
    required this.material,
    required this.label,
    required this.onIncrease,
    required this.onDecrease,
  });

  final bool material;
  final String label;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final color = material
        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : CupertinoColors.tertiaryLabel.resolveFrom(context);
    return Semantics(
      label: label,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: SizedBox(
        height: material ? 36 : 16,
        child: Center(
          child: Container(
            width: material ? 32 : 36,
            height: material ? 4 : 5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades content out under the header once it is scrolled, like the iOS 26
/// scroll edge effect.
class _ScrollEdgeFade extends StatelessWidget {
  const _ScrollEdgeFade({
    required this.scrolled,
    required this.child,
    this.bottomEdge,
    this.fadesTop = true,
    this.fadesUnderTabs = false,
  });

  final ValueListenable<bool> scrolled;
  final Widget child;

  /// Whether the content fades out along its top edge once scrolled: not
  /// where it runs on under a header with a background of its own.
  final bool fadesTop;

  /// How much of the bottom of the content lies under the tabs floating
  /// over the sheet's bottom, and what they carry, as it is painted: the
  /// content ends where they begin, rather than running on under what they
  /// carry with no glass of its own (a tab accessory on the sheet).
  final double Function()? bottomEdge;

  /// Whether the content fades out over the part of it under the tabs, as it
  /// runs on under them, rather than ending where they begin.
  final bool fadesUnderTabs;

  /// How far the content fades over at its top, once scrolled.
  static const _fade = 16.0;

  /// How far above the tabs the content starts to fade out as it runs on
  /// under them, gone by about their middle.
  static const _intoTabs = 12.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      child: child,
      builder: (context, scrolled, child) {
        scrolled = scrolled && fadesTop;
        if (!scrolled && bottomEdge == null) return child!;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final bottomEdge = this.bottomEdge?.call() ?? 0;
            final height = math.max(bounds.height, 1.0);
            double at(double y) => (y / height).clamp(0.0, 1.0);
            const clear = Color(0x00000000);
            const shown = Color(0xFF000000);
            final bottom = height - bottomEdge;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                if (scrolled) clear,
                shown,
                shown,
                if (bottomEdge > 0) clear,
              ],
              // A clean edge at the bottom, or a fade over the tabs.
              stops: [
                if (scrolled) 0,
                at(scrolled ? _fade : 0),
                at(
                  bottomEdge > 0
                      ? bottom - (fadesUnderTabs ? _intoTabs : 0)
                      : height,
                ),
                if (bottomEdge > 0)
                  at(fadesUnderTabs ? bottom + bottomEdge * 0.6 : bottom),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// Fades out what its child paints above itself, over the [extent] above it,
/// from in sight at its own top edge to out of sight [fade] above it: content
/// scrolled on under a sheet's header.
class _UnderTopFade extends SingleChildRenderObjectWidget {
  const _UnderTopFade({
    required this.extent,
    required this.fade,
    required super.child,
  });

  final double extent;
  final double fade;

  @override
  _RenderUnderTopFade createRenderObject(BuildContext context) =>
      _RenderUnderTopFade(extent: extent, fade: fade);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderUnderTopFade renderObject,
  ) {
    renderObject
      ..extent = extent
      ..fade = fade;
  }
}

class _RenderUnderTopFade extends RenderProxyBox {
  _RenderUnderTopFade({required double extent, required double fade})
    : _extent = extent,
      _fade = fade;

  double _extent;

  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsPaint();
    markNeedsCompositingBitsUpdate();
  }

  double _fade;

  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    markNeedsPaint();
  }

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  bool get alwaysNeedsCompositing => child != null && _extent > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _extent <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final rect = Rect.fromLTRB(
      offset.dx,
      offset.dy - _extent,
      offset.dx + size.width,
      offset.dy + size.height,
    );
    final height = math.max(rect.height, 1.0);
    final fade = math.min(_fade, _extent);
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0x00000000), Color(0xFF000000)],
        stops: [0, (_extent - fade) / height, _extent / height],
      ).createShader(Offset.zero & rect.size)
      ..maskRect = rect
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}

/// The background of a sheet's grabber and header over content scrolled
/// under them, as a page's bar has it ([AdaptiveSheet.showsHeaderBackdrop]),
/// coming in as soon as the content scrolls.
class _HeaderBackdrop extends StatelessWidget {
  const _HeaderBackdrop({
    required this.scrolled,
    required this.material,
    required this.color,
  });

  final ValueListenable<bool> scrolled;
  final bool material;

  /// The sheet's fill over its glass, which the frost takes on iOS.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Nothing in the way (no blur, no paint) while out of sight.
    final background = IgnorePointer(
      child: material
          ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer)
          : AdaptiveBarBackdrop(color: color),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      child: background,
      builder: (context, scrolled, background) => AnimatedOpacity(
        opacity: scrolled ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: background,
      ),
    );
  }
}

/// Lets a drag on the content move the sheet while the content is at its top.
class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _AdaptiveSheetState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _AdaptiveSheetState sheet;

  /// Whether the drag in progress has moved the sheet.
  bool _movedSheet = false;

  bool get _atTop => pixels <= minScrollExtent;

  // A touch leaves a sheet on its way alone until it drags (which takes the
  // sheet over): stopped here, a tap would leave it halfway.

  @override
  void applyUserOffset(double delta) {
    // A positive delta: the finger moves down.
    if (sheet._takesDrag(
      expanding: delta < 0,
      contentAtTop: _atTop,
      contentFits: maxScrollExtent <= minScrollExtent,
    )) {
      _movedSheet = true;
      sheet._dragBy(-delta);
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (!_movedSheet) {
      super.goBallistic(velocity);
      return;
    }
    _movedSheet = false;
    // A positive velocity: flung up. Fully up, the content flies on.
    final contentFlies = velocity > 0 && sheet._isAtMax;
    sheet._onDragEnd(contentFlies ? 0 : velocity);
    super.goBallistic(contentFlies ? velocity : 0);
  }
}

/// The sheet as the toolbar host sees it, where it opens from the tab
/// accessory on it ([AdaptiveSheet.opensFromAccessory]).
class _AccessorySheetLink implements AccessorySheet {
  _AccessorySheetLink(this._sheet);

  final _AdaptiveSheetState _sheet;

  @override
  Animation<double> get value => _sheet._covered;

  @override
  Animation<double> get lifted => _sheet._lifted;

  @override
  bool get isOpen => _sheet._isOpenFromAccessory;

  @override
  void open() => _sheet._openFromAccessory();

  @override
  void close() => _sheet._closeOnAccessory();

  @override
  void toggle() => isOpen ? close() : open();

  @override
  void dragStart() => _sheet._onDragStart();

  @override
  void dragUpdate(double delta) => _sheet._dragBy(delta);

  @override
  void dragEnd(double velocity) => _sheet._onDragEnd(velocity);
}
