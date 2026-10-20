import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/outside_layout.dart';
import '../utils/size_reporter.dart';
import 'adaptive_chrome.dart';

/// The scroll edge effect of custom chrome, as iOS 26 draws it: part of each
/// scroll view whose content runs under the bars along the top of the page,
/// not a layer over the whole page.
///
/// A page wraps its body in one. Every vertical scroll view inside it then
/// draws the bar's background ([AdaptiveChrome.barBackgroundBuilder], or
/// else [AdaptiveBarBackdrop]) over its own content where that content runs
/// under the bars along the top ([top]), fading in as soon as content starts
/// to scroll under them ([AdaptiveScrollEdge]). Whatever the page lays over a
/// scroll view stays clear of it, such as a search field pinned below the bar
/// ([AdaptiveSafeAreaBar]). Content that does not scroll, such as a map, gets
/// none.
///
/// Where scroll views nest, the outermost one under the bars draws it, as
/// its content is what runs under them.
class AdaptiveScrollEdgeRegion extends StatefulWidget {
  const AdaptiveScrollEdgeRegion({
    super.key,
    required this.chrome,
    required this.placement,
    required this.top,
    required this.child,
    this.titleBand = false,
    this.hairline = true,
    this.visibility = const AlwaysStoppedListenable<double>(1),
    this.color,
    this.data,
  });

  final AdaptiveChrome chrome;
  final AdaptiveChromePlacement placement;

  /// How far down the page the bars along its top reach, from the top of the
  /// page. Null where nothing covers it there.
  final double? top;

  /// The bars along the top are the iPhone Duo's title band.
  final bool titleBand;

  /// Whether the bar's background ends in a hairline
  /// ([AdaptiveAppBar.showsHairline]).
  final bool hairline;

  /// How far the bars along the top are shown, from 0 to 1: the iPhone Duo's
  /// title band moves out of the way while content scrolls on, and comes
  /// back as it scrolls back.
  final ValueListenable<double> visibility;

  /// The colour along the top: a header's, or the page's own.
  final Color? color;

  /// The app's data for the bar background ([AdaptiveAppBar.chromeData]).
  final Object? data;

  final Widget child;

  @override
  State<AdaptiveScrollEdgeRegion> createState() =>
      _AdaptiveScrollEdgeRegionState();
}

class _AdaptiveScrollEdgeRegionState extends State<AdaptiveScrollEdgeRegion> {
  final _PageBox _page = _PageBox();

