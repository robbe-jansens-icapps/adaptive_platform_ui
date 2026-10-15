
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:foldable/foldable.dart';

import '../chrome/adaptive_chrome.dart';
import '../chrome/scroll_edge_effect.dart';
import '../platform/system_vertical_bar.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_bottom_navigation_bar.dart';
import '../widgets/adaptive_popover.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/ios26/ios26_popup_menu_button.dart';
import '../widgets/ios26/ios26_glass_capsule.dart';

/// Width of the strip the vertical control bar lives in when the system
/// reserves none: the leading pane in Split View, or a missing inset. Matches
/// the hardware strip of the inner display (the bar's centre sits 48 points
/// from the edge in both), which the system mirrors there. Where the system
/// does reserve the strip, the bar takes the width of that inset instead.
const double kDuoVerticalBarWidth = 84.0;

/// Top clearance of the vertical bar in a strip without hardware (the leading
/// Split View pane). Matches UIKit's `bar(onEdge:extent:)` layout region there.
const double kDuoBarOnlyTopMargin = 16.0;

/// How far the control band extends inward beyond the system strip, so the
/// centred controls sit a few points off the bezel instead of hugging the
/// display edge.
const double kDuoVerticalBarBezelInset = 12.0;

/// Clearance used below the top edge until the system has reported where the
/// camera and status cluster are. It covers the taller of the two displays, so
/// controls never start out underneath the cluster.
const double kDuoStatusClusterFallbackHeight = 170.0;

/// The edge of the window the system reserves for vertical controls.
enum DuoBarSide { left, right }

/// The resolved iPhone Duo layout for a window: which edge the vertical bar is
/// on and how wide its strip is.
@immutable
class DuoPose {
  const DuoPose({required this.side, required this.stripWidth, required this.reservedBySystem});

  final DuoBarSide side;

  /// Width of the strip the bar sits in.
  final double stripWidth;

  /// True when the strip is a system safe-area inset, holding the status
  /// cluster or camera. False in the leading Split View pane: the system
  /// wants a vertical bar there, but only adds its inset for bars it draws
  /// itself, never for a Flutter view.
  final bool reservedBySystem;

  bool get onLeft => side == DuoBarSide.left;

  /// Width of the band the bar is laid out in: the strip plus
  /// [kDuoVerticalBarBezelInset].
  double get bandWidth => stripWidth + kDuoVerticalBarBezelInset;

  /// Distance from the window's top to the centre of the bar's first control,
  /// with no camera or status cluster above it. The title is centred on it.
  double get firstControlCenter => (reservedBySystem ? kDuoBarEdgeMargin : kDuoBarOnlyTopMargin) + IOS26GlassCapsule.width / 2;

  /// [insets] with the strip added on the bar's side: the inset UIKit would
  /// have reserved for a vertical bar it draws itself.
  EdgeInsets addStrip(EdgeInsets insets) => onLeft ? insets.copyWith(left: insets.left + stripWidth) : insets.copyWith(right: insets.right + stripWidth);

  @override
  bool operator ==(Object other) => other is DuoPose && other.side == side && other.stripWidth == stripWidth && other.reservedBySystem == reservedBySystem;

  @override
  int get hashCode => Object.hash(side, stripWidth, reservedBySystem);

  @override
  String toString() =>
      '${side.name} ${stripWidth.toStringAsFixed(0)}pt '
      '(${reservedBySystem ? 'system strip' : 'bar-only strip'})';
}

/// Layout decisions for iPhone Duo.
abstract final class DuoLayout {
  /// The Duo layout for a window, or null where bars stay horizontal.
  ///
  /// The safe-area insets decide where they name a side ([barSide]). The
  /// system's own [edge] only adds a vertical pose where they name none, which
  /// is the leading Split View pane: it has no side inset, so the edge is the
  /// only signal there. The insets win because they arrive with the frame,
  /// while the edge comes on its own channel and can be a frame stale after a
  /// pane move.
  static DuoPose? resolvePose(EdgeInsets viewPadding, SystemVerticalBarEdge edge) {
    final side =
        barSide(viewPadding) ??
        switch (edge) {
          SystemVerticalBarEdge.left => DuoBarSide.left,
          SystemVerticalBarEdge.right => DuoBarSide.right,
          SystemVerticalBarEdge.none || SystemVerticalBarEdge.unknown => null,
        };
    if (side == null) return null;
    final inset = side == DuoBarSide.left ? viewPadding.left : viewPadding.right;
    return DuoPose(side: side, stripWidth: inset > 0 ? inset : kDuoVerticalBarWidth, reservedBySystem: inset > 0);
  }

