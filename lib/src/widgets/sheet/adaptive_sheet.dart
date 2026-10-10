import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../platform/platform_info.dart';
import '../../toolbar/duo_vertical_bar.dart';
import '../../utils/size_reporter.dart';
import '../ios26/ios26_glass_surface.dart';
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
  });

  final Size size;
  final EdgeInsets padding;
  final bool sidePanel;
  final bool material;
  final bool rtl;

  /// Room a floating sheet leaves at its sides: the band of the iPhone Duo
  /// vertical bar, which carries the tab bar and toolbar along that edge.
  final EdgeInsets sides;

  @override
  bool operator ==(Object other) =>
      other is _Metrics &&
      other.size == size &&
      other.padding == padding &&
      other.sidePanel == sidePanel &&
      other.material == material &&
      other.rtl == rtl &&
      other.sides == sides;

  @override
  int get hashCode =>
      Object.hash(size, padding, sidePanel, material, rtl, sides);
}

class _AdaptiveSheetState extends State<AdaptiveSheet>
    with SingleTickerProviderStateMixin {
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

  /// The spring the sheet settles on, and when it gets there.
  _RetargetableSpring? _spring;
  TickerFuture? _settling;

  /// Whether the side panel was in view as it last built.
  bool _panelInView = false;
  static const _panelResizeDuration = Duration(milliseconds: 300);

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
  void dispose() {
    widget.controller?._detach(this);
    _scrollController.dispose();
    _scrolled.dispose();
    _extent.dispose();
    super.dispose();
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

  /// Visible height of the content area that the bottom padding takes, inside
  /// the sheet's frame.
  double _bottomSpace(_Metrics m) {
    if (m.sidePanel) return widget.padding.bottom;
    return _safeBottom(m) + widget.padding.bottom;
  }

  double _collapsedExtent(_Metrics m) =>
      _grabberHeight + (_headerHeight ?? 0) + _bottomGap(m) + _safeBottom(m);

  double _largeExtent(_Metrics m) =>
      m.size.height - m.padding.top - (m.material ? 0 : _floatingGap);

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
    setState(() => _contentHeight = size.height);
    _onExtentsChanged();
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
      widget.onDetentChanged?.call(detent);
      widget.controller?._onDetentChanged();
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
    widget.onSettled?.call(obstruction);
  }

  // Dragging ----------------------------------------------------------------

  void _interrupt() {
    if (_extent.isAnimating) _extent.stop();
  }

  void _onDragStart() {
    _interrupt();
    _dragging = true;
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
  /// that way.
  bool _takesDrag({required bool expanding, required bool contentAtTop}) {
    final m = _metrics;
    if (m == null || m.sidePanel || !contentAtTop) return false;
    final extent = _extent.value;
    final atMin = extent <= _minExtent + 0.5;
    final atMax = extent >= _maxExtent - 0.5;
    if (!atMin && !atMax) return true;
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
    final height = _measured
        ? math.min(_fitExtent(m) - _floatingGap, maxHeight)
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

  /// The band of the iPhone Duo vertical bar, on the side the system reserves
  /// for it. Android has no such bar; its landscape cutouts are no reason to
  /// move the sheet.
  static EdgeInsets _sidesOf(BuildContext context, {required bool material}) {
    if (material) return EdgeInsets.zero;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    return switch (DuoLayout.barSide(viewPadding)) {
      DuoBarSide.left => EdgeInsets.only(
        left: DuoLayout.bandWidth(viewPadding),
      ),
      DuoBarSide.right => EdgeInsets.only(
        right: DuoLayout.bandWidth(viewPadding),
      ),
      null => EdgeInsets.zero,
    };
  }

  @override
  Widget build(BuildContext context) {
    final material = PlatformInfo.isAndroid;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanel =
            widget.sidePanel ??
            constraints.maxWidth >= AdaptiveSheet.sidePanelMinWidth;
        final metrics = _Metrics(
          size: constraints.biggest,
          padding: MediaQuery.paddingOf(context),
          sidePanel: sidePanel,
          material: material,
          rtl: rtl,
          sides: _sidesOf(context, material: material),
        );
        if (metrics != _metrics) {
          _metrics = metrics;
          // After this layout: settling needs the new metrics in place.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _reportedObstruction = null;
            _onExtentsChanged();
          });
        }
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
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned.fromRect(
                rect: _sidePanelRect(metrics),
                duration: resizes ? _panelResizeDuration : Duration.zero,
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: hidden ? Offset(rtl ? 1.2 : -1.2, 0) : Offset.zero,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(ignoring: hidden, child: body),
                ),
              ),
            ],
          );
        }
        return AnimatedBuilder(
          animation: _extent,
          builder: (context, child) => Stack(
            // A clip around the native glass would break it.
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: _frame(_extent.value, metrics),
                child: child!,
              ),
            ],
          ),
          child: body,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, _Metrics metrics) {
    final material = metrics.material;
    final header = widget.header;
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
    final content = CustomMultiChildLayout(
      delegate: _SheetBodyLayout(),
      children: [
        LayoutId(
          id: _SheetSlot.top,
          child: _dragsSheet(
            Column(
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
            ),
          ),
        ),
        LayoutId(
          id: _SheetSlot.content,
          child: widget.scrollable
              ? _ScrollEdgeFade(
                  scrolled: _scrolled,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: contentPadding,
                    child: measuredChild,
                  ),
                )
              // Laid out at its natural height, never scrolled: a drag on it
              // moves the sheet.
              : _dragsSheet(
                  OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Padding(
                      padding: contentPadding,
                      child: measuredChild,
                    ),
                  ),
                ),
        ),
      ],
    );

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
    const radius = 30.0;
    return IOS26GlassSurface(
      cornerRadius: sidePanel ? 28 : radius,
      corners: sidePanel
          ? GlassSurfaceCorners.fixed
          : GlassSurfaceCorners.concentric,
      // The content is clipped on its own, as a sibling of the glass: a clip
      // around the glass would break it.
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(sidePanel ? 28 : radius),
        child: content,
      ),
    );
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
  const _ScrollEdgeFade({required this.scrolled, required this.child});

  final ValueListenable<bool> scrolled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      child: child,
      builder: (context, scrolled, child) {
        if (!scrolled) return child!;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00000000), Color(0xFF000000)],
            stops: [0, math.min(16 / math.max(bounds.height, 1), 1)],
          ).createShader(bounds),
          child: child,
        );
      },
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
    if (sheet._takesDrag(expanding: delta < 0, contentAtTop: _atTop)) {
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
