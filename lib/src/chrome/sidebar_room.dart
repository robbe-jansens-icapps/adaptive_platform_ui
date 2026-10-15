import 'package:flutter/widgets.dart';

/// The room the sidebar of custom chrome takes at the leading edge of the
/// pages beside it, for the first page under the tab layout to take over.
///
/// The pages run under the floating sidebar, so their own background (a
/// header, the colour of a list) goes on behind it with no edge between the
/// two, as a sidebar floats over the content on iPadOS 26. The first page
/// keeps its content clear of the room, or lays its content out under it
/// and keeps clear through the media query's padding
/// (`AdaptiveScaffold.extendBodyBehindVerticalBar`). A split view hands the
/// room to its list. The pages inside a page that took it over get none.
class SidebarRoom extends InheritedWidget {
  const SidebarRoom({super.key, required this.width, required super.child});

  /// How wide the room is; 0 once a page has taken it over.
  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarRoom>()?.width ?? 0;

  @override
  bool updateShouldNotify(SidebarRoom oldWidget) => width != oldWidget.width;
}