  /// The edge the safe-area insets alone put the bar on, or null where they
  /// say bars stay horizontal. [resolvePose] trusts it first and consults the
  /// system's vertical bar edge only when this returns null.
  ///
  /// Decided from what the system actually reserves rather than from a device
  /// or size class. On iPhone Duo the controls stay aligned with the hardware:
  /// the window has an inset on one side only, with no top inset. That strip
  /// holds the camera and status cluster, and measurements put it on the right
  /// in every pose that has it: the inner display in both landscape rotations,
  /// and the cover display while folded. A pane that does not touch the
  /// hardware strip reports no inset at all, which is why the leading Split
  /// View pane (the one real left-bar case) needs the system's edge instead.
  /// The strip is absent where bars stay horizontal:
  ///
  /// * any other iPhone in portrait has a top inset, and in landscape has
  ///   equal insets on both sides;
  /// * an iPad has no side inset;
  /// * the Duo inner display in portrait has a top inset.
  ///
  /// A left inset is handled too, although no pose has been observed to
  /// report one.
  ///
  /// Pass the *view* padding: it is known on the very first frame, and unlike
  /// `padding` it is not consumed by a `SafeArea` further up the tree.
  static DuoBarSide? barSide(EdgeInsets viewPadding) {
    if (viewPadding.top != 0) return null;
    if (viewPadding.right > 0 && viewPadding.left == 0) return DuoBarSide.right;
    if (viewPadding.left > 0 && viewPadding.right == 0) return DuoBarSide.left;
    return null;
  }

  /// Whether toolbar controls belong in a vertical bar right now.
  static bool isVerticalBarPose(EdgeInsets viewPadding) => barSide(viewPadding) != null;

  /// Free space to keep above and below the controls, so that they clear the
  /// camera and status cluster wherever the current rotation puts them: at
  /// the top of the strip in portrait, at the bottom of it in one landscape
  /// rotation. Measured on the system's own bar: controls start right at the
  /// edge of a region, and keep [kDuoBarEdgeMargin] from a free window edge.
  static ({double top, double bottom}) barInsets({required Size size, required DuoPose pose, required List<ReservedRegion> regions}) {
    // A strip the system did not reserve has no camera or status cluster in
    // it. No region will ever be reported there, so don't wait for one.
    if (!pose.reservedBySystem) {
      return (top: kDuoBarOnlyTopMargin, bottom: kDuoBarEdgeMargin);
    }
    final stripStart = pose.onLeft ? 0.0 : size.width - pose.stripWidth;
    final stripEnd = pose.onLeft ? pose.stripWidth : size.width;

    // Only regions that really lie in this window's strip count. While the
    // device folds, unfolds or rotates, a reading taken in the previous pose
    // can still be around for a moment; its region sits elsewhere.
    final inStrip = regions.where(
      (r) =>
          r.kind == ReservedRegionKind.occlusion &&
          r.isActive &&
          r.bounds.right > stripStart &&
          r.bounds.left < stripEnd &&
          r.bounds.right <= size.width + 1 &&
          r.bounds.bottom <= size.height + 1,
    );

    double? top;
    double? bottom;
    for (final region in inStrip) {
      if (region.bounds.center.dy < size.height / 2) {
        if (top == null || region.bounds.bottom > top) {
          top = region.bounds.bottom;
        }
      } else {
        final room = size.height - region.bounds.top + kDuoBarRegionGap;
        if (bottom == null || room > bottom) bottom = room;
      }
    }

    // Every system-reserved strip has the camera or the status cluster
    // somewhere in it, so an empty strip means nothing has been reported for
    // this pose yet (regions arrive a moment after launch and after a pose
    // change). Until then stay clear of where the cluster can be instead of
    // starting underneath it.
    final unknown = inStrip.isEmpty;
    return (top: top ?? (unknown ? kDuoStatusClusterFallbackHeight : kDuoBarEdgeMargin), bottom: bottom ?? kDuoBarEdgeMargin);
  }

