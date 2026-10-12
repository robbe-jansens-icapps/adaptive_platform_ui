import 'package:flutter/widgets.dart';

import '../widgets/adaptive_app_bar.dart';
import 'toolbar_registry.dart';

/// Shows [appBar] in the app's one fixed toolbar while this page is in front,
/// like the app bar of an `AdaptiveScaffold` page, for a page that lays itself
/// out: a full-screen map with controls of its own, say. On iPhone Duo its
/// actions go to the vertical bar.
///
/// It draws nothing itself. Without an `AdaptiveToolbarHost` above it, it
/// only shows [child].
class AdaptiveFixedToolbar extends StatefulWidget {
  const AdaptiveFixedToolbar({
    super.key,
    required this.appBar,
    required this.child,
  });

  /// Shown when [AdaptiveAppBar.useNativeToolbar] is set.
  final AdaptiveAppBar appBar;

  final Widget child;

  @override
  State<AdaptiveFixedToolbar> createState() => _AdaptiveFixedToolbarState();
}

class _AdaptiveFixedToolbarState extends State<AdaptiveFixedToolbar> {
  ToolbarRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AdaptiveFixedToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appBar != widget.appBar) _sync();
  }

  @override
  void dispose() {
    _registry?.remove(this);
    super.dispose();
  }

  /// Publishes the app bar the way a scaffold page does. Reading the route,
  /// the ticker mode and the visibility here runs this again whenever the page
  /// stops or starts being the one in front.
  void _sync() {
    final registry = ToolbarRegistry.maybeOf(context);
    if (registry == null) return;
    _registry = registry;
    final navigator = Navigator.maybeOf(context);
    // Routes of the navigators around this page's own one (tabs, shell
    // routes), nearest first.
    final enclosingRoutes = <ModalRoute<Object?>>[];
    var outer = navigator?.context;
    while (outer != null) {
      final route = ModalRoute.of(outer);
      if (route == null) break;
      enclosingRoutes.add(route);
      outer = outer.findAncestorStateOfType<NavigatorState>()?.context;
    }
    registry.upsert(
      ToolbarEntry(
        id: this,
        appBar: widget.appBar,
        route: ModalRoute.of(context),
        navigator: navigator,
        enclosingRoutes: enclosingRoutes,
        // `TickerMode.valuesOf` replaces this, but only exists in Flutter
        // releases after 3.35; `of` works on every supported version.
        // ignore: deprecated_member_use
        visible: TickerMode.of(context) && Visibility.of(context),
        shownInPlace: Visibility.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