  @override
  Widget build(BuildContext context) {
    return _PageMarker(
      page: _page,
      child: _RegionScope(
        region: widget,
        top: widget.top,
        pinned: false,
        color: widget.color,
        page: _page,
        child: ScrollConfiguration(
          behavior: _ScrollEdgeBehavior.around(ScrollConfiguration.of(context)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Content pinned below a page's bar that joins it, such as a search field
/// or tabs, like SwiftUI's `safeAreaBar`: the page's [child] runs under both,
/// its padding along the top grows by the height of [bar], and the bar's
/// background ([AdaptiveScrollEdgeRegion]) reaches below [bar] too, behind
/// it, frosted with the bar as one surface
/// ([AdaptiveBarBackgroundSpec.pinned]).
///
/// On the iPhone Duo, where the title band moves out of the way while
/// content scrolls on, [bar] goes with it.
class AdaptiveSafeAreaBar extends StatefulWidget {
  const AdaptiveSafeAreaBar({
    super.key,
    required this.bar,
    required this.child,
    this.color,
  });

  /// Pinned below the bar. Its height is measured; a [PreferredSizeWidget]
  /// lays the page out right from the first frame.
  final Widget bar;

  final Widget child;

  /// The colour of the bar's background behind [bar] and the content
  /// below it, where it differs from the page's.
  final Color? color;

  /// Whether [context] is in the [bar] of an [AdaptiveSafeAreaBar] that has
  /// the bar's background behind it. What is pinned there leaves its own
  /// background out, or it covers the bar's frost with a band of its own.
  static bool isIn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PinnedBar>()?.onBackground ??
      false;

  @override
  State<AdaptiveSafeAreaBar> createState() => _AdaptiveSafeAreaBarState();
}

class _PinnedBar extends InheritedWidget {
  const _PinnedBar({required this.onBackground, required super.child});

  final bool onBackground;

  @override
  bool updateShouldNotify(_PinnedBar oldWidget) =>
      onBackground != oldWidget.onBackground;
}

class _AdaptiveSafeAreaBarState extends State<AdaptiveSafeAreaBar> {
  late final ValueNotifier<double> _height = ValueNotifier<double>(
    switch (widget.bar) {
      final PreferredSizeWidget bar => bar.preferredSize.height,
      _ => 0,
    },
  );

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RegionScope>();
    final visibility =
        scope?.region.visibility ?? const AlwaysStoppedListenable<double>(1);
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _height,
          child: widget.child,
          builder: (context, height, child) {
            final data = MediaQuery.of(context);
            final content = MediaQuery(
              data: data.copyWith(
                padding: data.padding.copyWith(top: data.padding.top + height),
                viewPadding: data.viewPadding.copyWith(
                  top: data.viewPadding.top + height,
                ),
              ),
              child: child!,
            );
            if (scope == null) return content;
            return _RegionScope(
              region: scope.region,
              // Nothing pinned on a page without a bar background keeps
              // that: no background along the top.
              top: scope.top == null && height <= 0
                  ? null
                  : (scope.top ?? top) + height,
              pinned: scope.pinned || height > 0,
              color: widget.color ?? scope.color,
              page: scope.page,
              child: content,
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: ValueListenableBuilder<double>(
            valueListenable: visibility,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SizeReporter(
                onSizeChanged: (size) => _height.value = size.height,
                child: _PinnedBar(
                  onBackground: scope != null,
                  child: widget.bar,
                ),
              ),
            ),
            builder: (context, shown, bar) => shown >= 1
                ? bar!
                : IgnorePointer(
                    ignoring: shown < 0.5,
                    child: FractionalTranslation(
                      translation: Offset(0, -(1 - shown)),
                      child: Opacity(
                        opacity: shown.clamp(0.0, 1.0),
                        child: bar,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The box of the page that [AdaptiveScrollEdgeRegion.top] is measured in.
class _PageBox {
  RenderBox? box;
}

class _RegionScope extends InheritedWidget {
  const _RegionScope({
    required this.region,
    required this.top,
    required this.pinned,
    required this.color,
    required this.page,
    required super.child,
  });

  final AdaptiveScrollEdgeRegion region;

  /// [AdaptiveScrollEdgeRegion.top], or further down below an
  /// [AdaptiveSafeAreaBar].
  final double? top;

  /// Whether something sits pinned below the bar ([AdaptiveSafeAreaBar]).
  final bool pinned;

  /// The colour of the bar's background here.
  final Color? color;
  final _PageBox page;

  @override
  bool updateShouldNotify(_RegionScope oldWidget) =>
      region.chrome != oldWidget.region.chrome ||
      region.placement != oldWidget.region.placement ||
      top != oldWidget.top ||
      pinned != oldWidget.pinned ||
      color != oldWidget.color ||
      region.titleBand != oldWidget.region.titleBand ||
      region.hairline != oldWidget.region.hairline ||
      region.visibility != oldWidget.region.visibility ||
      region.color != oldWidget.region.color ||
      region.data != oldWidget.region.data;
}

class _PageMarker extends SingleChildRenderObjectWidget {
  const _PageMarker({required this.page, required super.child});

  final _PageBox page;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPageMarker(page);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPageMarker renderObject,
  ) {
    renderObject.page = page;
  }
}

class _RenderPageMarker extends RenderProxyBox {
  _RenderPageMarker(this._page);

  _PageBox _page;

  set page(_PageBox value) {
    if (identical(value, _page)) return;
    if (identical(_page.box, this)) _page.box = null;
    _page = value;
    if (attached) _page.box = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _page.box = this;
  }

  @override
  void detach() {
    if (identical(_page.box, this)) _page.box = null;
    super.detach();
  }
}

/// The app's scroll behavior, with the edge effect around every vertical
/// scroll view.
class _ScrollEdgeBehavior extends ScrollBehavior {
  const _ScrollEdgeBehavior(this.parent);

  /// Around [behavior], once: a page inside another page's region keeps the
  /// app's own behavior underneath.
  factory _ScrollEdgeBehavior.around(ScrollBehavior behavior) =>
      _ScrollEdgeBehavior(
        behavior is _ScrollEdgeBehavior ? behavior.parent : behavior,
      );

  final ScrollBehavior parent;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final inner = parent.buildOverscrollIndicator(context, child, details);
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return inner;
    return _ScrollEdgeEffect(child: inner);
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => parent.buildScrollbar(context, child, details);

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      parent.getPlatform(context);

  @override
  Set<PointerDeviceKind> get dragDevices => parent.dragDevices;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      parent.getMultitouchDragStrategy(context);

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      parent.pointerAxisModifiers;

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      parent.velocityTrackerBuilder(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      parent.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => parent.getKeyboardDismissBehavior(context);

  @override
  bool shouldNotify(_ScrollEdgeBehavior oldDelegate) =>
      parent.runtimeType != oldDelegate.parent.runtimeType ||
      parent.shouldNotify(oldDelegate.parent);
}

/// The scroll views of one region, so nested ones can leave the edge to the
/// outermost, and the outermost to one inside it that reaches further.
class _EdgeNode {
  _EdgeNode(this.parent) {
    parent?.children.add(this);
  }

  final _EdgeNode? parent;
  final Set<_EdgeNode> children = <_EdgeNode>{};
  _RenderScrollEdgeEffect? renderObject;

  void dispose() => parent?.children.remove(this);
}

class _EdgeNodeScope extends InheritedWidget {
  const _EdgeNodeScope({required this.node, required super.child});

  final _EdgeNode node;

  @override
  bool updateShouldNotify(_EdgeNodeScope oldWidget) => node != oldWidget.node;
}

class _ScrollEdgeEffect extends StatefulWidget {
  const _ScrollEdgeEffect({required this.child});

  final Widget child;

  @override
  State<_ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

class _ScrollEdgeEffectState extends State<_ScrollEdgeEffect> {
  final ValueNotifier<double> _edge = ValueNotifier<double>(0);
  _EdgeNode? _node;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = context
        .dependOnInheritedWidgetOfExactType<_EdgeNodeScope>()
        ?.node;
    if (_node == null || _node!.parent != parent) {
      _node?.dispose();
      _node = _EdgeNode(parent);
    }
  }

  @override
  void dispose() {
    _node?.dispose();
    _edge.dispose();
    super.dispose();
  }

  bool _onNotification(Notification notification) {
    final (metrics, depth) = switch (notification) {
      final ScrollNotification n => (n.metrics, n.depth),
      final ScrollMetricsNotification n => (n.metrics, n.depth),
      _ => (null, 0),
    };
    if (metrics == null || depth != 0) return false;
    final edge = AdaptiveScrollEdge.of(metrics) ?? 0;
    runOutsideLayout(() => _edge.value = edge, mounted: () => mounted);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RegionScope>();
    final region = scope?.region;
    final top = scope?.top;
    return _ScrollEdgeBand(
      node: _node!,
      page: scope?.page,
      top: top,
      edge: _edge,
      visibility: region?.visibility,
      viewport: NotificationListener<Notification>(
        onNotification: _onNotification,
        child: _EdgeNodeScope(node: _node!, child: widget.child),
      ),
      band: region == null || top == null
          ? null
          : _band(
              context,
              region,
              AdaptiveBarBackgroundSpec(
                placement: region.placement,
                height: top,
                color: scope!.color,
                titleBand: region.titleBand,
                pinned: scope.pinned,
                hairline: region.hairline || scope.pinned,
                scrollEdge: _edge,
                data: region.data,
              ),
            ),
    );
  }

  Widget _band(
    BuildContext context,
    AdaptiveScrollEdgeRegion region,
    AdaptiveBarBackgroundSpec spec,
  ) {
    final background =
        region.chrome.barBackgroundBuilder?.call(context, spec) ??
        AdaptiveBarBackdrop(
          color: spec.color,
          hairline: spec.hairline ? AdaptiveBarBackdrop.defaultHairline : null,
        );
    final shown = Listenable.merge([_edge, region.visibility]);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: shown,
        child: background,
        builder: (context, child) => Opacity(
          opacity: (_edge.value * region.visibility.value).clamp(0.0, 1.0),
          child: child,
        ),
      ),
    );
  }
}

/// The background of a bar along the top as iOS 26 draws it over content
/// scrolling underneath: the content blurred and tinted with the page's
/// [color], ending in a clean edge at the bottom of the bar, set off by a
/// hairline.
///
/// Custom chrome draws it unless the app brings its own
/// ([AdaptiveChrome.barBackgroundBuilder]); the native toolbar and the iPhone
/// Duo's title band draw it too.
class AdaptiveBarBackdrop extends StatelessWidget {
  const AdaptiveBarBackdrop({
    super.key,
    this.color,
    this.blurSigma = defaultBlurSigma,
    this.tint,
    this.hairline = defaultHairline,
  });

  static const double defaultBlurSigma = 8;

  /// How much of a neutral page colour is laid over the content, as iOS
  /// does; a strong colour, such as a brand colour, is laid on thicker
  /// ([colouredTint]), so the bar reads in that colour.
  static const double defaultTint = 0.75;
  static const double colouredTint = 0.88;
  static const Color defaultHairline = Color(0x24000000);

  /// The page's colour; white if null.
  final Color? color;

  final double blurSigma;

  /// How much of [color] is laid over the blurred content; by default
  /// [defaultTint], or [colouredTint] for a strong colour.
  final double? tint;

  /// The line along the bottom edge, one pixel thick; none if null.
  final Color? hairline;

  @override
  Widget build(BuildContext context) {
    final base = (color ?? const Color(0xFFFFFFFF)).withValues(alpha: 1);
    final tint =
        this.tint ??
        (HSLColor.fromColor(base).saturation > 0.3
            ? colouredTint
            : defaultTint);
    final surface = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base.withValues(alpha: tint)),
        if (hairline case final hairline?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
            child: ColoredBox(color: hairline),
          ),
      ],
    );
    // A solid bar has nothing to show through it.
    if (tint >= 1) return surface;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.mirror,
        ),
        child: surface,
      ),
    );
  }
}

enum _BandSlot { viewport, band }

class _ScrollEdgeBand
    extends SlottedMultiChildRenderObjectWidget<_BandSlot, RenderBox> {
  const _ScrollEdgeBand({
    required this.node,
    required this.page,
    required this.top,
    required this.edge,
    required this.visibility,
    required this.viewport,
    required this.band,
  });

  final _EdgeNode node;
  final _PageBox? page;
  final double? top;
  final ValueListenable<double> edge;
  final ValueListenable<double>? visibility;
  final Widget viewport;
  final Widget? band;

  @override
  Iterable<_BandSlot> get slots => _BandSlot.values;

  @override
  Widget? childForSlot(_BandSlot slot) => switch (slot) {
    _BandSlot.viewport => viewport,
    _BandSlot.band => band,
  };

  @override
  _RenderScrollEdgeEffect createRenderObject(BuildContext context) =>
      _RenderScrollEdgeEffect(node: node, page: page, top: top)
        ..edge = edge
        ..visibility = visibility;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollEdgeEffect renderObject,
  ) {
    renderObject
      ..node = node
      ..page = page
      ..top = top
      ..edge = edge
      ..visibility = visibility;
  }
}

class _RenderScrollEdgeEffect extends RenderBox
    with SlottedContainerRenderObjectMixin<_BandSlot, RenderBox> {
  _RenderScrollEdgeEffect({
    required _EdgeNode node,
    required _PageBox? page,
    required double? top,
  }) : _node = node,
       _page = page,
       _top = top;

  _EdgeNode _node;

  set node(_EdgeNode value) {
    if (identical(value, _node)) return;
    if (identical(_node.renderObject, this)) _node.renderObject = null;
    _node = value;
    if (attached) _node.renderObject = this;
  }

  _PageBox? _page;

  set page(_PageBox? value) {
    if (identical(value, _page)) return;
    _page = value;
    markNeedsPaint();
  }

  double? _top;

  set top(double? value) {
    if (value == _top) return;
    _top = value;
    markNeedsLayout();
  }

  ValueListenable<double>? edge;
  ValueListenable<double>? visibility;

  bool _paints = false;

  RenderBox? get _viewport => childForSlot(_BandSlot.viewport);
  RenderBox? get _band => childForSlot(_BandSlot.band);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _node.renderObject = this;
  }

  @override
  void detach() {
    if (identical(_node.renderObject, this)) _node.renderObject = null;
    super.detach();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _viewport?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _viewport?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _viewport?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _viewport?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _viewport?.getDistanceToActualBaseline(baseline);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _viewport?.getDryLayout(constraints) ?? constraints.smallest;

  @override
  void performLayout() {
    final viewport = _viewport;
    if (viewport == null) {
      size = constraints.smallest;
    } else {
      viewport.layout(constraints, parentUsesSize: true);
      size = viewport.size;
    }
    _band?.layout(
      BoxConstraints.tight(Size(size.width, math.max(0, _top ?? 0))),
    );
  }

  /// Where this scroll view is on its page, or null when it is not on one
  /// that is laid out.
  Rect? _onPage() {
    final page = _page?.box;
    if (page == null || !page.attached || !page.hasSize || !hasSize) {
      return null;
    }
    final RenderObject ancestor = page;
    RenderObject? node = this;
    while (node != null && node != ancestor) {
      node = node.parent;
    }
    if (node == null) return null;
    return MatrixUtils.transformRect(getTransformTo(page), Offset.zero & size);
  }

  bool _underTop(Rect rect) {
    final top = _top;
    return top != null && rect.top < top - 0.5 && rect.bottom > 0;
  }

  /// The outermost scroll view under the bars draws the edge: its content is
  /// what runs under them.
  bool _ancestorTakesIt() {
    for (var node = _node.parent; node != null; node = node.parent) {
      final renderObject = node.renderObject;
      if (renderObject == null || !renderObject.attached) continue;
      if (!identical(renderObject._page, _page)) return false;
      final rect = renderObject._onPage();
      // One whose band reaches less far down leaves this one its own: a
      // list below something pinned in a scroll view with a header.
      if (rect != null &&
          renderObject._underTop(rect) &&
          (renderObject._top ?? 0) >= (_top ?? 0) - 0.5) {
        return true;
      }
    }
    return false;
  }

  /// A scroll view inside this one draws the bar's background over all of
  /// it: its content runs under the bars from the top of the page and its
  /// band reaches at least as far down, below something pinned under the
  /// bar. Its content is what is under the bars then, so this one leaves
  /// the band to it rather than laying a second one over the bar.
  bool _descendantTakesIt() {
    bool covers(_EdgeNode node) {
      for (final child in node.children) {
        final renderObject = child.renderObject;
        if (renderObject != null &&
            renderObject.attached &&
            renderObject._paints &&
            identical(renderObject._page, _page) &&
            (renderObject._top ?? 0) >= (_top ?? 0) - 0.5) {
          final rect = renderObject._onPage();
          if (rect != null && rect.top <= 0.5) return true;
        }
        if (covers(child)) return true;
      }
      return false;
    }

    return covers(_node);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paints = false;
    final viewport = _viewport;
    if (viewport != null) context.paintChild(viewport, offset);
    final band = _band;
    if (band == null) return;
    final rect = _onPage();
    if (rect == null ||
        !_underTop(rect) ||
        _ancestorTakesIt() ||
        _descendantTakesIt()) {
      return;
    }
    _paints = true;
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) =>
          context.paintChild(band, offset + Offset(0, -rect.top)),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!identical(child, _band)) return;
    final rect = _onPage();
    if (rect == null) return;
    transform.translateByDouble(0, -rect.top, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _viewport?.hitTest(result, position: position) ?? false;

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      identical(child, _viewport) ? null : Offset.zero & size;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final viewport = _viewport;
    if (viewport != null) visitor(viewport);
  }

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('top', _top));
  }
}

/// How far in the bar's background is where the scroll views on screen last
/// drew it, one entry for each that did: as far as content has scrolled
/// under the bar, and as far as the bar is shown.
@visibleForTesting
List<double> debugScrollEdgesOnScreen() => _paintedEdges(
  (node) => (node.edge?.value ?? 0) * (node.visibility?.value ?? 1),
);

/// How far down the page the bar's background reaches where the scroll
/// views on screen last drew it, one entry for each that did.
@visibleForTesting
List<double> debugScrollEdgeHeightsOnScreen() =>
    _paintedEdges((node) => node._top ?? 0);

List<double> _paintedEdges(
  double Function(_RenderScrollEdgeEffect node) value,
) {
  final result = <double>[];
  bool painted(RenderObject node) {
    for (
      var child = node, parent = node.parent;
      parent != null;
      child = parent, parent = parent.parent
    ) {
      if (!parent.paintsChild(child)) return false;
    }
    return true;
  }

  void visit(RenderObject node) {
    if (node is _RenderScrollEdgeEffect &&
        node.attached &&
        node._paints &&
        painted(node)) {
      result.add(value(node));
    }
    node.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  return result;
}