  /// Top clearance of [barInsets].
  static double topClearance({required Size size, required DuoPose pose, required List<ReservedRegion> regions}) => barInsets(size: size, pose: pose, regions: regions).top;
}

/// Hands the resolved [DuoPose] to everything below, so the bar, the title
/// and the page body agree on one decision instead of re-reading insets the
/// host may have adjusted.
class DuoPoseScope extends InheritedWidget {
  const DuoPoseScope({super.key, required this.pose, required super.child});

  /// The pose in effect, or null where bars stay horizontal.
  final DuoPose? pose;

  /// The nearest scope, or null when there is none. Tells "no scope" apart
  /// from a scope whose pose is null (a decision for horizontal bars).
  static DuoPoseScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DuoPoseScope>();

  /// The pose in effect here. Without a scope, derived from the insets alone.
  static DuoPose? of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope.pose;
    return DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), SystemVerticalBarEdge.unknown);
  }

  @override
  bool updateShouldNotify(DuoPoseScope oldWidget) => pose != oldWidget.pose;
}

/// Space the system leaves between the controls and a free edge of the
/// window, above the first control and below the tab capsule.
const double kDuoBarEdgeMargin = 24.0;

/// Space the system leaves between the controls and a reserved region that
/// sits below them.
const double kDuoBarRegionGap = 11.0;

/// Height of the band at the top of the page that holds the title on iPhone
/// Duo. The system sets the title at the leading edge, centred 48 points
/// below the top, with the controls in the trailing bar instead of beside it.
const double kDuoTitleBandHeight = 70.0;

/// What sits behind the title on iPhone Duo once content scrolls under it:
/// the content blurred and tinted, as behind every bar along the top
/// ([AdaptiveBarBackdrop]), ending in a clean edge below the band.
class DuoTitleBackdrop extends StatelessWidget {
  const DuoTitleBackdrop({super.key, this.color});

  /// The color of the page behind the band; the system background if null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AdaptiveBarBackdrop(color: color ?? CupertinoColors.systemBackground.resolveFrom(context)),
    );
  }
}

/// The iPhone Duo's title band as it moves out of the way while a page
/// scrolls on and comes back as it scrolls back ([shown]): up and out of
/// sight, and inert once mostly gone.
class DuoTitleBandTransition extends StatelessWidget {
  const DuoTitleBandTransition({super.key, required this.shown, required this.child});

  final ValueListenable<double> shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: shown,
      child: child,
      builder: (context, value, child) => value >= 1
          ? child!
          : IgnorePointer(
              ignoring: value < 0.5,
              child: FractionalTranslation(
                translation: Offset(0, value - 1),
                child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              ),
            ),
    );
  }
}

/// The page title as iPhone Duo shows it: at the leading edge rather than
/// centred, because the navigation controls live in the trailing bar.
class DuoToolbarTitle extends StatelessWidget {
  const DuoToolbarTitle({super.key, this.title, this.titleWidget});

  final String? title;

  /// Replaces [title] (a custom widget, or a title with a subtitle).
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final pose = DuoPoseScope.of(context);
    final strip = pose?.stripWidth ?? 0;
    final onLeft = pose?.onLeft ?? false;
    final center = pose?.firstControlCenter ?? kDuoBarEdgeMargin + IOS26GlassCapsule.width / 2;
    return Padding(
      padding: EdgeInsets.only(
        left: 20 + (onLeft ? strip : 0),
        right: onLeft ? 20 : strip + 8,
        // Centres the rest of the band on the first control.
        top: 2 * center - kDuoTitleBandHeight,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child:
            titleWidget ??
            Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: CupertinoColors.label.resolveFrom(context)),
            ),
      ),
    );
  }
}

/// Space between the groups of controls in the bar, as the system leaves it.
const double kDuoBarGroupSpacing = 12.0;

