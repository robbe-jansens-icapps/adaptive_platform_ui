import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../platform/platform_info.dart';
import '../style/sf_symbol.dart';
import '../style/glass_button_glyph.dart';
import '../widgets/adaptive_app_bar.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/ios26/ios26_native_toolbar.dart';
import 'duo_top_strip.dart';
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
    this.backdrop = true,
    this.backdropColor,
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
      backdrop: appBar.showsBackdrop,
      backdropColor: appBar.backdropColor,
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

  /// Whether the page wants the bar's backdrop behind its controls.
  final bool backdrop;

  /// The page's color, which the backdrop takes; null for the system
  /// background.
  final Color? backdropColor;

  /// Whether the native bar has anything to show: a title it draws itself
  /// or bar buttons.
  bool get hasNativeItems =>
      (title != null && titleOverlay == null) || actions.isNotEmpty;

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
    final topInset = _barTop(context);
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = TopToolbarContent.of(upperEntry, titleOnly: titleOnly);
    final lower = TopToolbarContent.of(lowerEntry, titleOnly: titleOnly);
    final upperOwns = blend.upperOwns;
    // A page shown like a dialog slides up over the screen and back down. Its
    // part of the bar travels with it, as a modal's own navigation bar does,
    // instead of fading in place.
    final upperSlide = _dialogSlide(upperEntry);
    final upperOpacity = upperSlide != null
        ? kAlwaysCompleteAnimation
        : blend.upperOpacity;
    final lowerOpacity = blend.lowerOpacity;

    final upperBack = upper.impliesBack && upper.customLeading == null;
    final lowerBack = lower.impliesBack && lower.customLeading == null;
    // A back button that both pages show the same way is one control that
    // stays put. Otherwise each page's own comes and goes with the page and
    // keeps its look: a cross does not turn into a chevron on its way out.
    final backs =
        <(TopToolbarContent, Animation<double>, bool, Animation<double>?)>[
          if (upperBack && lowerBack && upper.backStyle == lower.backStyle)
            (upperOwns ? upper : lower, kAlwaysCompleteAnimation, true, null)
          else ...[
            if (lowerBack) (lower, lowerOpacity, !upperOwns, null),
            if (upperBack) (upper, upperOpacity, upperOwns, upperSlide),
          ],
        ];

    // The bar's backdrop belongs to the chrome, not to a page: it only fades
    // when the toolbar as a whole comes or goes, or between a page that wants
    // it and one that does not. Only one page's, it travels with that page.
    final upperBackdrop = !upper.isEmpty && upper.backdrop;
    final lowerBackdrop = !lower.isEmpty && lower.backdrop;
    final Animation<double> backdropOpacity = switch ((
      upperBackdrop,
      lowerBackdrop,
    )) {
      (true, true) => kAlwaysCompleteAnimation,
      (true, false) =>
        blend.isBlending && lowerEntry != null
            ? upperOpacity
            : kAlwaysCompleteAnimation,
      (false, true) => lowerOpacity,
      (false, false) => kAlwaysDismissedAnimation,
    };
    final backdropSlide = upperBackdrop && !lowerBackdrop ? upperSlide : null;
    // In the color of the page it sits on: blended from one page's to the
    // next as the pages are.
    final systemBackground = CupertinoColors.systemBackground.resolveFrom(
      context,
    );
    final upperColor = upper.backdropColor ?? systemBackground;
    final lowerColor = lower.backdropColor ?? systemBackground;
    final driver = blend.driver;
    // Pages of one colour have nothing to blend, which would redraw the
    // backdrop on every frame of the transition.
    final backdrop =
        upperBackdrop &&
            lowerBackdrop &&
            driver != null &&
            upperColor != lowerColor
        ? AnimatedBuilder(
            animation: driver,
            builder: (context, _) =>
                _backdrop(Color.lerp(lowerColor, upperColor, driver.value)!),
          )
        : _backdrop(upperBackdrop ? upperColor : lowerColor);

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: titleOnly
            ? kDuoTitleBandHeight
            : kHostedToolbarHeight + topInset,
        child: IgnorePointer(
          ignoring: blend.ownerIsCovered,
          child: FadeTransition(
            opacity: blend.chromeOpacity,
            // Every layer is keyed, so a page's native bar survives the start
            // and the end of a blend instead of being torn down and rebuilt.
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                FadeTransition(
                  key: const ValueKey<String>('adaptive_toolbar_backdrop'),
                  opacity: backdropOpacity,
                  // Gone while a dialog or a sheet covers the page: over the
                  // page's dimmed barrier it would show as a lighter band.
                  child: FadeTransition(
                    opacity: ReverseAnimation(blend.cover),
                    child: _DialogSlide(driver: backdropSlide, child: backdrop),
                  ),
                ),
                if (lowerEntry != null && !lower.isEmpty)
                  _layer(
                    context,
                    key: ValueKey<Object>(lowerEntry.id),
                    content: lower,
                    opacity: lowerOpacity,
                    interactive: !upperOwns,
                  ),
                if (upperEntry != null && !upper.isEmpty)
                  _layer(
                    context,
                    key: ValueKey<Object>(upperEntry.id),
                    content: upper,
                    opacity: upperOpacity,
                    interactive: upperOwns,
                    slide: upperSlide,
                  ),
                // One back button of each look, always in place: shown when a
                // page has one, kept alive but off stage otherwise, so its
                // native view is not created anew on every transition.
                if (!titleOnly)
                  for (final style in AdaptiveBackButtonStyle.values)
                    _backSlot(
                      context,
                      style: style,
                      back: backs
                          .where((b) => b.$1.backStyle == style)
                          .firstOrNull,
                      topInset: topInset,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backSlot(
    BuildContext context, {
    required AdaptiveBackButtonStyle style,
    required (TopToolbarContent, Animation<double>, bool, Animation<double>?)?
    back,
    required double topInset,
  }) {
    return Positioned(
      // Keyed by its look, so a back button carries on as the same control
      // from one page to the next.
      key: ValueKey<Object>(('adaptive_toolbar_back', style)),
      left:
          16 +
          (_hasWindowControls(context) ? 62 : 0) +
          (DuoTopStripScope.of(context)?.clusterLeft ?? 0),
      top: topInset,
      bottom: 0,
      child: Offstage(
        offstage: back == null,
        child: FadeTransition(
          key: const ValueKey<String>('adaptive_toolbar_back_fade'),
          opacity: back?.$2 ?? kAlwaysDismissedAnimation,
          // See _layer: in the semantics tree at every opacity, left out
          // while it fades with the page leaving.
          alwaysIncludeSemantics: true,
          child: ExcludeSemantics(
            excluding: !(back?.$3 ?? false),
            child: _DialogSlide(
              driver: back?.$4,
              child: IgnorePointer(
                ignoring: !(back?.$3 ?? false),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: _BackButton(
                    content: back?.$1 ?? TopToolbarContent(backStyle: style),
                    // While pages are pushed, popped or swiped back, also one
                    // that both pages show and that stays put, so all of them
                    // look the same; and one fading or sliding otherwise.
                    moving:
                        back != null &&
                        blend.isBlending &&
                        (blend.routeTransition.value ||
                            !identical(back.$2, kAlwaysCompleteAnimation) ||
                            back.$4 != null),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backdrop(Color color) =>
      titleOnly ? DuoTitleBackdrop(color: color) : _Backdrop(color: color);

  /// While [entry] is a page shown like a dialog that comes up or goes down:
  /// its route's animation, which the blend follows. Null otherwise.
  Animation<double>? _dialogSlide(ToolbarEntry? entry) {
    final driver = blend.driver;
    final route = entry?.route;
    if (driver == null || route is! PageRoute || !route.fullscreenDialog) {
      return null;
    }
    return identical(driver, route.animation) ? driver : null;
  }

  /// One page's bar. The back button is not part of it: the shared one is
  /// drawn on top of all page layers.
  Widget _layer(
    BuildContext context, {
    required Key key,
    required TopToolbarContent content,
    required Animation<double> opacity,
    required bool interactive,
    Animation<double>? slide,
  }) {
    // alwaysIncludeSemantics: a layer that fades to zero during a back swipe
    // must not drop its semantics and restore them when the swipe comes back;
    // doing that mid gesture trips SemanticsNode._replaceChildren with the
    // native bar inside. The layer that is not the page in front is excluded
    // explicitly instead, so a screen reader never lands on invisible items.
    return FadeTransition(
      key: key,
      opacity: opacity,
      alwaysIncludeSemantics: true,
      child: ExcludeSemantics(
        excluding: !interactive,
        child: _DialogSlide(
          driver: slide,
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
                    // The shared back button is drawn over the bar: the title
                    // keeps clear of it all the same.
                    reservesLeading:
                        content.impliesBack || content.customLeading != null,
                    leadingInset: _hasWindowControls(context) ? 62 : 0,
                    actions: content.actions,
                    tintColor: content.tint,
                    showsGradient: false,
                    // A native bar only for what only it can show: its own
                    // title or bar buttons. Most pages have a Flutter title and
                    // no buttons, and a platform view per page and transition
                    // costs frames.
                    showNativeView: content.hasNativeItems,
                    onActionTap: (index) {
                      if (index >= 0 && index < content.actions.length) {
                        content.actions[index].onPressed();
                      }
                    },
                  )
                : _FallbackBar(content: content),
          ),
        ),
      ),
    );
  }

  /// Whether the system's window controls take the bar's leading corner: in
  /// an iPad window smaller than the display. An iPhone Duo window in split
  /// view has none.
  static bool _hasWindowControls(BuildContext context) =>
      PlatformInfo.isIPad && _isWindowed(context);

  /// Where the bar starts: below the status bar, or in the iPhone Duo's top
  /// strip, beside its status cluster.
  static double _barTop(BuildContext context) =>
      DuoTopStripScope.of(context) != null
      ? DuoTopStrip.barTop
      : MediaQuery.viewPaddingOf(context).top;

  /// Whether the app runs in a window smaller than the display.
  static bool _isWindowed(BuildContext context) {
    final display = View.of(context).display.size;
    final viewport =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return (display.longestSide - viewport.longestSide).abs() > 1 ||
        (display.shortestSide - viewport.shortestSide).abs() > 1;
  }
}

/// Moves its part of the bar with a page shown like a dialog, which slides up
/// from below the screen and back down ([driver] is that page's route
/// animation, eased as `CupertinoFullscreenDialogTransition` eases it). It
/// stays in place without a [driver], and is built the same either way, so a
/// native bar inside lives on when a transition starts or ends.
class _DialogSlide extends StatelessWidget {
  const _DialogSlide({required this.driver, required this.child});

  final Animation<double>? driver;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final driver = this.driver;
    final height = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: driver ?? kAlwaysCompleteAnimation,
      builder: (context, child) {
        var below = 0.0;
        if (driver != null) {
          final curve = driver.status == AnimationStatus.reverse
              ? Curves.linearToEaseOut.flipped
              : Curves.linearToEaseOut;
          below = 1 - curve.transform(driver.value);
        }
        return Transform.translate(
          offset: Offset(0, below * height),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// The soft gradient that keeps the bar readable over scrolling content, in
/// the page's [color]: invisible at rest, it fades out what scrolls under the
/// bar.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = color.withValues(alpha: 1);
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            // Runs on below the bar for a smooth fade into the content.
            height:
                HostedTopToolbar._barTop(context) + kHostedToolbarHeight + 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
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
        ),
      ),
    );
  }
}

/// Back for the page that owns the chrome: the page's own handler, or else a
/// pop of the page's own navigator, so nested navigators (tabs, shell routes)
/// pop the right stack.
///
/// A native glass button. While pages move, a Flutter one takes its place,
/// with the glyph as iOS shows it in the native button ([GlassButtonGlyph]):
/// a native view on screen makes every frame of a transition dearer. The
/// native button waits off stage meanwhile, and the stand-in fades out over it
/// once it is back.
class _BackButton extends StatefulWidget {
  const _BackButton({required this.content, required this.moving});

  final TopToolbarContent content;

  /// Whether pages move right now, or the button fades or slides with one.
  final bool moving;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton>
    with SingleTickerProviderStateMixin {
  // As the system draws them.
  static const _back = SFSymbol(
    'chevron.left',
    size: 19,
    weight: FontWeight.w600,
  );
  static const _close = SFSymbol('xmark', size: 17, weight: FontWeight.w600);

  SFSymbol get _symbol =>
      widget.content.backStyle == AdaptiveBackButtonStyle.close
      ? _close
      : _back;

  /// The stand-in's opacity: 1 while it stands in, fading out over the native
  /// button once that is back.
  late final AnimationController _standIn;

  /// Whether the stand-in is in the native button's place right now.
  bool _standingIn = false;

  /// The appearance the glyph is loaded for: the native button's, which
  /// follows the platform brightness.
  bool? _dark;

  GlassButtonGlyph? get _glyph => _dark == null
      ? null
      : GlassButtonGlyph.of(_symbol, side: kHostedToolbarHeight, dark: _dark!);

  @override
  void initState() {
    super.initState();
    _standIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addStatusListener(_onStandInStatus);
  }

  // Gone once faded out.
  void _onStandInStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ready long before the first page with a back button comes in: the two
    // buttons are in place from the start. Again in the other appearance.
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (dark == _dark || defaultTargetPlatform != TargetPlatform.iOS) return;
    _dark = dark;
    GlassButtonGlyph.load(
      _symbol,
      context,
      side: kHostedToolbarHeight,
      dark: dark,
    ).then((glyph) {
      if (mounted && glyph != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_BackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moving && !_standingIn) {
      // Only with the glyph in hand: an empty button would be worse than the
      // native one.
      if (_glyph == null) return;
      _standingIn = true;
      _standIn.value = 1;
    } else if (!widget.moving && _standingIn) {
      _standingIn = false;
      // The native button is back on screen with this frame; the stand-in
      // makes way once it is.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _standingIn) return;
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
          _standIn.value = 0;
        } else {
          _standIn.reverse(from: 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _standIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final onBack = content.onBack ?? () => content.navigator?.maybePop();
    final glyph = _glyph;
    // A circle as tall as the bar, as the system's back button.
    return SizedBox.square(
      dimension: kHostedToolbarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            // Never an empty button: should the appearance change while pages
            // move, the native one shows until the glyph for it is in.
            offstage: _standingIn && glyph != null,
            child: AdaptiveButton.sfSymbol(
              size: AdaptiveButtonSize.large,
              useSmoothRectangleBorder: false,
              onPressed: onBack,
              sfSymbol: _symbol,
            ),
          ),
          if (glyph != null && (_standingIn || _standIn.value > 0))
            FadeTransition(
              key: const ValueKey<String>('adaptive_toolbar_back_stand_in'),
              opacity: _standIn,
              child: _BackStandIn(glyph: glyph, onPressed: onBack),
            ),
        ],
      ),
    );
  }
}

/// The back button without glass, for while pages move: a light, translucent
/// circle, as the glass surfaces stand in for theirs, with the button's glyph.
class _BackStandIn extends StatelessWidget {
  const _BackStandIn({required this.glyph, required this.onPressed});

  final GlassButtonGlyph glyph;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: dark ? const Color(0xE6303034) : const Color(0xE6FAFAFC),
          shape: CircleBorder(
            side: BorderSide(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
              width: 0.5,
            ),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 2),
            ),
          ],
        ),
        // Where, how large and in what colour the native button shows it.
        child: Center(
          child: Transform.translate(
            offset: glyph.offset,
            child: Image(
              image: glyph.image,
              color: glyph.color,
              colorBlendMode: BlendMode.srcIn,
              gaplessPlayback: true,
            ),
          ),
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
    final strip = DuoTopStripScope.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kHostedToolbarHeight,
        child: Padding(
          padding: EdgeInsets.only(
            left: strip?.clusterLeft ?? 0,
            right: strip?.clusterRight ?? 0,
          ),
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
                Builder(
                  builder: (context) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        action.press(context, navigator: content.navigator),
                    child: action.icon != null
                        ? Icon(action.icon)
                        : Text(action.title ?? ''),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
