import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../style/sf_symbol.dart';
import '../widgets/adaptive_app_bar.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/ios26/ios26_bar_backdrop.dart';
import '../widgets/ios26/ios26_native_toolbar.dart';
import 'duo_vertical_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// Height of the toolbar's content area, excluding the status bar.
const double kHostedToolbarHeight = 44.0;

/// What one page contributes to the top toolbar.
@immutable
class TopToolbarContent {
  const TopToolbarContent({
    this.title,
    this.titleOverlay,
    this.customLeading,
    this.impliesBack = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
    this.navigator,
    this.onBack,
    this.backStyle = AdaptiveBackButtonStyle.back,
  });

  /// No page owns the chrome, the page has no toolbar, or it draws a
  /// non-native bar of its own: nothing to show.
  ///
  /// With [titleOnly] the controls are left out, because the iPhone Duo
  /// vertical bar shows them instead.
  factory TopToolbarContent.of(ToolbarEntry? entry, {bool titleOnly = false}) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const TopToolbarContent();
    }
    return TopToolbarContent(
      title: appBar.title,
      titleOverlay: entry.titleOverlay,
      customLeading: titleOnly ? null : appBar.leading,
      impliesBack: !titleOnly && entry.impliesBackButton,
      actions: titleOnly
          ? const <AdaptiveAppBarAction>[]
          : appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
      navigator: entry.navigator,
      onBack: appBar.onBack,
      backStyle: appBar.backButtonStyle,
    );
  }

  final String? title;

  /// A Flutter-drawn title (custom widget, or title with subtitle). The
  /// native title is left empty while one is shown.
  final Widget? titleOverlay;
  final Widget? customLeading;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;
  final NavigatorState? navigator;

  /// Performed by the back button instead of popping [navigator].
  final VoidCallback? onBack;
  final AdaptiveBackButtonStyle backStyle;

  bool get isEmpty =>
      title == null &&
      titleOverlay == null &&
      customLeading == null &&
      !impliesBack &&
      actions.isEmpty;
}

/// The one top toolbar of the app. It stays where it is while pages come and
/// go underneath it; only its items change.
///
/// It works exactly like the iPhone Duo vertical bar: every page involved in
/// a transition gets a layer of its own (here a native Liquid Glass
/// navigation bar), the layers are blended as [ToolbarBlend] dictates, so the
/// outgoing items fade out before the incoming ones fade in, in step with the
/// route transition and with a back swipe. A back button that both pages show
/// is one control in a layer of its own and stays put.
class HostedTopToolbar extends StatelessWidget {
  const HostedTopToolbar({
    super.key,
    required this.blend,
    this.titleOnly = false,
  });

  final ToolbarBlend blend;