/// The accessory above the tab bar, with the gap between them once it has
/// anything to show.
class _AccessorySlot extends SingleChildRenderObjectWidget {
  const _AccessorySlot({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAccessorySlot();
}

class _RenderAccessorySlot extends RenderShiftedBox {
  _RenderAccessorySlot() : super(null);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    final gap = child.size.height > 0 ? kDuoBarGroupSpacing : 0.0;
    size = constraints.constrain(Size(child.size.width, child.size.height + gap));
    (child.parentData! as BoxParentData).offset = Offset.zero;
  }
}

/// Space the system leaves below the tab capsule.
const double kDuoBarBottomMargin = kDuoBarEdgeMargin;

/// The trailing vertical bar used on iPhone Duo, laid out the way the system
/// lays out its own: from the top, below the status cluster, primary
/// navigation (back, close), then the toolbar items, each group in one glass
/// capsule; at the bottom, the tab bar as a capsule of icons.
///
/// This is a Flutter-composed bar rather than a native one: iOS only lays out
/// container-managed bars vertically, never a hand-built UINavigationBar. The
/// capsules themselves are native Liquid Glass, or with [chrome] the app's
/// own controls, laid out in the same sizes.
class DuoVerticalBar extends StatelessWidget {
  const DuoVerticalBar({
    super.key,
    this.leading,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tabBar,
    this.reservedTabs = 0,
    this.accessory,
    this.reservedAccessory = 0,
    this.tint,
    this.regions = const <ReservedRegion>[],
    this.navigator,
    this.chrome,
    this.chromeData,
  });

  /// The app's own bars: its builders draw the groups of actions, the
  /// overflow control and the tabs, each in the size of the native capsule
  /// it stands for.
  final AdaptiveChrome? chrome;

  /// [AdaptiveAppBar.chromeData] of the page whose actions these are.
  final Object? chromeData;

  /// Primary navigation control (back, close), placed first.
  final Widget? leading;

  /// The page's toolbar actions, in order. Consecutive actions share a
  /// capsule; a spacer after an action ([AdaptiveAppBarAction.spacerAfter])
  /// starts a new one, which keeps the groups the top toolbar shows.
  final List<AdaptiveAppBarAction> actions;

  /// The tab bar to show at the bottom of the bar, if any.
  final AdaptiveBottomNavigationBar? tabBar;

  /// Number of tabs to keep room for without drawing them. The fixed chrome
  /// draws the tab bar in a layer of its own, so the layers holding a page's
  /// toolbar items need to know how much of the bar it takes.
  final int reservedTabs;

  /// The tab layout's accessory (a mini player), above the tab bar.
  final Widget? accessory;

  /// Height of an accessory to keep room for without drawing it, as with
  /// [reservedTabs].
  final double reservedAccessory;

  /// Tint for the toolbar items.
  final Color? tint;

  /// The page's navigator, for menus opened from a bar above the navigator.
  final NavigatorState? navigator;

  /// Reserved regions reported by the system, used to clear the camera.
  final List<ReservedRegion> regions;

