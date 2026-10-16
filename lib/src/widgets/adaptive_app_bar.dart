import 'package:flutter/widgets.dart';
import 'adaptive_app_bar_action.dart';

/// What the back button of the fixed iOS 26 toolbar looks like.
enum AdaptiveBackButtonStyle {
  /// A chevron, for a page pushed onto another one.
  back,

  /// A cross, for a page that covers the screen like a dialog.
  close,
}

/// Configuration for an adaptive app bar
///
/// This class holds the configuration for the app bar in [AdaptiveScaffold].
/// The actual rendering is platform-specific:
/// - iOS 26+ with useNativeToolbar: Native UIToolbar with Liquid Glass effects
/// - iOS 26+ without useNativeToolbar: CupertinoNavigationBar with custom back button
/// - iOS <26: CupertinoNavigationBar
/// - Android: Material AppBar
///
/// You can provide custom navigation bars using [cupertinoNavigationBar] or [appBar]:
/// - If [cupertinoNavigationBar] is provided and [useNativeToolbar] is false: Uses custom CupertinoNavigationBar on iOS
/// - If [appBar] is provided: Uses custom AppBar on Android
/// - Otherwise: Builds navigation bar from [title], [actions], and [leading]
class AdaptiveAppBar {
  /// Creates an adaptive app bar configuration
  const AdaptiveAppBar({
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.useNativeToolbar = true,
    this.tintColor,
    this.titleWidget,
    this.cupertinoNavigationBar,
    this.appBar,
    this.onBack,
    this.backButtonStyle = AdaptiveBackButtonStyle.back,
    this.automaticallyImplyLeading = true,
    this.showsBackdrop = true,
    this.hidesOnScroll = true,
    this.showsHairline = true,
    this.backdropColor,
    this.chromeData,
  });

  /// Title for the app bar
  final String? title;

  /// Optional subtitle displayed below the title
  final String? subtitle;

  /// Action buttons in the app bar
  /// - iOS 26+ with native toolbar: Rendered as native UIBarButtonItem in UIToolbar
  /// - iOS < 26: Rendered as buttons in CupertinoNavigationBar
  /// - Android: Rendered as IconButtons in Material AppBar
  final List<AdaptiveAppBarAction>? actions;

  /// Leading widget in the app bar (e.g., back button, menu button)
  /// If null and navigation is possible, an automatic back button will be shown
  final Widget? leading;

  /// Use native iOS 26 toolbar (iOS 26+ only)
  /// - When false (default): Uses CupertinoNavigationBar for better compatibility with routers
  /// - When true: Uses native iOS 26 UIToolbar with Liquid Glass effect
  ///
  /// Note: Setting this to true may cause compatibility issues with GoRouter and other
  /// router packages. Use with caution.
  ///
  /// If true, [cupertinoNavigationBar] will be ignored and native toolbar will be shown.
  final bool useNativeToolbar;

  /// Custom widget to display in the title area
  ///
  /// When set, this widget replaces the default title text rendering.
  /// On iOS 26+ with native toolbar, it is overlaid centered over the toolbar.
  /// On iOS < 26, it is used as the CupertinoNavigationBar middle.
  /// On Android, it is used as the AppBar title.
  final Widget? titleWidget;

  /// Tint color for toolbar action buttons (iOS 26+ native toolbar only)
  ///
  /// When set, this color is applied to the navigation bar's tintColor,
  /// which colors all bar button items (action buttons and back button).
  /// If null, the system default tint color is used.
  final Color? tintColor;

  /// Custom CupertinoNavigationBar for iOS
  ///
  /// When provided and [useNativeToolbar] is false, this custom navigation bar will be used
  /// instead of building one from [title], [actions], and [leading].
  ///
  /// Ignored when [useNativeToolbar] is true or on non-iOS platforms.
  final PreferredSizeWidget? cupertinoNavigationBar;

  /// Custom AppBar for Android
  ///
  /// When provided, this custom app bar will be used instead of building one
  /// from [title], [actions], and [leading].
  ///
  /// Ignored on iOS platforms.
  final PreferredSizeWidget? appBar;

  /// Called by the back button that the fixed iOS 26 toolbar (see
  /// `AdaptiveToolbarHost`) shows for this page, instead of popping the page's
  /// navigator. With [onBack] set the back button is shown even when the page
  /// cannot pop.
  final VoidCallback? onBack;

  /// Whether the back button of the fixed toolbar is a chevron or a cross.
  final AdaptiveBackButtonStyle backButtonStyle;

  /// Whether the fixed toolbar adds a back button by itself when the page can
  /// pop. Turn it off for pages that show one only through [onBack].
  final bool automaticallyImplyLeading;

  /// Whether the fixed iOS 26 toolbar draws its soft backdrop behind this
  /// page's bar. Turn it off for a page whose controls float over content
  /// that should stay clear, such as a map.
  final bool showsBackdrop;

  /// Whether the bar moves out of the way while the page scrolls on, where it
  /// does: the iPhone Duo's title band. A page that docks part of its own
  /// header under the bar keeps it, as moving it would leave a gap above
  /// what is docked.
  final bool hidesOnScroll;

  /// Whether the bar's background ends in a hairline once content scrolls
  /// under it. Off for a page that docks part of its own header right below
  /// the bar, which then reads as part of the bar and draws the line below
  /// itself.
  final bool showsHairline;

  /// The color of the page behind the fixed iOS 26 toolbar. Its backdrop
  /// takes it, so the bar blends into the page at rest and only fades out
  /// what scrolls underneath, like the system's scroll edge effect. Defaults
  /// to the system background, which suits a white page; a page with another
  /// background (the grey of grouped lists) would otherwise show a band.
  final Color? backdropColor;

  /// Anything the app's custom chrome ([AdaptiveToolbarHost.chrome]) wants
  /// to know about this page's bar, such as a dark or a light look, handed to
  /// its builders as their spec's `data`.
  final Object? chromeData;

  /// Creates a copy of this app bar with the given fields replaced
  AdaptiveAppBar copyWith({
    String? title,
    String? subtitle,
    List<AdaptiveAppBarAction>? actions,
    Widget? leading,
    bool? useNativeToolbar,
    Color? tintColor,
    Widget? titleWidget,
    PreferredSizeWidget? cupertinoNavigationBar,
    PreferredSizeWidget? appBar,
    VoidCallback? onBack,
    AdaptiveBackButtonStyle? backButtonStyle,
    bool? automaticallyImplyLeading,
    bool? showsBackdrop,
    bool? hidesOnScroll,
    bool? showsHairline,
    Color? backdropColor,
    Object? chromeData,
  }) {
    return AdaptiveAppBar(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      actions: actions ?? this.actions,
      leading: leading ?? this.leading,
      useNativeToolbar: useNativeToolbar ?? this.useNativeToolbar,
      tintColor: tintColor ?? this.tintColor,
      titleWidget: titleWidget ?? this.titleWidget,
      cupertinoNavigationBar:
          cupertinoNavigationBar ?? this.cupertinoNavigationBar,
      appBar: appBar ?? this.appBar,
      onBack: onBack ?? this.onBack,
      backButtonStyle: backButtonStyle ?? this.backButtonStyle,
      automaticallyImplyLeading:
          automaticallyImplyLeading ?? this.automaticallyImplyLeading,
      showsBackdrop: showsBackdrop ?? this.showsBackdrop,
      hidesOnScroll: hidesOnScroll ?? this.hidesOnScroll,
      showsHairline: showsHairline ?? this.showsHairline,
      backdropColor: backdropColor ?? this.backdropColor,
      chromeData: chromeData ?? this.chromeData,
    );
  }
}
