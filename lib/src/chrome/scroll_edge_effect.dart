import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'adaptive_chrome.dart';

/// The scroll edge effect of custom chrome, as iOS 26 draws it: part of each
/// scroll view whose content runs under the bars, not a layer over the whole
/// page.
///
/// A page wraps its body in one. Every vertical scroll view inside it then
/// draws the app's bar background ([AdaptiveChrome.barBackgroundBuilder])
/// over its own content where that content runs under the bars along the top
/// ([top]) and the bottom ([bottom]) of the page, fading in as content
/// scrolls under them ([AdaptiveScrollEdge]). Whatever the page lays over a
/// scroll view stays clear of it: a header pinned above a list, a search
/// field, a segmented control floating at the bottom. Content that does not
/// scroll, such as a map, gets none.
///
/// Where scroll views nest, the outermost one under the bars along the top
/// draws it there, as its content is what runs under them, and the innermost
/// one along the bottom.
///
/// Along the bottom there is only an edge where the tab bar sits there
/// ([bottomChrome]) or a control the page floats over its content asks for
/// one ([AdaptiveBottomControl]). The home indicator alone gets none, nor
/// does an accessory floating on its own.
///
/// A scroll view below something the page pins above it, such as a search
/// field or tabs, and clear of the bars, fades its content out at its own top
/// as it scrolls under that: a soft edge in the page's colour
/// ([AdaptiveChromeMetrics.pinnedEdgeHeight]) instead of a hard line.
class AdaptiveScrollEdgeRegion extends StatefulWidget {
  const AdaptiveScrollEdgeRegion({
    super.key,
    required this.chrome,
    required this.placement,
    required this.top,
    required this.bottom,
    required this.child,
    this.titleBand = false,
    this.bottomChrome = true,
    this.topColor,
    this.bottomColor,
    this.data,
  });

  final AdaptiveChrome chrome;
  final AdaptiveChromePlacement placement;

  /// How far down the page the bars along its top reach, from the top of the
  /// page. Null where nothing covers it there.
  final double? top;

  /// The bars along the top are the iPhone Duo's title band.
  final bool titleBand;

  /// How far up the page the chrome along its bottom reaches: a tab bar, an
  /// accessory, the home indicator. 0 where nothing covers it there.
  final double bottom;

  /// Whether the tab bar sits along the bottom of the page (with its
  /// accessory). Without it the scroll views draw no edge there, not for an
  /// accessory floating on its own either, unless the page floats a control
  /// there ([AdaptiveBottomControl]).
  final bool bottomChrome;

  /// The colour along the top: a header's, or the page's own.
  final Color? topColor;

  /// The colour along the bottom: the page's own.
  final Color? bottomColor;

  /// The app's data for the bar background ([AdaptiveAppBar.chromeData]).
  final Object? data;

  final Widget child;

  /// The region of the scroll views around [context], if any.
  static AdaptiveScrollEdgeRegion? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RegionScope>()?.region;

  @override
  State<AdaptiveScrollEdgeRegion> createState() =>
      _AdaptiveScrollEdgeRegionState();
}