  /// [actions] split into the groups that each get a capsule.
  static List<List<AdaptiveAppBarAction>> groupsOf(List<AdaptiveAppBarAction> actions) {
    final groups = <List<AdaptiveAppBarAction>>[];
    var current = <AdaptiveAppBarAction>[];
    for (final action in actions) {
      current.add(action);
      if (action.spacerAfter != ToolbarSpacerType.none) {
        groups.add(current);
        current = <AdaptiveAppBarAction>[];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final pose = DuoPoseScope.of(context);
    if (pose == null) return const SizedBox.shrink();
    final tabs = tabBar?.items ?? const <AdaptiveNavigationDestination>[];
    final insets = DuoLayout.barInsets(size: MediaQuery.sizeOf(context), pose: pose, regions: regions);
    final tabCount = tabs.isNotEmpty ? tabs.length : reservedTabs;
    final tabsHeight = tabCount == 0 ? 0.0 : IOS26GlassCapsule.tabsHeight(tabCount) + kDuoBarGroupSpacing;
    final accessoryHeight = reservedAccessory > 0 ? reservedAccessory + kDuoBarGroupSpacing : 0.0;

    return Padding(
      // Safe areas are asymmetric on iPhone Duo; read each edge on its own.
      padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxHeight - tabsHeight - accessoryHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ..._controls(room),
              const Spacer(),
              if (accessory != null) _AccessorySlot(child: accessory!),
              if (tabs.isNotEmpty && chrome != null)
                SizedBox(
                  width: IOS26GlassCapsule.width,
                  height: IOS26GlassCapsule.tabsHeight(tabs.length),
                  child: chrome!.tabBarBuilder(
                    context,
                    AdaptiveTabBarSpec(
                      placement: AdaptiveChromePlacement.vertical,
                      items: tabs,
                      selectedIndex: tabBar!.selectedIndex ?? 0,
                      onTap: (index) => tabBar!.onTap?.call(index),
                      data: tabBar!.chromeData,
                    ),
                  ),
                )
              else if (tabs.isNotEmpty)
                SizedBox(
                  width: IOS26GlassCapsule.width,
                  height: IOS26GlassCapsule.tabsHeight(tabs.length),
                  child: IOS26GlassCapsule(
                    items: [for (final tab in tabs) GlassCapsuleItem.fromDestination(tab)],
                    selectedIndex: tabBar!.selectedIndex ?? 0,
                    inset: IOS26GlassCapsule.tabsInset,
                    tint: tabBar!.selectedItemColor ?? CupertinoTheme.of(context).primaryColor,
                    onTap: (index) => tabBar!.onTap?.call(index),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The controls that fit into [room], top to bottom. Toolbar items give way
  /// before the tab bar does, which keeps the primary destinations reachable:
  /// the items that do not fit move, from the bottom up, into one overflow
  /// menu, as the system does. A group can be split, so its first items stay
  /// visible while the rest moves into the menu.
  List<Widget> _controls(double room) {
    final groups = groupsOf(actions);
    final total = actions.length;
    var used = leading == null ? 0.0 : IOS26GlassCapsule.width;
    final overflowCost = kDuoBarGroupSpacing + IOS26GlassCapsule.actionsHeight(1);

    final shown = <List<AdaptiveAppBarAction>>[];
    var count = 0;
    outer:
    for (final group in groups) {
      var capsule = <AdaptiveAppBarAction>[];
      for (final action in group) {
        // Growing a capsule costs one more row; starting one costs a whole
        // control plus the gap before it.
        final cost = capsule.isEmpty
            ? (used > 0 ? kDuoBarGroupSpacing : 0.0) + IOS26GlassCapsule.width
            : IOS26GlassCapsule.actionsHeight(capsule.length + 1) - IOS26GlassCapsule.actionsHeight(capsule.length);
        final isLast = count == total - 1;
        // Keep room for the overflow control unless this is the last item.
        if (used + cost + (isLast ? 0 : overflowCost) > room) {
          if (capsule.isNotEmpty) shown.add(capsule);
          break outer;
        }
        used += cost;
        capsule.add(action);
        count++;
      }
      shown.add(capsule);
      capsule = <AdaptiveAppBarAction>[];
    }

    final overflow = actions.skip(count).toList();

    final children = <Widget>[];
    void add(Widget child) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: kDuoBarGroupSpacing));
      }
      children.add(child);
    }

    if (leading != null) add(leading!);
    final chrome = this.chrome;
    for (final group in shown) {
      if (group.isEmpty) continue;
      add(
        chrome == null
            ? _ActionCapsule(actions: group, tint: tint)
            : _customActions(chrome, group, overflow: false),
      );
    }
    if (overflow.isNotEmpty) {
      add(
        chrome == null
            ? _OverflowCapsule(actions: overflow, navigator: navigator)
            : _customActions(chrome, overflow, overflow: true),
      );
    }
    return children;
  }

  /// The actions that did not fit, in a menu next to [anchor]; the one
  /// picked is performed from there.
  Future<void> _showOverflow(
    BuildContext anchor,
    List<AdaptiveAppBarAction> actions,
  ) async {
    final index = await AdaptivePopover.showMenu(
      anchor: anchor,
      navigator: navigator,
      items: [
        for (final action in actions)
          AdaptivePopupMenuItem<void>(
            label: action.effectiveLabel ?? '',
            icon: action.icon ?? action.iconWidget,
          ),
      ],
    );
    if (index == null || !anchor.mounted) return;
    actions[index].press(anchor, navigator: navigator);
  }

  /// One group of actions as the app draws it, in the size of the capsule
  /// it stands for; the overflow control in the size of one action.
  Widget _customActions(
    AdaptiveChrome chrome,
    List<AdaptiveAppBarAction> actions, {
    required bool overflow,
  }) {
    return SizedBox(
      width: IOS26GlassCapsule.width,
      height: IOS26GlassCapsule.actionsHeight(overflow ? 1 : actions.length),
      child: Builder(
        builder: (context) => chrome.actionsBuilder(
          context,
          AdaptiveActionsSpec(
            placement: AdaptiveChromePlacement.vertical,
            actions: actions,
            axis: Axis.vertical,
            overflow: overflow,
            showOverflow: overflow
                ? (anchor) => _showOverflow(anchor, actions)
                : null,
            tint: tint,
            data: chromeData,
            onPressed: (action, anchor) =>
                action.press(anchor, navigator: navigator),
          ),
        ),
      ),
    );
  }
}

/// The items that did not fit, behind the system's ellipsis menu.
class _OverflowCapsule extends StatelessWidget {
  const _OverflowCapsule({required this.actions, this.navigator});

  final List<AdaptiveAppBarAction> actions;
  final NavigatorState? navigator;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IOS26GlassCapsule.width,
      height: IOS26GlassCapsule.actionsHeight(1),
      child: IOS26GlassCapsule(
        items: [
          GlassCapsuleItem(
            symbol: 'ellipsis',
            label: 'More',
            fallback: const Icon(CupertinoIcons.ellipsis, size: 22),
            menu: [
              for (var i = 0; i < actions.length; i++)
                GlassCapsuleMenuEntry(
                  id: i,
                  // Without a name the entry shows its symbol alone; a
                  // symbol's identifier is not something to show a person.
                  title: actions[i].effectiveLabel ?? '',
                  symbol: actions[i].iosSymbol,
                ),
            ],
          ),
        ],
        onTap: (_) {},
        // Menus can't nest in the overflow menu, so they open as action sheets
        onMenuTap: (id) {
          if (id >= 0 && id < actions.length) {
            actions[id].press(context, navigator: navigator);
          }
        },
      ),
    );
  }
}

/// One group of toolbar items in one capsule.
class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({required this.actions, this.tint});