  /// True on iPhone Duo, where the controls live in the vertical bar.
  final bool titleOnly;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: blend, builder: _build);
  }

  Widget _build(BuildContext context, Widget? _) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = TopToolbarContent.of(upperEntry, titleOnly: titleOnly);
    final lower = TopToolbarContent.of(lowerEntry, titleOnly: titleOnly);
    final upperOwns = blend.upperOwns;
    final upperOpacity = blend.upperOpacity;
    final lowerOpacity = blend.lowerOpacity;
    final ownerEntry = upperOwns ? upperEntry : lowerEntry;

    final upperBack = upper.impliesBack && upper.customLeading == null;
    final lowerBack = lower.impliesBack && lower.customLeading == null;
    final Animation<double>? backOpacity = switch ((upperBack, lowerBack)) {
      (true, true) => kAlwaysCompleteAnimation,
      (true, false) => upperOpacity,
      (false, true) => lowerOpacity,
      (false, false) => null,
    };

    final height = titleOnly
        ? kDuoTitleBandHeight
        : kHostedToolbarHeight + topInset;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        child: IgnorePointer(
          ignoring: blend.ownerIsCovered,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Like the background of a navigation controller's bar, the
              // backdrop belongs to the chrome, not to a page, and follows the
              // page that owns it. It is never faded with the chrome: a fade
              // would break the system's effect.
              Positioned(
                key: const ValueKey<String>('adaptive_toolbar_backdrop'),
                top: 0,
                left: 0,
                right: 0,
                height: height + kBarBackdropFade,
                child: BarScrollEdge(
                  scrolledUnder: ownerEntry?.scrolledUnder,
                  shown: !upper.isEmpty || !lower.isEmpty,
                ),
              ),
              FadeTransition(
                opacity: blend.chromeOpacity,
                // Every layer is keyed, so a page's native bar survives the
                // start and the end of a blend instead of being torn down and
                // rebuilt.
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    if (lowerEntry != null && !lower.isEmpty)
                      _layer(
                        key: ValueKey<Object>(lowerEntry.id),
                        content: lower,
                        opacity: lowerOpacity,
                        interactive: !upperOwns,
                      ),
                    if (upperEntry != null && !upper.isEmpty)
                      _layer(
                        key: ValueKey<Object>(upperEntry.id),
                        content: upper,
                        opacity: upperOpacity,
                        interactive: upperOwns,
                      ),
                    if (backOpacity != null)
                      Positioned(
                        key: const ValueKey<String>('adaptive_toolbar_back'),
                        left: 16 + (_isWindowed(context) ? 62 : 0),
                        bottom: 3,
                        child: FadeTransition(
                          key: const ValueKey<String>(
                            'adaptive_toolbar_back_fade',
                          ),
                          opacity: backOpacity,
                          child: _BackButton(
                            content: upperOwns ? upper : lower,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One page's bar. The back button is not part of it: the shared one is
  /// drawn on top of all page layers.
  Widget _layer({
    required Key key,
    required TopToolbarContent content,
    required Animation<double> opacity,
    required bool interactive,
  }) {
    return FadeTransition(
      key: key,
      opacity: opacity,
      child: IgnorePointer(
        ignoring: !interactive,
        child: titleOnly
            // On iPhone Duo the title sits at the leading edge and the
            // controls are in the trailing bar, so there is no bar to draw.
            ? DuoToolbarTitle(
                title: content.title,
                titleWidget: content.titleOverlay,
              )
            : defaultTargetPlatform == TargetPlatform.iOS
            ? IOS26NativeToolbar(
                title: content.title,
                titleWidget: content.titleOverlay,
                leading: content.customLeading,
                actions: content.actions,
                tintColor: content.tint,
                showsGradient: false,
                onActionTap: (index) {
                  if (index >= 0 && index < content.actions.length) {
                    content.actions[index].onPressed();
                  }
                },
              )
            : _FallbackBar(content: content),
      ),
    );
  }

  /// Whether the app runs in a window smaller than the display (iPadOS),
  /// where the system's window controls take the bar's leading corner.
  static bool _isWindowed(BuildContext context) {
    final display = View.of(context).display.size;
    final viewport =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return (display.longestSide - viewport.longestSide).abs() > 1 ||
        (display.shortestSide - viewport.shortestSide).abs() > 1;
  }
}

/// How far below a bar its backdrop runs on, fading out.
const double kBarBackdropFade = 16;

/// The native backdrop of a bar: clear while the page rests at its top, the
/// system's scroll edge effect while its content is scrolled under the bar.
@visibleForTesting
class BarScrollEdge extends StatelessWidget {
  const BarScrollEdge({
    super.key,
    required this.scrolledUnder,
    this.shown = true,
  });

  /// Whether the page's content is under the bar; null when the page does
  /// not tell, which leaves the bar clear.
  final ValueListenable<bool>? scrolledUnder;

  /// False while there is no bar to show.
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final scrolledUnder = this.scrolledUnder;
    if (scrolledUnder == null) {
      return const IOS26BarBackdrop(visible: false, fade: kBarBackdropFade);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: scrolledUnder,
      builder: (context, scrolled, _) =>
          IOS26BarBackdrop(visible: shown && scrolled, fade: kBarBackdropFade),
    );
  }
}

/// Back for the page that owns the chrome: the page's own handler, or else a
/// pop of the page's own navigator, so nested navigators (tabs, shell routes)
/// pop the right stack.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.content});

  final TopToolbarContent content;

  @override
  Widget build(BuildContext context) {
    final onBack = content.onBack;
    return SizedBox(
      height: 38,
      width: 38,
      child: AdaptiveButton.sfSymbol(
        onPressed: onBack ?? () => content.navigator?.maybePop(),
        sfSymbol: SFSymbol(
          content.backStyle == AdaptiveBackButtonStyle.close
              ? 'xmark'
              : 'chevron.left',
          size: 20,
        ),
      ),
    );
  }
}

/// Stand-in for the native bar where there is no UIKit (widget tests).
class _FallbackBar extends StatelessWidget {
  const _FallbackBar({required this.content});

  final TopToolbarContent content;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kHostedToolbarHeight,
        child: Row(
          children: [
            if (content.customLeading != null) content.customLeading!,
            Expanded(
              child: Center(
                child:
                    content.titleOverlay ??
                    (content.title != null ? Text(content.title!) : null),
              ),
            ),
            for (final action in content.actions)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: action.onPressed,
                child: action.icon != null
                    ? Icon(action.icon)
                    : Text(action.title ?? ''),
              ),
          ],
        ),
      ),
    );
  }
}
