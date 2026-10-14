import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../utils/size_reporter.dart';
import '../widgets/ios26/ios26_native_tab_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// The native tab bar of the app's tab layouts, at the bottom of the screen
/// above the navigator, the way the iPhone Duo vertical bar holds the tabs on
/// its side.
///
/// Inside its page the native bar slid with the page under one that was
/// pushed over it, and Flutter had to draw that page over a moving native
/// view on every frame of the transition. Here it never moves and nothing is
/// drawn over it. It stays put and at full opacity while the pages within the
/// tabs change.
///
/// A native view on screen still makes every frame dearer while pages move,
/// so the bar is out of the way for most of a transition between the tabs and
/// a page without them, and for all of its end, where a stutter shows most:
/// it fades out over the first fifth of a push, and stays away while a page
/// pops or is swiped back off the tabs, to fade in once the tabs hold still.
///
/// The native view is made once per tab layout and kept for as long as the
/// layout is mounted: off stage while a page covers the tabs, so it is not
/// made again at the start of every pop.
class HostedTabBar extends StatefulWidget {
  const HostedTabBar({super.key, required this.blend, required this.height});

  final ToolbarBlend blend;

  /// Set to the height the bar covers at the bottom of the screen, for the
  /// tab layout to keep its content clear of it.
  final ValueNotifier<double> height;

  @override
  State<HostedTabBar> createState() => _HostedTabBarState();
}