  /// Menu entry id offset per action, as a capsule has one onMenuTap
  static const int _menuIdStride = 1000;

  final List<AdaptiveAppBarAction> actions;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IOS26GlassCapsule.width,
      height: IOS26GlassCapsule.actionsHeight(actions.length),
      child: IOS26GlassCapsule(
        items: [for (var i = 0; i < actions.length; i++) GlassCapsuleItem.fromAction(actions[i], menuIdBase: i * _menuIdStride)],
        tint: tint,
        onTap: (index) => actions[index].onPressed(),
        onMenuTap: (id) {
          final index = id ~/ _menuIdStride;
          if (index >= 0 && index < actions.length) {
            actions[index].selectMenuItem(id % _menuIdStride);
          }
        },
      ),
    );
  }
}

/// The back button of the trailing bar: one round glass control.
class DuoBarBackButton extends StatelessWidget {
  const DuoBarBackButton({super.key, required this.onPressed, this.close = false});

  final VoidCallback onPressed;

  /// A cross instead of a chevron, for a page shown like a dialog.
  final bool close;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IOS26GlassCapsule.width,
      height: IOS26GlassCapsule.width,
      child: IOS26GlassCapsule(
        items: [
          close
              ? const GlassCapsuleItem(symbol: 'xmark', label: 'Close', fallback: Icon(CupertinoIcons.xmark, size: 22))
              : const GlassCapsuleItem(symbol: 'chevron.left', label: 'Back', fallback: Icon(CupertinoIcons.chevron_left, size: 22)),
        ],
        onTap: (_) => onPressed(),
      ),
    );
  }
}