class _AdaptiveScrollEdgeRegionState extends State<AdaptiveScrollEdgeRegion> {
  final _PageBox _page = _PageBox();
  final _BottomControls _controls = _BottomControls();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controls.outer = context
        .dependOnInheritedWidgetOfExactType<_RegionScope>()
        ?.controls;
  }

  @override
  void dispose() {
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PageMarker(
      page: _page,
      child: _RegionScope(
        region: widget,
        page: _page,
        controls: _controls,
        child: ScrollConfiguration(
          behavior: _ScrollEdgeBehavior.around(ScrollConfiguration.of(context)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The box of the page that [AdaptiveScrollEdgeRegion.top] and
/// [AdaptiveScrollEdgeRegion.bottom] are measured in.
class _PageBox {
  RenderBox? box;
}

/// How many controls the page floats along its bottom
/// ([AdaptiveBottomControl]), counting those of the page around it: a control
/// floating over a page floats over the pages inside it too.
class _BottomControls extends ChangeNotifier {
  int _count = 0;
  bool _disposed = false;
  _BottomControls? _outer;

  bool get any => _count > 0 || (_outer?.any ?? false);

  set outer(_BottomControls? value) {
    if (identical(value, _outer)) return;
    final wasAny = any;
    _outer?.removeListener(_onOuter);
    _outer = value?..addListener(_onOuter);
    if (any != wasAny) notifyListeners();
  }

  void _onOuter() {
    if (_count == 0) notifyListeners();
  }

  /// Applied after the frame: a control comes and goes while the page is
  /// built, and the scroll views listening are built with it.
  void change(int delta) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final wasAny = any;
      _count += delta;
      if (any != wasAny) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _outer?.removeListener(_onOuter);
    super.dispose();
  }
}

/// A control floating at the bottom of a page, over its scroll views, such
/// as a segmented control that switches what the page lists.
///
/// While one is on a page with no chrome along its bottom, the page's scroll
/// views keep their edge there ([AdaptiveScrollEdgeRegion]), so content
/// fades out under the control rather than running into it.
class AdaptiveBottomControl extends StatefulWidget {
  const AdaptiveBottomControl({super.key, required this.child});

  final Widget child;

  @override
  State<AdaptiveBottomControl> createState() => _AdaptiveBottomControlState();
}

class _AdaptiveBottomControlState extends State<AdaptiveBottomControl> {
  _BottomControls? _controls;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controls = context
        .dependOnInheritedWidgetOfExactType<_RegionScope>()
        ?.controls;
    if (identical(controls, _controls)) return;
    _controls?.change(-1);
    _controls = controls?..change(1);
  }

  @override
  void dispose() {
    _controls?.change(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RegionScope extends InheritedWidget {
  const _RegionScope({
    required this.region,
    required this.page,
    required this.controls,
    required super.child,
  });

  final AdaptiveScrollEdgeRegion region;
  final _PageBox page;
  final _BottomControls controls;

  @override
  bool updateShouldNotify(_RegionScope oldWidget) =>
      region.chrome != oldWidget.region.chrome ||
      region.placement != oldWidget.region.placement ||
      region.top != oldWidget.region.top ||
      region.titleBand != oldWidget.region.titleBand ||
      region.bottom != oldWidget.region.bottom ||
      region.bottomChrome != oldWidget.region.bottomChrome ||
      controls != oldWidget.controls ||
      region.topColor != oldWidget.region.topColor ||
      region.bottomColor != oldWidget.region.bottomColor ||
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

/// The scroll views of one region, so nested ones can leave an edge to each
/// other.
class _EdgeNode {
  _EdgeNode(this.parent);

  final _EdgeNode? parent;
  final Set<_EdgeNode> children = <_EdgeNode>{};
  _RenderScrollEdgeEffect? renderObject;
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
  final ValueNotifier<double> _top = ValueNotifier<double>(0);
  final ValueNotifier<double> _bottom = ValueNotifier<double>(0);
  _EdgeNode? _node;
  _BottomControls? _controls;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = context
        .dependOnInheritedWidgetOfExactType<_EdgeNodeScope>()
        ?.node;
    if (_node == null || _node!.parent != parent) {
      _node?.parent?.children.remove(_node);
      _node = _EdgeNode(parent);
      parent?.children.add(_node!);
    }
    final controls = context
        .dependOnInheritedWidgetOfExactType<_RegionScope>()
        ?.controls;
    if (!identical(controls, _controls)) {
      _controls?.removeListener(_onControls);
      _controls = controls?..addListener(_onControls);
    }
  }

  void _onControls() => setState(() {});

  @override
  void dispose() {
    _controls?.removeListener(_onControls);
    _node?.parent?.children.remove(_node);
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  bool _onNotification(Notification notification) {
    final (metrics, depth) = switch (notification) {
      final ScrollNotification n => (n.metrics, n.depth),
      final ScrollMetricsNotification n => (n.metrics, n.depth),
      _ => (null, 0),
    };
    if (metrics == null || depth != 0) return false;
    _top.value = AdaptiveScrollEdge.of(metrics) ?? 0;
    _bottom.value = AdaptiveScrollEdge.bottomOf(metrics) ?? 0;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RegionScope>();
    final region = scope?.region;
    final top = region?.top;
    final bottom =
        region == null ||
            region.bottom <= 0 ||
            !(region.bottomChrome || (scope!.controls.any))
        ? null
        : region.bottom;
    final pinnedHeight = region?.chrome.metrics.pinnedEdgeHeight ?? 0;
    final pinnedColor = region?.bottomColor ?? region?.topColor;
    return _ScrollEdgeBands(
      node: _node!,
      page: scope?.page,
      top: top,
      bottom: bottom,
      pinned: pinnedHeight > 0 && pinnedColor != null ? pinnedHeight : null,
      topEdge: _top,
      bottomEdge: _bottom,
      viewport: NotificationListener<Notification>(
        onNotification: _onNotification,
        child: _EdgeNodeScope(node: _node!, child: widget.child),
      ),
      topBand: region == null || top == null
          ? null
          : _band(
              context,
              region,
              AdaptiveBarBackgroundSpec(
                placement: region.placement,
                height: top,
                color: region.topColor,
                titleBand: region.titleBand,
                scrollEdge: _top,
                data: region.data,
              ),
              _top,
            ),
      bottomBand: region == null || bottom == null
          ? null
          : _band(
              context,
              region,
              AdaptiveBarBackgroundSpec(
                placement: region.placement,
                height: bottom,
                color: region.bottomColor,
                bottom: true,
                scrollEdge: _bottom,
                data: region.data,
              ),
              _bottom,
            ),
      pinnedBand: pinnedHeight <= 0 || pinnedColor == null
          ? null
          : IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _top,
                child: _PinnedEdge(color: pinnedColor),
                builder: (context, value, child) =>
                    Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              ),
            ),
    );
  }

  Widget _band(
    BuildContext context,
    AdaptiveScrollEdgeRegion region,
    AdaptiveBarBackgroundSpec spec,
    ValueListenable<double> edge,
  ) {
    final background =
        region.chrome.barBackgroundBuilder?.call(context, spec) ??
        _DefaultEdge(spec: spec);
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: edge,
        child: background,
        builder: (context, value, child) =>
            Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
    );
  }
}

/// A fade into the page's colour, for chrome without a bar background of
/// its own.
class _DefaultEdge extends StatelessWidget {
  const _DefaultEdge({required this.spec});

  final AdaptiveBarBackgroundSpec spec;

  @override
  Widget build(BuildContext context) {
    final base = (spec.color ?? const Color(0xFFFFFFFF)).withValues(alpha: 1);
    return OverflowBox(
      alignment: spec.bottom ? Alignment.bottomCenter : Alignment.topCenter,
      maxHeight: double.infinity,
      child: Container(
        height: spec.height + 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: spec.bottom ? Alignment.bottomCenter : Alignment.topCenter,
            end: spec.bottom ? Alignment.topCenter : Alignment.bottomCenter,
            stops: const [0.0, 0.4, 0.7, 1.0],
            colors: [
              base.withValues(alpha: 0.85),
              base.withValues(alpha: 0.6),
              base.withValues(alpha: 0.2),
              base.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The soft edge at the top of a scroll view below something pinned above
/// it: the page's colour, fading out downwards.
class _PinnedEdge extends StatelessWidget {
  const _PinnedEdge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = color.withValues(alpha: 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35, 1],
          colors: [
            base,
            base.withValues(alpha: 0.7),
            base.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

enum _BandSlot { viewport, top, bottom, pinned }

class _ScrollEdgeBands
    extends SlottedMultiChildRenderObjectWidget<_BandSlot, RenderBox> {
  const _ScrollEdgeBands({
    required this.node,
    required this.page,
    required this.top,
    required this.bottom,
    required this.pinned,
    required this.topEdge,
    required this.bottomEdge,
    required this.viewport,
    required this.topBand,
    required this.bottomBand,
    required this.pinnedBand,
  });

  final _EdgeNode node;
  final _PageBox? page;
  final double? top;
  final double? bottom;
  final double? pinned;
  final ValueListenable<double> topEdge;
  final ValueListenable<double> bottomEdge;
  final Widget viewport;
  final Widget? topBand;
  final Widget? bottomBand;
  final Widget? pinnedBand;

  @override
  Iterable<_BandSlot> get slots => _BandSlot.values;

  @override
  Widget? childForSlot(_BandSlot slot) => switch (slot) {
    _BandSlot.viewport => viewport,
    _BandSlot.top => topBand,
    _BandSlot.bottom => bottomBand,
    _BandSlot.pinned => pinnedBand,
  };

  @override
  _RenderScrollEdgeEffect createRenderObject(BuildContext context) =>
      _RenderScrollEdgeEffect(
          node: node,
          page: page,
          top: top,
          bottom: bottom,
          pinned: pinned,
        )
        ..topEdge = topEdge
        ..bottomEdge = bottomEdge;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollEdgeEffect renderObject,
  ) {
    renderObject
      ..node = node
      ..page = page
      ..top = top
      ..bottom = bottom
      ..pinned = pinned
      ..topEdge = topEdge
      ..bottomEdge = bottomEdge;
  }
}

class _RenderScrollEdgeEffect extends RenderBox
    with SlottedContainerRenderObjectMixin<_BandSlot, RenderBox> {
  _RenderScrollEdgeEffect({
    required _EdgeNode node,
    required _PageBox? page,
    required double? top,
    required double? bottom,
    required double? pinned,
  }) : _node = node,
       _page = page,
       _top = top,
       _bottom = bottom,
       _pinned = pinned;

  /// How far past the bars the app's background may fade into the content.
  static const double _fadeAllowance = 64;

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

  double? _bottom;

  set bottom(double? value) {
    if (value == _bottom) return;
    _bottom = value;
    markNeedsLayout();
  }

  double? _pinned;

  set pinned(double? value) {
    if (value == _pinned) return;
    _pinned = value;
    markNeedsLayout();
  }

  ValueListenable<double>? topEdge;
  ValueListenable<double>? bottomEdge;

  bool _paintsTop = false;
  bool _paintsBottom = false;
  bool _paintsPinned = false;

  RenderBox? get _viewport => childForSlot(_BandSlot.viewport);
  RenderBox? get _topBand => childForSlot(_BandSlot.top);
  RenderBox? get _bottomBand => childForSlot(_BandSlot.bottom);
  RenderBox? get _pinnedBand => childForSlot(_BandSlot.pinned);

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
    _topBand?.layout(BoxConstraints.tight(Size(size.width, _top ?? 0)));
    _bottomBand?.layout(BoxConstraints.tight(Size(size.width, _bottom ?? 0)));
    _pinnedBand?.layout(
      BoxConstraints.tight(
        Size(size.width, math.min(_pinned ?? 0, size.height)),
      ),
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
    return top != null && rect.top < top + _fadeAllowance && rect.bottom > 0;
  }

  bool _overBottom(Rect rect, double pageHeight) {
    final bottom = _bottom;
    return bottom != null &&
        rect.bottom > pageHeight - bottom - _fadeAllowance &&
        rect.top < pageHeight;
  }

  /// Along the top the outermost scroll view draws the edge: its content is
  /// what runs under the bars there.
  bool _ancestorTakesTop() {
    for (var node = _node.parent; node != null; node = node.parent) {
      final renderObject = node.renderObject;
      if (renderObject == null || !renderObject.attached) continue;
      if (!identical(renderObject._page, _page)) return false;
      final rect = renderObject._onPage();
      if (rect != null && renderObject._underTop(rect)) return true;
    }
    return false;
  }

  /// Whether a scroll view on the same page holds this one: its content is
  /// what scrolls, so this one has nothing pinned above it.
  bool _insideAnother() {
    for (var node = _node.parent; node != null; node = node.parent) {
      final renderObject = node.renderObject;
      if (renderObject == null || !renderObject.attached) continue;
      if (identical(renderObject._page, _page)) return true;
    }
    return false;
  }

  /// Along the bottom the innermost one does.
  bool _descendantTakesBottom(Rect own, double pageHeight) {
    final pending = <_EdgeNode>[..._node.children];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      pending.addAll(node.children);
      final renderObject = node.renderObject;
      if (renderObject == null || !renderObject.attached) continue;
      if (!identical(renderObject._page, _page)) continue;
      final rect = renderObject._onPage();
      if (rect == null || !rect.overlaps(own)) continue;
      if (renderObject._overBottom(rect, pageHeight)) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintsTop = false;
    _paintsBottom = false;
    _paintsPinned = false;
    final viewport = _viewport;
    if (viewport != null) context.paintChild(viewport, offset);
    final topBand = _topBand;
    final bottomBand = _bottomBand;
    final pinnedBand = _pinnedBand;
    if (topBand == null && bottomBand == null && pinnedBand == null) return;
    final rect = _onPage();
    final pageHeight = _page?.box?.size.height;
    if (rect == null || pageHeight == null) return;
    final clip = Offset.zero & size;
    // Below something the page pins above it, clear of the bars: a soft
    // edge at its own top.
    if (pinnedBand != null &&
        rect.top > 0.5 &&
        !_underTop(rect) &&
        !_insideAnother()) {
      _paintsPinned = true;
      context.paintChild(pinnedBand, offset);
    }
    if (topBand != null && _underTop(rect) && !_ancestorTakesTop()) {
      _paintsTop = true;
      context.pushClipRect(
        needsCompositing,
        offset,
        clip,
        (context, offset) =>
            context.paintChild(topBand, offset + Offset(0, -rect.top)),
      );
    }
    if (bottomBand != null &&
        _overBottom(rect, pageHeight) &&
        !_descendantTakesBottom(rect, pageHeight)) {
      _paintsBottom = true;
      final y = pageHeight - rect.top - (_bottom ?? 0);
      context.pushClipRect(
        needsCompositing,
        offset,
        clip,
        (context, offset) =>
            context.paintChild(bottomBand, offset + Offset(0, y)),
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _viewport) || identical(child, _pinnedBand)) return;
    final rect = _onPage();
    if (rect == null) return;
    if (identical(child, _topBand)) {
      transform.translateByDouble(0, -rect.top, 0, 1);
    } else if (identical(child, _bottomBand)) {
      final pageHeight = _page?.box?.size.height ?? 0;
      transform.translateByDouble(
        0,
        pageHeight - rect.top - (_bottom ?? 0),
        0,
        1,
      );
    }
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
    properties
      ..add(DoubleProperty('top', _top))
      ..add(DoubleProperty('bottom', _bottom))
      ..add(DoubleProperty('pinned', _pinned));
  }
}

/// What the scroll views on screen last drew of the scroll edge effect: for
/// each one, how far its background along the top and along the bottom, and
/// its soft edge below something pinned above it, are in, or null where it
/// draws none there.
@visibleForTesting
List<({double? top, double? bottom, double? pinned})>
debugScrollEdgesOnScreen() {
  final result = <({double? top, double? bottom, double? pinned})>[];
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
    if (node is _RenderScrollEdgeEffect && node.attached && painted(node)) {
      result.add((
        top: node._paintsTop ? node.topEdge?.value ?? 0 : null,
        bottom: node._paintsBottom ? node.bottomEdge?.value ?? 0 : null,
        pinned: node._paintsPinned ? node.topEdge?.value ?? 0 : null,
      ));
    }
    node.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  return result;
}