class _HostedTabBarState extends State<HostedTabBar>
    with SingleTickerProviderStateMixin {
  /// The tab layouts the last build drew a bar for.
  List<ToolbarEntry> _built = const <ToolbarEntry>[];

  /// The opacity of the bar in front: it fades in once the pages hold still
  /// after a transition that brought the tabs in.
  late final AnimationController _reveal;

  /// Whether a transition running now, or that just ended, brings a bar in.
  bool _revealPending = false;

  /// How far into a push the bar of the page going out is gone, and so off
  /// screen for the rest of it.
  static const double _leaveBy = 0.2;

  static final Animatable<double> _leaveOnPush = Tween<double>(begin: 1, end: 0)
      .chain(
        CurveTween(curve: const Interval(0, _leaveBy, curve: Curves.easeOut)),
      );

  /// The same, for a pop: the driver runs from 1 down to 0.
  static final Animatable<double> _leaveOnPop = CurveTween(
    curve: const Interval(1 - _leaveBy, 1, curve: Curves.easeIn),
  );

  /// Fully out while a dialog or sheet covers the tabs: the bar would show
  /// above them, as it sits above the navigator.
  late Animation<double> _uncovered;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: kToolbarItemSwapDuration,
      value: 1,
    );
    _listen(widget.blend);
  }

  @override
  void didUpdateWidget(HostedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.blend, widget.blend)) {
      _unlisten(oldWidget.blend);
      _listen(widget.blend);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.blend);
    _reveal.dispose();
    super.dispose();
  }

  void _listen(ToolbarBlend blend) {
    _uncovered = ReverseAnimation(blend.cover);
    blend.addListener(_rebuild);
    blend.registry.addListener(_onRegistryChanged);
  }

  void _unlisten(ToolbarBlend blend) {
    blend.removeListener(_rebuild);
    blend.registry.removeListener(_onRegistryChanged);
  }

  void _rebuild() {
    _updateReveal();
    setState(() {});
  }

  /// Whether the running transition shows the upper page coming in: a push,
  /// or a crossfade between two tab layouts. Otherwise it is a pop or a back
  /// swipe, which uncover the lower page.
  bool get _bringsUpperIn {
    final blend = widget.blend;
    return blend.upperOwns && !blend.isGestureBlend;
  }

  /// While pages move between two tab layouts, or between the tabs and a page
  /// without them: the tab layout whose bar goes out, and the one whose bar
  /// comes in. Both null while the pages within one tab layout change.
  (ToolbarEntry?, ToolbarEntry?) _goingAndComing() {
    final blend = widget.blend;
    final registry = blend.registry;
    final upper = registry.tabBarOwnerFor(blend.upper);
    final lower = registry.tabBarOwnerFor(blend.lower);
    if (upper?.id == lower?.id) return (null, null);
    return _bringsUpperIn ? (lower, upper) : (upper, lower);
  }

  /// Notes a bar that a transition brings in, which waits off stage while the
  /// pages move, and fades it in once they hold still.
  void _updateReveal() {
    final blend = widget.blend;
    if (blend.isBlending) {
      if (_goingAndComing().$2 != null) _revealPending = true;
      return;
    }
    if (_revealPending && blend.registry.tabBarOwnerFor(blend.owner) != null) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _reveal.value = 1;
      } else {
        _reveal.forward(from: 0);
      }
    }
    _revealPending = false;
  }

  /// The blend only tells of the pages in front. A tab layout that is
  /// covered or comes and goes is only seen here.
  void _onRegistryChanged() {
    if (listEquals(_hosted(), _built)) return;
    setState(() {});
  }

  List<ToolbarEntry> _hosted() => [
    for (final entry in widget.blend.registry.entries)
      if (entry.tabBarHosted && (entry.tabBar?.items?.isNotEmpty ?? false))
        entry,
  ];

  @override
  Widget build(BuildContext context) {
    final blend = widget.blend;
    final registry = blend.registry;
    _built = _hosted();
    final ownerTabs = registry.tabBarOwnerFor(blend.owner);
    // The bar that stays in view: the owner's, or while pages move, the one
    // of the tab layout on both sides of the transition. A bar that comes in
    // waits off stage until the pages hold still.
    final upperTabs = registry.tabBarOwnerFor(blend.upper);
    final lowerTabs = registry.tabBarOwnerFor(blend.lower);
    final driver = blend.driver;
    final shown = driver == null
        ? ownerTabs
        : upperTabs?.id == lowerTabs?.id
        ? upperTabs
        : null;
    final going = driver == null ? null : _goingAndComing().$1;
    final leave = driver?.drive(_bringsUpperIn ? _leaveOnPush : _leaveOnPop);
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        opacity: _uncovered,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in _built)
              _layer(
                entry,
                opacity: entry.id == shown?.id
                    ? _reveal
                    : entry.id == going?.id
                    ? leave
                    : null,
                interactive: entry.id == ownerTabs?.id,
              ),
          ],
        ),
      ),
    );
  }

  /// The bar of one tab layout; off stage while no [opacity] shows it. The
  /// widgets around the native bar are the same in every state, so it is
  /// never made again.
  Widget _layer(
    ToolbarEntry entry, {
    required Animation<double>? opacity,
    required bool interactive,
  }) {
    final bar = entry.tabBar!;
    return Positioned(
      key: ValueKey<(String, Object)>(('adaptive_hosted_tabs', entry.id)),
      left: 0,
      right: 0,
      bottom: 0,
      child: Offstage(
        offstage: opacity == null,
        child: IgnorePointer(
          ignoring: !interactive,
          // See HostedTopToolbar._layer: in the semantics tree at every
          // opacity, left out while it is not the tabs of the page in front.
          child: FadeTransition(
            opacity: opacity ?? kAlwaysDismissedAnimation,
            alwaysIncludeSemantics: true,
            child: ExcludeSemantics(
              excluding: !interactive,
              // Laid out off stage too, so the height holds while a page
              // covers the tabs, and the tabs are not laid out again for it.
              child: SizeReporter(
                onSizeChanged: (size) => widget.height.value = size.height,
                child: _Minimizable(
                  minimized: entry.tabBarMinimized,
                  child: IOS26NativeTabBar(
                    destinations: bar.items!,
                    selectedIndex: bar.selectedIndex!,
                    onTap: bar.onTap!,
                    tint:
                        bar.selectedItemColor ??
                        CupertinoTheme.of(context).primaryColor,
                    unselectedItemTint: bar.unselectedItemColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shrinks the bar while its tab layout scrolls, as `minimizeBehavior` asks.
class _Minimizable extends StatelessWidget {
  const _Minimizable({required this.minimized, required this.child});

  final ValueListenable<bool>? minimized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: minimized ?? const AlwaysStoppedAnimation<bool>(false),
      child: child,
      builder: (context, minimized, child) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: minimized ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: child,
        // As the bar in the page does: 70% of its size and half its opacity.
        builder: (context, progress, child) => Transform.scale(
          scale: 1 - progress * 0.3,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: 1 - progress * 0.5, child: child),
        ),
      ),
    );
  }
}
