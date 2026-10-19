# Changelog

## [Unreleased]
* **FIX**: iPhone Duo: a detail pane built inside the tab scaffold (a two-pane layout, nothing pushed) kept the tab bar hidden once it became the chrome owner, because the owner lookup only recognised shell routes around a nested navigator. A pane on the tab scaffold's own route now keeps the tab bar; pages pushed above the tabs still hide it (reported and diagnosed by @monster-echo, #173)
* **NEW**: `AdaptiveAppBarAction.badgeCount` puts a count badge on a toolbar action: the native glass capsule draws it in the iPhone Duo bar ("99+" above 99), and iOS 18 and Android draw an `AdaptiveBadge` on the icon. The horizontal iOS 26 toolbar ignores it, as `UIBarButtonItem` has no badge. Null or 0 shows nothing (@keithcheehui, #174)

## [Blue Bike fork]
Changes on top of the vendored 1.0.2 release (forked from 1.0.1).

* **FIX**: A sheet that settles as its page builds, its detents or its place changing with the page (a side panel floating again as a foldable folds shut, while what it shows changes), tells the page where it settles and which detent it heads for (`onSettled`, `onDetentChanged`, its controller) after the frame, rather than while the page builds: a page that builds again for it no longer threw, leaving Flutter's error box over the sheet
* **NEW**: `AdaptiveSheet.accessory`: an accessory a floating sheet holds at its bottom itself, where no tab bar along the bottom holds the tab accessory on it (`AdaptiveTabAccessoryLayout.onSheet`), as in the iPhone Duo's vertical bar pose, whose bar shows the tab accessory as a key: a ride's row on the map's sheet beside it. It sits round with the sheet's corners (`kAdaptiveSheetCornerRadius` less half its height in from them), at the collapsed detent the sheet's glass around it alone. With `opensFromAccessory` the content comes up into its place as it makes way, and a drag on it moves the sheet; other content ends above it, and with `liftsAccessory` it stands apart on a Liquid Glass capsule of its own. `AdaptiveAccessoryScope` tells it it is on a page's sheet along the bottom, with the sheet's glass or its capsule as its surface, and opens and closes the sheet. The sheet reports its band as part of what it covers. Floating sheets with the native chrome only; one with nothing to show takes no room
* **NEW**: `AdaptiveAccessoryScope.surfaceOf` (`AdaptiveAccessorySurface`) tells a tab accessory what it sits on, how far that reaches beyond it on each side, and its shape: the tray's glass, a page's sheet's glass in its place with the sheet's corners (`kAdaptiveSheetCornerRadius`), a capsule of its own (floating, beside the tabs, or lifted apart on a page's sheet), or the band of the Material navigation bar, which reaches the window's sides. Content of the accessory that moves beyond its bounds, a page of rides swiped away, can so go on to that edge and be cut off there in its shape (`AdaptiveAccessorySurface.outline`), rather than at the accessory's bounds inside it. Null with custom chrome
* **FIX**: The content of a page's sheet that holds the tab accessory (`AdaptiveSheet.opensFromAccessory`, `liftsAccessory`), where it does not open from it, ends at the top of the accessory's band wherever the sheet is: coming up from behind the accessory, a station's details above a folded ride, it no longer shows around and through the accessory, which has no glass of its own there yet, for the first frames
* **FIX**: An accessory on a page's sheet no longer fades out and in again as other content comes up above it from its place (a station opened above a folded ride), with the native tab bar and the Material one: while the sheet stops opening from it, the accessory only comes back into sight
* **NEW**: The Material tab layout of `AdaptiveScaffold` (Android) shows a tab accessory too (`AdaptiveBottomNavigationBar.accessory`, `MaterialTabAccessory`): on the `NavigationBar`'s own surface, in its colour, in a band just above its destinations, so the two are one bar that rises over the pages with rounded top corners, as a Material sheet at its smallest. The pages run on under the band and keep clear of it (their bottom padding, and `AdaptiveBottomBarInset.accessoryOf`), so a page's sheet comes up from behind the bar with the accessory in sight above it, as with the native tab bar. The band takes no room while the accessory builds to nothing, and makes way for the keyboard. `AdaptiveAccessoryScope` tells the accessory the layout (`tray` or `onSheet`) and its room
* **NEW**: `AdaptiveSheet.opensFromAccessory` with the Material navigation bar: on the tab whose layout is `AdaptiveTabAccessoryLayout.onSheet`, the sheet collapsed lies behind the band, and pulled up, dragged up on the accessory, or opened through `AdaptiveAccessoryScope.expansionOf`, it comes up into the accessory's place, the accessory and the band's surface making way as its content comes up, and ends where the destinations begin
* **NEW**: `AdaptiveSheet.liftsAccessory`: while the sheet's content lies above the tab accessory on it (`AdaptiveTabAccessoryLayout.onSheet`), such as a station's details above a ride's row, the accessory stands apart from it on a Liquid Glass capsule of its own, as one floats above the tabs elsewhere, rather than running together with the content on the sheet's glass. The capsule comes in as the content comes up above the accessory and goes as it goes down, and stays away where the content comes up into the accessory's place (`opensFromAccessory`). Under a dialog its Flutter stand-in takes its place, which the dialog's barrier dims with the accessory. Off by default
* **FIX**: A sheet that opens from the tab accessory on it no longer fades the accessory out and in again as it shrinks onto it from other content (a station giving way to a folded ride): on its way down to its lowest detent the accessory only comes back into sight
* **NEW**: `AdaptiveSheet.opensFromAccessory`, for a page's sheet that the tab accessory on it opens into (`AdaptiveTabAccessoryLayout.onSheet`), as a ride's card opens from its row above the tabs: at its collapsed detent only the accessory shows on the sheet's glass, where a tray would hold it; pulled up, or opened through the accessory's scope, the accessory fades out as the content fades in and stops taking touches, and the content runs on into the accessory's room, ending where the tabs begin as it would with no accessory. The pages keep their padding, so a map under the sheet does not move. A sheet that stops or starts opening from the accessory (the ride giving way to a station) eases the accessory in or out. Native iOS chrome along the bottom only; off by default
* **IMPROVEMENT**: An accessory on a page's sheet that opens from it (`AdaptiveTabAccessoryLayout.onSheet` with `AdaptiveSheet.opensFromAccessory`) moves the sheet: dragged up it pulls the sheet up under the finger, and `AdaptiveAccessoryScope.expansionOf` opens and closes the sheet as it does a tray
* **NEW**: `AdaptiveBottomBarInset.accessory` (`accessoryOf`) tells a page how much of the bottom inset is the tab accessory's on a tray, or where a tray would put it on the page's own sheet: the band above the tabs it and the room around it take. 0 elsewhere
* **FIX**: On a page's sheet (`AdaptiveTabAccessoryLayout.onSheet`) under a dialog, the sheet's glass is dimmed once, by the page's barrier, rather than again by a tray-shaped barrier over the accessory and the tabs: the tabs' capsule and the accessory's own pixels are dimmed on their own

* **NEW**: `AdaptiveSheet.keepsContentClearOfBars`, for a sheet that holds the tabs at its smallest: with a collapsed detent only its header shows there, as with Find My, its content fading in as it is pulled up and taking no touches while out of sight; and with the tabs floating over its bottom its content ends where they begin, with a clean edge, wherever the sheet is, rather than running on under what they carry with no glass of its own (a tab accessory on the sheet). Off by default
* **NEW**: `AdaptiveTabAccessoryLayout.onSheet`: the accessory and the tabs where a tray puts them, with the pages keeping the same room, but without the tray's glass: for a page whose own sheet holds the tabs at its smallest (a map's), on whose glass they sit. Moving between a tab with a tray and one with such a sheet then moves nothing in the bar
* **NEW**: `AdaptiveBottomNavigationBar.accessoryExpanded`: what the accessory's tray (`AdaptiveTabAccessoryLayout.tray`) opens into, as a sheet at its smallest opens into a taller one. Dragged up the tray grows under the finger, this unfolding between the accessory and the tabs at its own height, and springs open or closed when let go; dragged down, tapped beside (the page dimmed while it is open), another tab picked or a page pushed, it closes. The pages keep clear of the closed tray only. `AdaptiveAccessoryScope.expansionOf` hands the accessory an `AdaptiveTrayExpansion` to open, close and follow it
* **NEW**: `AdaptiveToolbarHost.sheetNavigatorKey`: a navigator the host lays over its bars, for sheets that come up over the whole screen as UIKit presents a sheet: the toolbar, the tabs with their accessory and the iPhone Duo's bar stay in sight under the sheet's barrier, dimmed with the page, rather than making way as they do for a sheet on the app's navigator. It holds nothing but what is pushed on it and takes no touches while empty
* **NEW**: `AdaptiveSheet.contentDragsSheet`: content with nothing to scroll leaves every drag to the sheet, which follows the finger at once rather than the content bouncing; and a dismissible sheet follows a drag down from its lowest detent all the way out, where it moves one step and then hands the drag to its content otherwise. Off by default
* **NEW**: `AdaptiveSheet.modal`, for a sheet that is the page of a popup route of its own: it slides down out of view with the route as it goes, however it is popped (the barrier tapped, a button, back), rather than only as the route has it; and at its tallest it stops below the toolbar the host draws over the page under it, which stays in sight above it. Off by default
* **FIX**: On the tray of `AdaptiveTabAccessoryLayout.tray` under a dialog, one barrier dims the tray, its accessory and the tabs together, rather than the capsule alone
* **NEW**: `AdaptiveBottomNavigationBar.accessoryLayout` (`AdaptiveTabAccessoryLayout`): how the native iOS 26 tab bar along the bottom sets the tab layout's accessory with its tabs. `floating` (the default) keeps it on its own glass above them. `beside` puts it in the bar's row at the trailing end of the tabs, as tall as their capsule, as iOS sets a control beside its tab bar: on a phone the tabs make room for it, at least `kBesideAccessoryMinRoom`, and keep their labels; on an iPad the two are centred together. `tray` puts it and the tabs on one glass tray, the accessory above them, as a sheet at its smallest holds the tabs: the tray floats `kAccessoryTrayInset` from the window's sides and bottom, its top corners `kAccessoryTrayCornerRadius` and its bottom ones concentric with the display's, the tabs keep their whole width, the accessory has no glass of its own, and touches on the tray stay on it. `AdaptiveAccessorySpec.layout` and `room` tell the accessory which, and how wide it may be. The pages keep clear of all of it; an accessory with nothing to show takes no tray
* **FIX**: The Flutter stand-in for `IOS26GlassSurface` with `GlassSurfaceCorners.concentric` corners, shown while its page moves, now rounds each corner as the native glass does, after the display's where it is near them, rather than all of them by the least radius: the bottom corners of a sheet or a tray no longer change as the native glass takes over
* **NEW**: `AdaptiveScaffold.extendBodyUnderDuoBar`: on the iPhone Duo, with the native chrome, the body runs under the vertical bar, as a page's background does with custom chrome, rather than ending where the bar's strip begins; the strip stays in the media query's padding for the content to keep clear of. For a page whose background (a brand shape, an image) should reach the edge. Off by default
* **NEW**: `DuoPose.controlsEdge`: how far from the bar's edge of the window the bar's controls begin. Content that keeps its usual margin from there is as far from the controls as from the other edge, where from the strip it is a margin and more away
* **NEW**: `AdaptiveAppBar.tintsBackButton`: the back button of the fixed toolbar, and that of the iPhone Duo's vertical bar, draw their chevron or cross in the bar's tint (`AdaptiveAppBar.tintColor`) as its actions do, the stand-in that shows while pages move too. Off by default: the back button keeps the system's colour
* **FIX**: The close button of the date and time picker sheet keeps the label's colour as the sheet leaves, rather than turning system blue
* **NEW**: `AdaptiveSplitView.followsCrease`: the list and the column beside it also meet where the fold runs while the device lies flat (`FoldScope.creaseOf`), as two pages of a book on the iPhone Duo's inner display or an unfolded Android foldable, the list taking the page before the fold. As on a partly open fold, a fold that would leave a column under 280 points is left alone. Off by default
* **NEW**: `AdaptiveSplitView.showDetail(settings, replace: true)` shows the page as one picked in the list wherever the last press was: it replaces what the column shows, and the list's selection follows, for a page opened from outside the split view, such as from an accessory over the tabs. Without it, a page shown after a press in the column still goes on top of it there; on a narrow window it opens over the list either way
* **NEW**: `FoldScope.creaseOf` tells where a fold runs through the window whether the device lies flat or is partly open, in window coordinates: the iPhone Duo's from the toolbar host (the fold's region, which the system reports while the device lies flat too; one that does not run through the window, such as a reading from the previous pose or one along the edge of a Split View pane, does not count), an Android fold or hinge in any state from the media query. `FoldScope.foldOf` still gives only the fold of a partly open device
* **NEW**: `AdaptiveTwoPane.followsCrease`: the panes also meet where the fold runs while the device lies flat (`FoldScope.creaseOf`), so the two halves of the iPhone Duo's inner display, or of an unfolded Android foldable, each hold one. Off by default
* **FIX**: `AdaptiveTwoPane` meets the fold where it runs through the widget rather than where it runs through the window, so its panes line up with the fold in a column of a split view, or wherever it does not fill the window; a fold beside it rather than through it leaves the panes to `proportion`. A two-pane layout that fills the window is laid out as before
* **NEW**: The native iOS 26 chrome shows a tab layout's accessory (`AdaptiveBottomNavigationBar.accessory`, a mini player or an active rental), where it only did with custom chrome: above the native tab bar on a Liquid Glass capsule of its own, as wide as the capsule of the tabs and 8 points above it (at most `kFloatingAccessoryMaxWidth`, centred over it on a wide window), and in the iPhone Duo's vertical bar on a capsule as wide as the bar's controls, in what the page's controls leave of the bar. It keeps its state as it moves between them, leaves and comes back with the tabs, makes way for a sheet or a popover and stays under a dialog's barrier as they do, and fades for the keyboard. The pages keep clear of it as of the tabs (`AdaptiveBottomBarInset`); one with nothing to show has no glass and takes no room. Its native views (the glass, a native button on it) leave the screen while it fades, Flutter stand-ins fading in their place. Apps without an accessory are unchanged
* **NEW**: `AdaptiveAccessoryScope` tells a tab accessory where it is shown (`AdaptiveAccessorySpec`: the placement, `compact` and `room`), with the native chrome as with custom chrome, so it can take the form that fits there without a frame of the app's: a full capsule along the bottom, a round control in the iPhone Duo's bar
* **NEW**: `AdaptiveKeyboardFade.holdsNativeViews`: the native views in what it fades (Liquid Glass, native buttons) leave the screen while it fades, Flutter stand-ins fading in their place, as a fade on a native view breaks its glass
* **FIX**: iPhone Duo: a tab accessory that goes away no longer leaves its room in the vertical bar, where the page's controls kept clear of it and went into the overflow menu sooner
* **FIX**: Custom chrome: a list that runs under the bar from below a docked header, with something pinned below the bar (`AdaptiveSafeAreaBar`), draws the bar's background for both as one frosted pane; the scroll view around it no longer lays a second background over the bar, which left the bar solid above a frosted strip. `debugScrollEdgeHeightsOnScreen` tells how far down each drawn background reaches
* **FIX**: A native button (`IOS26Button`, `AdaptiveButton` on iOS 26) leaves the screen while its page is covered or moves, as the glass surfaces do, a Flutter stand-in taking its place with the glyph iOS shows in it. Left on screen in a sheet under a dialog, it kept iOS from compositing what came after it anywhere but within the sheet's clip: only the sheet greyed under the dialog's barrier, in its rounded shape, and a page pushed over the dialog came up inside the sheet before it filled the screen
* **IMPROVEMENT**: The native tab bar stays under a dialog (`showDialog`, `showCupertinoDialog`) as UIKit's does, the dialog's barrier laid over the capsule it floats its tabs on, in the barrier's colour and with its animation, rather than fading out. It still makes way for a sheet or a popover, which may come up over it, and wherever iOS shows no such capsule. `IOS26NativeTabBar.onCapsuleChanged` tells where that capsule is
* **FIX**: iPhone Duo: a page in a column of a split view no longer shows a frosted title band at rest: its background comes in as the content scrolls under it, as the fixed toolbar's does, in the colour of the page's bar (`AdaptiveAppBar.backdropColor`). A list with a large title of its own no longer has an empty band above it

* **NEW**: `AdaptiveAccessorySpec.room`: how tall the accessory may be. In the iPhone Duo's vertical bar it is what the page's controls and the tabs leave of the bar, as the page's controls come first; an accessory takes a smaller form to fit rather than moving them into the overflow menu. Unbounded elsewhere
* **FIX**: iPhone Duo: the vertical bar keeps no room for the overflow control while every one of a page's controls fits, so the last ones no longer go into the menu when they would have fitted exactly
* **FIX**: An overflow menu with an action's own icon widget (`AdaptiveAppBarAction.iconWidget`) no longer throws on every frame when that widget lays itself out as it goes, such as with a `LayoutBuilder`: the menu draws it as an icon in the colour of the row, and the row performs the action
* **NEW**: `AdaptiveSafeAreaBar.isIn` tells what is pinned below a bar that it has the bar's background behind it, so it leaves its own background out rather than covering the frost with a band
* **NEW**: `AdaptiveBottomNavigationBar.hidesFor` picks the pages pushed inside the tab layout that the tabs leave for with `hidesWhenPushed`; they stay for the others. A page pushed above one it picks keeps them away until that one is popped, as with UIKit, and gets the room at the bottom back the same way
* **NEW**: `AdaptiveKeyboardFade` fades what it wraps out as the keyboard comes up and back in as it goes down: once the text field it came up for lets go of the focus, or the keyboard is down past half its height, without waiting for the system to report it gone. It takes no touches meanwhile, and a hardware keyboard, which takes no room, hides nothing. Custom chrome fades its tabs and their accessory with it wherever the keyboard would slide over them: along the bottom, in the iPhone Duo's vertical bar and floating at the bottom of the content; tabs in the top strip or a sidebar stay
* **IMPROVEMENT**: Custom chrome: tabs that leave for a page without them, or come back from one, fade all through the transition as the page covers or uncovers them, under the finger during a back swipe, rather than going in the first half of a push and only coming back at the very end of a pop. Between two tab layouts they still cross as the toolbar's controls do

* **IMPROVEMENT**: Content pinned below a bar (`AdaptiveSafeAreaBar`) is frosted with the bar as one surface rather than solid, with the hairline below it; `AdaptiveSafeAreaBar.color` sets the colour of that surface. A list below something pinned inside a scroll view with a header (a `NestedScrollView`) draws that surface itself, where the outer scroll view only reaches as far as the bar
* **NEW**: `AdaptiveAppBar.showsHairline`: off for a page whose bar runs on into something docked below it, so the two read as one surface
* **NEW**: `AdaptiveChrome.keepsTabsInVerticalBar`: the tabs in the iPhone Duo's vertical bar stay while a page is pushed inside the tab layout, as in a sidebar, the page's back button and actions above them
* **IMPROVEMENT**: `AdaptivePopover` comes out from behind its control: the control stays on top while the surface grows out of it and shrinks back into it, on a softer spring, its content growing with the surface instead of being cut off by it. Next to its control it keeps to the room below or above it rather than opening over it
* **IMPROVEMENT**: A page's bar in a popover is as tall as its controls, which sit in the popover's rounded corners
* **FIX**: iPhone Duo: a page without a bar background (its title hidden over its header) no longer draws an empty, frosted title band as its content scrolls under it
* **NEW**: `AdaptiveChrome.centerTitleBand` centres the title in the iPhone Duo's title band over the page, as an app's own bars centre theirs, rather than at the leading edge
* **IMPROVEMENT**: iPhone Duo: the title band moves out of the way as soon as a page scrolls on, before its background has come in, so it no longer flashes up and goes; a scroll view only moves it while its content runs under the band
* **NEW**: `AdaptiveAppBar.hidesOnScroll`: a page that docks part of its own header under the bar keeps the iPhone Duo's title band where it is, as moving it would leave a gap above what is docked
* **FIX**: iPhone Duo: scrolling back the list of a scroll view with a header (a `NestedScrollView`) brings the title band back once the header is gone; only the outer scroll view moved it. Scrolling sideways moves it no more
* **IMPROVEMENT**: `AdaptiveBarBackdrop` is a little more subtle, as the native bars are: less blur and less of the page's colour over the content
* **BREAKING**: Custom chrome: no scroll edge along the bottom any more, behind the tab bar, an accessory or a control floating over a page: content runs under them as it is. `AdaptiveBottomControl`, `AdaptiveScrollEdge.bottomOf` and `AdaptiveBarBackgroundSpec.bottom` are gone, and so are the soft edge at the top of a scroll view below something pinned above it and `AdaptiveChromeMetrics.pinnedEdgeHeight`: pin it with `AdaptiveSafeAreaBar` instead
* **NEW**: `AdaptiveBarBackdrop`: the background of a bar along the top as iOS 26 draws it over content scrolling underneath, the content blurred and tinted in the page's colour (thicker for a strong colour, so a brand-coloured bar reads in it), ending in a clean edge at the bottom of the bar, set off by a hairline. Custom chrome draws it unless the app brings its own background, and so do the native toolbar (where a gradient was always there) and the iPhone Duo's title band. It is in as soon as content scrolls under the bar, and gone at rest
* **NEW**: `AdaptiveSafeAreaBar` joins content a page pins below its bar, such as a search field or tabs, to the bar, as SwiftUI's `safeAreaBar` does: the page runs under both, its padding along the top grows by the pinned content's height, and the bar's background reaches below it, solid rather than see-through, as the system draws a bar with a search field in it (`AdaptiveBarBackgroundSpec.pinned`)
* **IMPROVEMENT**: iPhone Duo held sideways: the title band moves out of the way while a page scrolls on and comes back, with its background, as soon as it scrolls back or reaches its top, as the system's does. Content pinned below it (`AdaptiveSafeAreaBar`) goes with it, also on a page without a title and in the list of a split view, so a list with a search field gets the whole height while it scrolls. Over content that starts below the band it stays where it is, as there is nothing of the content to show there
* **NEW**: `AdaptiveSpringCurve`: a curve that moves as a spring does (a response and a damping ratio, as the system's springs take), with `bouncy`, `smooth` and `snappy` presets
* **NEW**: `AdaptiveDeferredStartController`: an animation controller for a route that only starts moving once its first frame is built, and holds for a frame before going away from fully in, so a route that takes a while to build, or a page underneath that takes a while to come back, does not eat into its motion
* **IMPROVEMENT**: `AdaptivePopover` springs out of its control, passing its place a little and settling, and springs back into it; its content comes in with the surface instead of after it. It waits for its content's first frame before it starts, so a menu that takes a while to build still grows out of its control all the way
* **IMPROVEMENT**: Custom chrome: the tab bar gets out of the way of a sheet or popover coming up within the first half of its fade, and only comes back as that has mostly gone, rather than showing through it
* **NEW**: `AdaptiveChromeMetrics.controlInset`: the room between the side of a custom bar and its back button and actions (16 by default, as the system's). A title with no control beside it keeps to the page's margin
* **IMPROVEMENT**: Custom chrome on the iPhone Duo: the columns of a split view run on under the vertical bar, as a whole page does, so the background of the page beside the list (a header) reaches the edge of the window, while its content keeps clear of the bar. Beside the native bar the columns lie beside it as before
* **FIX**: Custom chrome: a page's padding along the side of a sidebar or the iPhone Duo's vertical bar can no longer turn negative where something above it had already taken that side's padding away
* **IMPROVEMENT**: Custom chrome on the iPhone Duo held sideways: the tab layout's accessory sits in the vertical bar above the tabs instead of floating over the content, and the page's controls above it keep clear of it, moving into the overflow menu sooner. The pages keep no room for it at the bottom
* **IMPROVEMENT**: Custom chrome: the pages beside a sidebar (or its rail) run on under it, so the page's own background (a list, a header) goes on behind the floating sidebar with no edge between the two, as on iPadOS 26. The first page under the tab layout takes the sidebar's room over and keeps its content clear of it, or lays its body out under it with `AdaptiveScaffold.extendBodyBehindVerticalBar` and keeps clear through the padding; a split view hands the room to its list, and the column beside the list gets none. The flat backdrop in the page's colour behind the sidebar is gone
* **NEW**: `AdaptiveSplitView.opensDeeperOver`: a page opened from the page beside the list opens over the whole split view instead of on top of it in the column, so the column keeps to what was picked in the list. Off by default
* **IMPROVEMENT**: `AdaptivePopover` keeps above the keyboard: it stays where it opened and only moves up as far as the keyboard needs, and its content keeps no room for the keyboard
* **NEW**: `AdaptivePopoverSurface` marks an app's own floating surface (a sheet of its own) as a popover's content. Pages in a popover, also on a navigator of their own inside it, draw their own bar there instead of handing it to the toolbar host, with their controls in its corners
* **IMPROVEMENT**: iPhone Duo held upright: the column of a split view with nothing of the status cluster over it has the strip to itself, and its pages start level with the bar the system sets there instead of below the strip
* **IMPROVEMENT**: `AdaptivePopover`: the back or close button of a page in a popover sits in its rounded corner, as far from the side as from the top
* **FIX**: `AdaptivePopover`: its content no longer keeps the window's padding. A page in a popover (a bar, a list) left room for the status bar at its top, an empty band above its title, though the popover sits inside the safe area. A page's bar in a popover or its sheet keeps `AdaptivePopover.barInset` above itself instead, clear of the surface's rounded corners, with the page's content below it (`AdaptivePopover.isIn`)
* **FIX**: Custom chrome: a title at the leading edge with no control beside it lines up with the page's 16 point margin, in the hosted bar and in the bar inside a column, sheet or popover, where it sat 12 points further in (`kToolbarTitleSpacing`, the room kept between a title and the controls beside it)
* **IMPROVEMENT**: `AdaptivePopover` too tall to open above or below its control opens beside it, on the side with more room and level with it, so it still comes out of the control instead of covering it
* **IMPROVEMENT**: Custom chrome: a tab accessory with a frame (`AdaptiveChrome.accessoryBuilder`) floating at the bottom of the content gets the content's whole width and its frame places it, such as a small video in the corner beside the iPhone Duo's vertical bar. One without a frame is centred at most `kFloatingAccessoryMaxWidth` wide, as before
* **IMPROVEMENT**: Custom chrome draws the background under its bars as the system's scroll edge effect does: as part of each scroll view whose content runs under the bars (`AdaptiveScrollEdgeRegion`), along the top and the bottom, instead of a layer over the whole window. What a page lays over its scroll views stays clear of it, where it was washed out before: a search field or tabs pinned above a list, a segmented control or button floating over its bottom, the top of a column beside a list. A page without scroll views, such as a map, has none. Where scroll views nest, the outer one draws it along the top and the inner one along the bottom
* **IMPROVEMENT**: Custom chrome: behind a sidebar beside the pages the page in front runs on in its own colour (blended between pages as they change), so a sidebar floats over the page instead of over the tab layout's background, which showed as an edge between the two
* **FIX**: Custom chrome: a tab layout that hides its tabs (`tabBarHidden`) beside a sidebar hides the sidebar and gives its pages the room, where they kept an empty column the width of the sidebar
* **FIX**: Custom chrome: in a list with the page it opened beside it, only the list shrinks and restores the tab bar as it scrolls (`minimizeBehavior`). The two scrolling on their own made it flicker
* **FIX**: Custom chrome: a page replaced where it stands (a new page in its place without a route transition) no longer trips "A ValueNotifier was used after being disposed" as its bar fades out. The host keeps showing a page for a moment after it has gone, and still listened to the scroll edge it had handed over; that value now keeps its last state once the page is gone
* **NEW**: `AdaptiveTwoPane` lays two panes of a full screen page out around the fold of a partly open foldable: side by side on a fold down the window (held as a book), above and below one across it (standing on a table: a video above the fold, its chat below), and by `proportion` along `direction` without a fold. The panes keep their state as the device folds and as the second comes and goes, and lose the window's padding on the side they share. `FoldScope.foldOf` gives that fold for any page: the iPhone Duo's from the toolbar host, or an Android hinge or half-opened fold
* **IMPROVEMENT**: Custom chrome: a sidebar stays in sight under a dialog, sheet or popover, dimmed as the toolbar is, instead of fading out as a tab bar along the bottom does
* **IMPROVEMENT**: Each column of an `AdaptiveSplitView` is the window its pages have: their media query has the column's size, so a page beside another lays out for its own width (a phone's layout in a 380 point column), as a column of a split view controller has a compact width of its own
* **NEW**: `TabBarMinimizeBehavior.onScrollDownUntilTop` minimizes the tab bar as the page scrolls down and keeps it minimized until the page is back at its top, rather than restoring it on any scroll up. The native tab bar, which has no such behavior, minimizes on scrolling down
* **IMPROVEMENT**: Custom chrome hands the tab layout's `minimizeBehavior` to the app's tab bar (`AdaptiveTabBarSpec.minimized`), which draws its own smaller form while the page scrolls, instead of the host scaling it to 70% and half its opacity. Picking another tab brings any minimized tab bar back at full size
* **FIX**: `minimizeBehavior` no longer minimizes the tab bar while a carousel or pager scrolls sideways; only the page scrolling up and down does
* **FIX**: Custom chrome on iPhone Duo: a page without a title, with or without a bar, started at the very top of the window in the vertical bar poses, which have no inset there, so its first line ran into the display's rounded corner. It now starts level with the bar's first control (`kDuoBarEdgeMargin`), and a page with a title below the title band; the room is a floor, so a page inside a tab layout that already keeps it adds nothing
* **IMPROVEMENT**: `AdaptivePopover` grows out of the control that opened it and shrinks back into it, as the system's popovers and menus do, with its content fading in as the surface opens; the content is laid out once and only takes taps once the popover is open. `AdaptivePopoverPlacement.over` opens it in the control's place on a window of any size, from the control's edge nearest the window's (upwards from a bar along the bottom, beside the iPhone Duo's vertical bar for a control in it), for content a bar opens out of itself
* **IMPROVEMENT**: Custom chrome on the iPhone Duo's inner display held upright keeps the tabs along the bottom at full size, as the system's tab bar does there, with every page's toolbar in the strip beside the camera and status cluster. `AdaptiveChrome.tabsInTopStrip` puts the tabs in the strip as before
* **NEW**: Custom chrome follows the scroll edge: the bar's background (the app's or the default gradient) fades in as a page's content scrolls under the bar and is gone while nothing is underneath, blended from one page's scroll to the next's during a transition, as the system's scroll edge effect is. The app's background, back button and actions get it as `scrollEdge` in their spec (`AdaptiveScrollEdge`), for controls that only need a surface of their own over content. Content that only scrolls sideways leaves the bar clear, and where scroll views nest the outermost decides, as its content is what runs under the bar (a list below a header pinned under the bar scrolls under the header)
* **IMPROVEMENT**: Custom chrome takes the page's own colour (`AdaptiveScaffold.backgroundColor`) behind the bar where the bar has none, or a see-through one, rather than the system background or black
* **IMPROVEMENT**: Custom chrome on the iPhone Duo: every page's own background runs under the strip of the vertical bar, so the bar reads as part of the page, while its content keeps beside the strip. A tab layout leaves that to the pages inside it instead of keeping its whole body beside the strip, where the strip showed the tab layout's colour next to a page of another. `AdaptiveScaffold.extendBodyBehindVerticalBar` lets the body itself run under the strip too, with the strip in its padding, so a header's colour can reach into the bar
* **NEW**: Custom chrome has a scroll edge along the bottom too: behind the tab bar, an accessory floating at the bottom or the home indicator, a background in the page's colour (`AdaptiveChrome.barBackgroundBuilder` with `AdaptiveBarBackgroundSpec.bottom`) shows while the page's content runs under the bottom (`ToolbarEntry.bottomScrollEdge`, `AdaptiveScrollEdge.bottomOf`) and is gone at its end

* **IMPROVEMENT**: Custom chrome: the app's bars form a semantics container of their own, as a page's route does, so their controls are reported to accessibility services, and to UI test drivers, in their own place rather than merged into a node that spans the window
* **FIX**: Custom chrome: the app's bars sit in a transparent `Material`, as a page's content does. Above the navigator they had none, so their text showed Flutter's yellow underlined fallback style and ink effects had nowhere to draw
* **NEW**: `AdaptivePopover.show` and `showMenu` take `chromeData`, handed to the app's popover surface (`AdaptivePopoverSpec.data`), so one app can open popovers in more than one look
* **FIX**: iPhone Duo: the tabs of a tab page with its own bottom bar (`useNativeBottomBar: false`) are in the vertical bar, where the system puts tabs. Before, with a native toolbar they disappeared in the vertical bar pose, as the page left its bar out and the bar got none; without one, the page's bar stayed along the bottom
* **IMPROVEMENT**: Under custom chrome an `AdaptiveSheet` floats on the app's glass (`AdaptiveChrome.glass`) on every platform, with continuous corners, instead of the native Liquid Glass on iOS and a Material sheet on Android, so it matches the app's bars
* **NEW**: `AdaptivePopover`: content anchored to the control that opened it, drawn by Flutter on every platform, below the control or above it where there is no room, kept on screen. It keeps to the half of a partly open foldable that holds its control (the iPhone Duo's fold from the toolbar host, an Android hinge or half-opened fold), stays out of the iPhone Duo's vertical bar and opens beside it for a control in it. On a window narrower than 600 points it opens as a sheet from the bottom. `AdaptivePopover.showMenu` shows `AdaptivePopupMenuEntry` items in one, and `rectOf` gives a control's place on screen (for a share sheet). Under custom chrome the menus of the app's actions open as popovers next to the action, the iPhone Duo's overflow control shows its actions in one (`AdaptiveActionsSpec.showOverflow`), and `AdaptiveChrome.popoverBuilder` draws their surface; glass otherwise
* **NEW**: `AdaptiveBottomNavigationBar.accessory` (custom chrome), the accessory of a tab bar as on iOS 26 (Music's mini player): above a tab bar along the bottom, floating at the bottom of the content beside the iPhone Duo's vertical bar and below a page with its tabs in the top strip, and handed to the sidebar to dock (`AdaptiveSidebarSpec.accessory`). It keeps its state as it moves between them, comes and goes with the tabs, and the pages keep clear of it (`AdaptiveChromeScope.floatingAccessoryHeight`). `AdaptiveChrome.accessoryBuilder` frames it per placement (`AdaptiveAccessorySpec`)
* **NEW**: `AdaptiveChrome.sidebarBuilder`: on a window at least `sidebarMinWindowWidth` (700) wide, such as an iPad or an unfolded foldable, the tabs of custom chrome are in a sidebar along the leading edge instead of at the bottom. It is at its full width (`sidebarWidth`, 300) from `sidebarExpandedWindowWidth` (1024) on, and a rail of icons (`sidebarCollapsedWidth`, 88) below it, which the user can expand over the content (`AdaptiveSidebarSpec.onToggle`; a tap outside it or on a tab closes it again). The pages of the tab layout and their part of the toolbar sit beside it as it eases between its widths (`AdaptiveChromeScope.sidebarInsetOf`); it stays while pages are pushed inside the tab layout, whatever `hidesWhenPushed` says, and leaves for a page over the whole layout. The iPhone Duo keeps its own placements at any width
* **NEW**: Custom chrome on the iPhone Duo held upright: the app's tabs sit in the strip along the top, beside the camera and status cluster and level with it, with the toolbar below the strip. A page the tabs leave for (`hidesWhenPushed`) has its bar in the strip instead, as the native bar does, and the pages keep clear of whichever it is; nothing is kept at the bottom
* **NEW**: Custom chrome on iPhone Duo: in the vertical bar poses (the cover display, the inner display held sideways, a Split View pane) the app's back button, action groups, overflow control and tabs run down the vertical bar, each drawn by its builder in the size of the native capsule it stands for, so they line up with the system's controls and the camera exactly as the native ones do; actions that do not fit move into one overflow control while the tabs stay. The title sits in the title band, level with the first control, and pages keep out of the strip and below the band
* **NEW**: Custom chrome: `AdaptiveToolbarHost(chrome: AdaptiveChrome(...))` (or `AdaptiveApp(chrome:)`) replaces the native iOS 26 bars with the app's own, drawn by Flutter on every platform, for an app whose brand decides how its bars look. The host still places everything, as it does the native bars: the tab bar at the bottom of the screen, above the navigator, staying put while pages come and go, and the toolbar along the top, its items blended from page to page with the route transition. The app supplies builders for the tab bar, the title, the back button, a group of actions and, optionally, the backdrop; each gets a spec saying where its part goes (`AdaptiveChromePlacement`) and the page's own `chromeData` (new on `AdaptiveAppBar` and `AdaptiveBottomNavigationBar`). Pages keep using `AdaptiveScaffold`: under custom chrome it takes one platform-neutral path, keeps its content clear of the bars through the media query's padding, and draws its own bar with the app's builders where the host's does not reach (sheets, dialogs, split view columns). `AdaptiveChromeScope` tells the pages the placement. Without `chrome` nothing changes
* **NEW**: `AdaptiveBottomNavigationBar.hidesWhenPushed` (custom chrome): the tabs leave while a page pushed on the navigator of a tab is in front, as `hidesBottomBarWhenPushed` does, fading with the push and following a back swipe, and that page gets the room at the bottom back
* **NEW**: `AdaptiveGlass`, frosted glass drawn by Flutter in an app's own colours: the content underneath blurred and made more vivid, under a tint and a thin rim, in any shape, with shadows outside it. It looks the same on every platform, for an app whose brand decides how its bars look, where `IOS26GlassSurface` is the system's Liquid Glass. `AdaptiveGlassStyle` sets the tint, blur, saturation, rim and shadows, and `AdaptiveGlassTheme` hands one down. A tint without transparency or a blur of 0 draws no blur at all; with more contrast asked for (`MediaQuery.highContrast`) the glass turns opaque. Surfaces in one `BackdropGroup` share one read of the content
* **NEW**: `AdaptiveSplitView.showsDetailColumn`: false keeps the list at the full width of a wide window for now, such as while its page shows a section with nothing to open beside it (a timetable). The pages open in the column wait meanwhile, rather than move over the list, and come back with the column; a page opened meanwhile opens over the list and takes their place
* **NEW**: `AdaptiveSplitView.onPushedOver` tells navigation code of every page the split view opens over its list: one opened on a narrow window, and those that move over the list as the window narrows, so code that keeps track of the pages it opens knows of these too
* **FIX**: A split view on a tab that an app hides without `Visibility` (tabs faded out with their tickers off, all of them laid out) no longer takes the pages meant for the tab in sight, and folding on another tab no longer moves its pages over a list out of sight: they wait until its tab is selected again, as on a tab of an `IndexedStack`
* **NEW**: Exports `FoldScope` (where the fold of a partly open iPhone Duo runs), `DuoTitleBackdrop`, the iPhone Duo layout constants (`kDuoTitleBandHeight`, `kDuoVerticalBarWidth`, `kDuoBarEdgeMargin`, `kDuoBarGroupSpacing`, ...) and `kHostedToolbarHeight`, so an app can line its own controls up with the bars and the fold without importing from `src`
* **NEW**: `IOS26GlassSurface.fill` and `AdaptiveSheet.glassFill` lay a colour over the iOS glass, in its shape, under the content. A light, partly opaque fill lets less of the page behind show through, so text on the glass reads better over a busy page such as a map, while the glass keeps its edge and its blur. A `tint` cannot do that: `UIGlassEffect` keeps tinted glass as see-through, even with an opaque tint. The Flutter stand-ins of the glass lay the fill over their colour too
* **NEW**: `AdaptiveBrightnessLock` holds the app, or the part of it below, in one brightness whatever the device's, for an app without a design for the other one. The pages below get it as their platform brightness, which the native views follow, and on iOS the app's windows are held in it too, so that what UIKit draws on its own (menus, alerts, pickers) does not turn dark on a device in dark mode under a light app. With none mounted the app follows the device again
* **IMPROVEMENT**: On iOS 26+ the native tab bar stays put while pages are pushed over the tabs and popped, as the iPhone Duo vertical bar already did. `AdaptiveToolbarHost` draws it at the bottom of the screen, above the navigator, and stays at full opacity while the pages within the tabs change. A native view on screen makes every frame dearer while pages move, so the bar keeps out of the way of a transition between the tabs and a page without them, and of all of its end, where a stutter shows most: it fades out over the first fifth of a push, and stays away while a page pops or is swiped back off the tabs, to fade in once the tabs hold still. Before, it was part of the tabs page: it slid with that page under the page coming in, and Flutter drew that page over a moving native view on every frame of the transition, which stuttered on a phone. Its native view is made once and kept off stage while a page covers the tabs, instead of being made again as the page leaves. While a dialog or sheet covers the tabs the bar fades out, since it would show above it. `AdaptiveToolbarHost(hostsTabBar: false)` leaves the bar in the tabs page. Overlay content of the navigator outside any route (an `OverlayPortal`, a tooltip) shows under the bar, as it does under the fixed toolbar. A tabs page with a native toolbar of its own now colours the selected tab with `selectedItemColor` too, as one without does
* **IMPROVEMENT**: While pages are pushed, popped or swiped back, a Flutter back button takes the place of the fixed toolbar's native glass one, so no native button is on screen while the pages move; it fades out over the native button once they hold still. Its chevron or cross is the one the native button shows: iOS makes a glass button the same way, lays it out and hands over its glyph as an image, at the size, in the colour (light or dark) and in the place the button shows it, so it needs no icon font in the app. Where iOS hands over no glyph the native button stays
* **IMPROVEMENT**: A native tab bar that its page takes off screen (a tab page with its own toolbar, without a host, covered by a page) is kept off stage instead of being thrown away and made again as the page comes back
* **IMPROVEMENT**: A new native tab bar builds its items once: in the app font from the start (`AdaptiveNativeFonts`), laid out again rather than built again when the bar gets its width, and without the second full set of items, style and selection Dart used to send right after it was made. `setItems` and `setStyle` with nothing new no longer build the items again either
* **IMPROVEMENT**: The fixed chrome is no longer rebuilt for each page that publishes itself unchanged during a push or a pop, a fold reading arriving as a page is pushed no longer rebuilds that page when it has a host, the backdrop of two pages of one colour is not redrawn on every frame of their transition, and the iOS version is parsed once
* **NEW**: `PlatformInfo.debugPlatformOverride` and `PlatformInfo.debugIOSVersionOverride` let tests take the iOS 26+ or Android paths on any host. Native views keep checking the real platform, so they still draw their Flutter fallbacks off device
* **FIX**: iPhone Duo: tabs built as an `IndexedStack` inside the tab scaffold's own route (no navigator per tab) keep their tab bar in the trailing bar on every tab. Before, a tab page with an app bar found no tab layout, and the tabs disappeared. A page that leaves also uncovers the selected tab instead of a hidden one
* **NEW**: `AdaptiveAppBar.onBack`, `backButtonStyle` and `automaticallyImplyLeading`. The back button of the fixed toolbar and of the iPhone Duo trailing bar can call the page's own handler instead of popping, show a cross for pages shown like a dialog, or be left out for pages that cannot go back
* **NEW**: On iOS 26+ the native tab bar of an `AdaptiveScaffold` without an app bar raises the body's bottom padding to its measured height and publishes it through `AdaptiveBottomBarInset`, so pages keep their content clear of the floating bar while still running underneath it
* **NEW**: `AdaptiveNavigationDestination.showsBadgeDot` shows a dot without a count, on the native tab bar, in the iPhone Duo trailing bar and on the Flutter tab bars
* **NEW**: `AdaptiveNativeFonts.register` hands the app's font files to iOS, so the native tab bar labels and segmented controls draw in the app's font instead of the system font
* **NEW**: `IOS26GlassSurface`, a native Liquid Glass surface (`UIGlassEffect`) with Flutter content on top, for sheets, cards and floating panels. It rounds its corners natively (fixed, concentric with the display, or capsule) and never takes touches
* **NEW**: `AdaptiveSheet`, the floating sheet of Find My and Maps on iOS 26, with a grabber, a header that stays in view and content that scrolls when it does not fit. It moves between pixel detents (`collapsed`, `fitContent`, `fraction`, `height`, `large`, `hidden`) on springs, picks the next detent on a fling and lets drags on the content move it. On iOS it floats on native Liquid Glass with corners concentric with the display and grows edge to edge at the large detent; on Android it is a Material 3 sheet with a drag handle. From 600 points wide it becomes a floating side panel. `onSettled` reports the part of the page it covers, so a map can keep its content in view
* **FIX**: `IOS26Button` enables or disables itself again when only `onPressed` switches between null and a callback, and a new label reaches buttons that use a configuration
* **FIX**: iPhone Duo: a floating `AdaptiveSheet` keeps clear of the vertical bar instead of running underneath the tab bar in it
* **NEW**: Exports `IOS26GlassCapsule`, for a vertical group of glass controls like the map controls of Find My, and `DuoLayout`, to lay out around the iPhone Duo vertical bar
* **FIX**: Tab bar titles in the app font (`AdaptiveNativeFonts`), now in its regular weight, are no longer truncated: they were measured in the system font. Bars created before the app font was registered switch to it as soon as it is
* **NEW**: `AdaptiveFixedToolbar` shows an app bar in the fixed toolbar, and its actions in the iPhone Duo vertical bar, for a page that lays itself out without an `AdaptiveScaffold`, such as a full-screen map
* **NEW**: `AdaptiveAppBar.showsBackdrop`, to leave out the toolbar's backdrop behind a page whose controls float over content that should stay clear
* **NEW**: `AdaptiveSheet.showsGrabber`, `scrollable` and `onDismissed`: a sheet without a grabber (or the room it takes), one whose content never scrolls (a drag anywhere on it moves the sheet instead), and one that can be dragged down out of view
* **NEW**: `AdaptiveSheet.floatingMargin`, to line a floating iOS sheet up with the page's own controls: how far it keeps from the sides and from the bottom. Placed that way, its content keeps no further room for the bottom padding, so it ends as far from the sheet's bottom edge as from its sides. A sheet also settles again when its margin, padding or grabber changes
* **NEW**: `AdaptiveAppBar.backdropColor`: the fixed toolbar's backdrop takes the color of the page behind it, so the bar blends into the page at rest and only fades out what scrolls underneath. Before, it was always the system background, a white band over a grey page. The iPhone Duo title band fades out more softly too
* **FIX**: While a dialog or sheet covers the page, the fixed toolbar's backdrop fades out: over the dimmed page it showed as a lighter band with a gradient edge
* **FIX**: A window that is only part of the display and has no room at its top (iPhone Duo split view, an iPad window) keeps a 12 point margin above the fixed toolbar and its pages, clear of the window's rounded top edge. The back button only moves aside for window controls on an iPad (`PlatformInfo.isIPad`); an iPhone Duo window has none
* **NEW**: `SizeReporter` is exported, for pages that lay their own controls out around a sheet
* **FIX**: A sheet whose content changes size while it is still moving, such as content that loads while it comes up, now heads for the new size from where it is, at the speed it has. Before, it stood still for a frame and started over from rest
* **FIX**: A side panel follows its content: when the content changed size, such as content that loads after the panel came in, it kept its old height until something else rebuilt it, cutting the content off. In view it now grows and shrinks with it; coming into view it slides in at its size
* **FIX**: A tap on a sheet that is still moving leaves it on its way. Before, the touch stopped it: a sheet whose content never scrolls then settled at the nearest detent from there, or slid out if it was dismissible and not yet two thirds of the way up, and one whose content scrolls stayed where the tap caught it. A drag still takes the sheet over
* **FIX**: A page shown like a dialog (`fullscreenDialog`) keeps its cross while it closes, in the fixed toolbar and in the iPhone Duo vertical bar. Before, the shared back button took the look of the page below as soon as that page owned the chrome, and turned into a chevron for the rest of the transition. A back button both pages show the same way still stays put
* **FIX**: The fixed toolbar of a page shown like a dialog slides up and down with the page, as a modal's own navigation bar does, instead of fading in place: its title, cross and backdrop no longer linger over the page below while the page slides away
* **FIX**: The Liquid Glass of a page no longer shows through a page pushed over it, a full-screen dialog sliding over it, or a dialog or sheet on top of it. An `IOS26GlassSurface` shows its native glass only while its page holds still in front; meanwhile a light Flutter stand-in in the glass's shape and tint takes its place, and fades out over the glass once it is back. The glass of a page coming in is created once the page has arrived, and the glass of a covered page is kept, off stage, rather than created again. Fewer native views on screen during transitions also makes them smoother. The toolbar host tells the pages when one is pushed, popped or dragged back (`ToolbarBlend.routeTransition`): a full-screen dialog does not move the page below it
* **FIX**: The back button of the fixed toolbar is a circle as tall as the bar, with the system's glyph (`SFSymbol.weight`, new), centred in the bar like the system's back button; before, it was a smaller rounded square. One button of each look (back and close) is kept from page to page instead of a native button being created on every transition
* **IMPROVEMENT**: A page whose title Flutter draws and that has no bar buttons gets no native navigation bar in the fixed toolbar: one native view less for most pages, and for every transition between them
* **NEW**: `AdaptiveScrollInsets` lets a page's scroll view rest below the fixed toolbar (and above a floating tab bar) and scroll underneath them, like a UIKit scroll view with content insets. `appliesTo` looks through wrappers (padding, safe areas, inherited widgets, `Expanded`) and into a column that starts with the scroll view
* **FIX**: With the keyboard up, a page with a toolbar in the iOS 26 scaffold no longer makes room for the keyboard twice, which left a blank pane above it: the page's `MediaQuery` now comes from inside the `CupertinoPageScaffold`, without the keyboard's inset that it already made room for
* **IMPROVEMENT**: The keyboard sliding in no longer rebuilds the toolbar host, the fixed toolbar or the scaffolds of the pages on every frame of its animation, and the scaffolds no longer publish their app bar to the toolbar again on each of those frames. Only small widgets that hand the pages the new insets follow every change of the media query; the rest read only the paddings and sizes they use
* **NEW**: `PlatformInfo.displayCornerRadius`, the radius of the display's corners (iOS 26, measured with `UIView.effectiveRadius(corner:)` once the toolbar host loads the device, and again when the window changes size, as on the iPhone Duo), and `IOS26GlassSurface.concentricRadius`, the radius concentric corners take at a given distance from the display's edges. Content near the bottom corners of a floating sheet can keep more room from them the rounder they are
* **FIX**: A title Flutter draws in the fixed toolbar (`titleWidget`) keeps clear of the back button and the bar buttons, centred between them, as the system's title does: a long title ends in an ellipsis before it reaches them instead of running into the back button. `IOS26NativeToolbar.reservesLeading` and `leadingInset` tell the bar about a leading control drawn over it, such as the toolbar host's back button
* **NEW**: `AdaptiveToast`, a short message that slides in at the top of the screen and goes again by itself, like a system banner: on Liquid Glass on iOS 26, a Material 3 card elsewhere, taken away sooner by a tap or an upward swipe. `AdaptiveToolbarHost` shows toasts above its bars (`AdaptiveToastLayer`), never behind the fixed toolbar or the iPhone Duo vertical bar, and a toast is no route, so the toolbar of the page under it is not dimmed
* **FIX**: The iOS banner of `AdaptiveSnackBar` shows above the fixed toolbar instead of behind it
* **NEW**: On iOS 26, `AdaptiveDatePicker` shows the system's date picker (`IOS26DatePicker`, a native `UIDatePicker`: its calendar by default, which switches to month and year wheels from its header, or its wheels) in a sheet floating on Liquid Glass, with a close button and a checkmark that confirms, as iOS 26 sheets do. New: `title`, `tintColor` and `iosStyle`. Older iOS versions keep the Cupertino wheels, Android the Material date picker
* **IMPROVEMENT**: In the date picker sheet of iOS 26, the checkmark on the calendar's month and year wheels goes back to its days instead of confirming: a month and a year are not a date yet, and the checkmark is where one would confirm them. On the days it confirms. `IOS26DatePickerController.showDays` does the same for other screens. Should a later iOS lay the calendar out differently, the checkmark simply confirms
* **FIX**: The date picker of iOS 26 could hang the app as it opened, at some widths (the iPhone Duo cover display) and at the largest text sizes: the calendar was left to find its own height and laid itself out again and again. It now fills its view on every side, measures the height it needs once for each width and text size (again when the text size changes), and gets the room there is when that is less, the sheet staying below the status bar
* **IMPROVEMENT**: The labels of the iOS 26 native tab bar keep one size whatever the text size, as the system's do; at the accessibility text sizes, a finger held on a tab now shows it large in the middle of the screen, as in the system's apps, and lifting it selects the tab. The system's large content viewer does not start on a standalone tab bar (the bar's own selection gesture keeps it from starting), so the bar shows a panel of its own in the same style. The native tab bar also gets its touches at once (an eager gesture recognizer instead of a tap recognizer), so a finger held on a tab or sliding across the tabs reaches it while the finger is down
* **NEW**: `AdaptiveKeyboardDismissal` closes the keyboard on a tap anywhere but on a text field or what belongs to it (its `TextFieldTapRegion`), native views such as the fixed toolbar's buttons included, while scrolling and dragging leave it up. `AdaptiveKeyboardDismissal.dismiss()` takes the focus from the text field that has it, and also hides a keyboard that no text field holds any more
* **FIX**: A side panel that slides out of view now leaves its area completely, however far from the edge it floats, such as beside the iPhone Duo vertical bar on the left. On Android it is also cut off at the edge of its area: beside a navigation rail it slid over the rail and stayed partly in view
* **NEW**: `AdaptiveSplitView`, a list and the page picked from it side by side, as `UISplitViewController` shows them on iPad and the iPhone Duo inner display, and as the list-detail layout of Material 3 does on tablets and foldables. On a wide window the list keeps the leading column and the pages picked from it open in a column beside it, each column with its own bar, divided by a hairline. A page picked in the list replaces what the column shows at once, as a sidebar does, and the list can show which one is open (`selectedDetailOf`); a page opened from a page in the column slides in over it and goes back with its back button or a swipe from the column's edge. Until something is picked the column shows `initialDetail`. On a narrow window only the list shows and pages open over it as usual; when the window narrows, such as when a foldable is folded, the pages picked in the list move onto the outer navigator and stay on screen. Navigation code hands pages over with `showDetail`, which returns false when no split view in front shows a column. A pop of the outer navigator, such as Android's back button or a page's own back handler, goes back in the column first, and `willGoBackFrom` lets the list's own close button close its page instead
* **IMPROVEMENT**: A page that draws its own iOS 26 toolbar instead of the fixed toolbar, such as a page in a column of a split view, follows `AdaptiveAppBar.onBack`, `backButtonStyle` and `automaticallyImplyLeading` as the fixed toolbar does: its back button calls the page's handler, shows a cross for a page shown like a dialog, and stays away where the app bar asks it to. Before, it showed a chevron whenever its navigator could pop and always popped it
* **FIX**: On Android a side panel that slides out of view is now really cut off at the edge of its area: the slide moves it as it is painted, after layout, so the clip of the area did not cover it, and beside a navigation rail it still showed. A side panel is also as tall as its content again: on Android it lost the room below its content, and floating further from the bottom than 8 points it kept too much
* **IMPROVEMENT**: In the iPhone Duo vertical bar pose the pages in the columns of an `AdaptiveSplitView` hand their back button and actions to the vertical bar of the fixed toolbar, as every other page does, and each keeps its title in its column, at the leading edge and with the room above it of the toolbar's title band. Before, they kept a bar of their own at the very top of their column. `ToolbarChromeScope` is exported, for a page that draws its own title to tell where the controls are
* **IMPROVEMENT**: Folding or unfolding a foldable with an `AdaptiveSplitView` lands the user where they were. On a narrow window the split view opens the pages it is given over its list itself and keeps them in mind; as the window widens, they move into the column beside the list, as deep as they were, with the list showing which one is open, also while they covered the list's page. As the window narrows, the pages beside the list move over it at once instead of sliding in, and still slide away when the user goes back. `AdaptiveSplitView.isInList` tells the rows of the list that they open pages beside it, so they can leave out their chevrons
* **FIX**: `AdaptiveSplitView` keeps the user's place more reliably across folds. The list always shows as open the page the column starts with, whatever brought it there: after an unfold it could show the first item while the column showed the page the user had open. A window that narrows again while the pages move into the column, as a fold can, moves them back over the list instead of losing them, and the split view takes no width it is handed before they are gone as the window's. Folding also keeps the pages opened from the page shown first, not only those picked in the list
* **FIX**: An `AdaptiveSplitView` that widens again shows what the user is on. A page opened over the list on the narrow window, that the user had gone back from, came back beside the list on the next unfold: the split view remembered it as picked. It now only takes along the pages still open over the list, and otherwise shows the page shown first. A column that comes back, also in the same frame as it went, gets a navigator of its own instead of the one of the column before, with that column's pages
* **IMPROVEMENT**: On Android `AdaptiveSegmentedControl` is a Material 3 Expressive pill instead of an outlined `SegmentedButton` with a checkmark: a tonal track with the selected segment a filled pill in `color` that slides to the segment picked (at once with reduced motion). TalkBack reads each segment as a button in a group, with its selected state
* **IMPROVEMENT**: On a foldable held partly open with its fold running down the window, such as the iPhone Duo held like a book, `AdaptiveSplitView` moves its divider onto the fold, as `UISplitViewController` does and as the list-detail layout of Material 3 does on Android, and back as the foldable lies flat. The divider slides there; the columns keep their widths at once as the window changes size. A fold across the window, or too close to an edge for a column, is left alone. On iOS the fold comes from the `AdaptiveToolbarHost` above, which now also hands it to the pages below
* **IMPROVEMENT**: On the iPhone Duo inner display held upright, the navigation bar sits in the hardware strip along the top, beside the camera and status cluster, as the system sets it, instead of below the strip: the fixed toolbar, the bar of a page drawing its own, and the bars of the columns of an `AdaptiveSplitView`. Its controls keep clear of the cluster, the title stays centred, and the page's content starts below the strip. `DuoTopStrip` and `DuoTopStripScope` tell where the bar is. The native bar now takes its height from Flutter instead of the window's safe area
* **FIX**: `AdaptiveScrollInsets` no longer throws when the insets change on a page that was never laid out, such as the pages an `AdaptiveSplitView` moves over its list as the window narrows, all but the top one covered from their first frame. Rotating the iPhone Duo back with such pages open ended in a red screen. Such a page now starts at the new rest offset once uncovered
* **IMPROVEMENT**: An `AdaptiveToast` with a `color` on iOS 26 keeps its glass as see-through as the default white one: the color tints the glass at 85% instead of covering it
* **MERGE**: Takes in 1.0.2. Where 1.0.2 and the fork changed the same thing:
  * The back button of the fixed toolbar and of the iPhone Duo vertical bar keeps the fork's look and its own handler and cross (`onBack`, `backButtonStyle`), now with the `large` size of 1.0.2. Both bars keep 1.0.2's semantics fix: every layer stays in the semantics tree, and the one that is not in front is left out
  * `ToolbarEntry.shownInPlace` of 1.0.2 replaces the fork's `selected`. Below a page leaving, a tab shown in place still wins, and a hidden tab is only the answer when none is shown
  * `AdaptiveNavigationDestination.showsBadgeDot` stays next to `badgeText`, `badgeColor` and `badgeTextColor`, and applies when there is neither a count nor a text
  * `AdaptiveToolbarHost` resolves the iPhone Duo pose as 1.0.2 does, the leading Split View pane included, and keeps the fork's top margin for windows without room at the top, its fold for the pages below and its toast layer
  * The iOS 26 scaffold resolves the pose as 1.0.2 does, but still reads only the paddings, so the keyboard sliding in does not rebuild the page
  * A floating `AdaptiveSheet` keeps clear of the vertical bar on the side the pose names, now also in the leading Split View pane. `DuoPose` and `DuoPoseScope` are exported

## [1.0.2]
* **FIX**: iOS 26: the fixed toolbar's automatic back button is now a 44-point circle like the native one, instead of a 38-point rounded square, and sits level with the title. The page-owned toolbar's back button is circular too (@Anderzzon, #171)
* **FIX**: iPhone Duo: in Split View, an app in the left pane now shows its controls and tab bar in a vertical bar on the left edge, as native apps do. It used to fall back to horizontal bars. The side now comes from the system's vertical bar edge (iOS 27.1) instead of the safe-area insets alone (@sergi-labhouse)
  * Adds a Swift source file. With CocoaPods and a path or git dependency, if the iOS build fails with `cannot find 'VerticalBarEdgeStreamHandler' in scope`, run `pod install` in your `ios/` folder
* **FIX**: iPhone Duo: in the left Split View pane the package reserves the strip itself, as UIKit only adds that inset for bars it draws, so the page body and `SafeArea` stay clear of the bar. The controls start near the top of the pane, since there is no camera there (@sergi-labhouse)
* **IMPROVEMENT**: iPhone Duo: when the system gives no inset for the strip, its width now matches the system's 84 pt (it was 60 pt) (@sergi-labhouse)
* **FIX**: iOS 26: reversing an interactive back swipe under the fixed toolbar could throw `SemanticsNode._replaceChildren` with a screen reader on. Every layer of the fixed chrome now keeps its semantics attached, and the layer that is not in front is excluded explicitly, so VoiceOver never lands on invisible items. Reported and diagnosed by @Anderzzon (#166)
* **FIX**: iOS: `resizeToAvoidBottomInset` is now honored on the plain page branch (no app bar, no tab bar) and in the drawer wrapper, so a body anchored to the bottom is no longer lifted above the keyboard when it is set to `false` (@Danilo-Mota, #158)
* **FIX**: Fixed toolbar: dragging back from a page pushed over an `IndexedStack` tab layout showed the bar of the last mounted tab instead of the selected one (@DFelten, #164)
* **FIX**: Android: the plugin module now targets JVM 17 for both Java and Kotlin. Apps on AGP 8 / Kotlin 2 that force Kotlin to 17 failed with "Inconsistent JVM-target compatibility" (@goalbypro reported it in #119, @bryandelgado99 proposed the fix in #160)
* **FIX**: iOS: the selected `AdaptiveRadio` is drawn as a ring with an inner dot, as in UIKit, instead of a filled circle (@luflow, #154)
* **NEW**: `borderColor` and `borderWidth` on `AdaptiveCard` for iOS; the default stays a hairline separator (@luflow, #153)
* **IMPROVEMENT**: Example app adopts the UIScene lifecycle, matching Flutter's template (@luflow, #151)
* **FIX**: iOS 26 alert dialogs: the primary button now takes `CupertinoTheme.primaryColor` instead of a hardcoded system blue (@Qian-Samuel, #121)
* **NEW**: `badgeText`, `badgeColor` and `badgeTextColor` on `AdaptiveNavigationDestination`. Arbitrary badge text and colors on the iOS 26+ native tab bar (`UITabBarItem.badgeValue` / `badgeColor`), and the same fields drawn through `AdaptiveBadge` on iOS <26 and Android; a transparent `badgeColor` with a glyph gives a dot indicator (@terrykang90, #127)
* **NEW**: `menuItems` and `onMenuItemSelected` on `AdaptiveAppBarAction` turn an app bar action into a menu button: a native `UIMenu` on iOS 26+ (in the fixed toolbar and the iPhone Duo capsule too), an action sheet on iOS <26, a popup menu on Android (@DFelten, #163)
* **NEW**: `AdaptivePopupMenuDivider(title:)` names the group that follows it: an inline section title in the native iOS 26 menu, a heading in the action sheet on iOS <26, a heading row on Android (@luflow, #149)
* **NEW**: `selected` on `AdaptivePopupMenuItem` shows the current choice: the system checkmark in native iOS menus, a trailing check on Android, a leading check in the iOS <26 action sheet (@gem85247, #147)
* **FIX**: iOS 26 `AdaptiveButton` in child mode (icon or custom child): `minSize` is now a minimum instead of a fixed width (a `Size(0, h)` no longer collapses the button), and the content gets the same 16pt horizontal padding as the other platforms, so such buttons can come out slightly wider than before (@gem85247, #147)
* **FIX**: iOS 26 tab bar: the app's text direction is also written to `traitOverrides.layoutDirection`, so the selected Liquid Glass item follows the app locale when it differs from the device locale (@KhalidSaud, #140)
* **IMPROVEMENT**: Example app moved from CocoaPods to Swift Package Manager (@luflow, #150)
* **NEW**: `AdaptiveContextMenu` on iOS 26+ is a native `UIContextMenuInteraction` with Liquid Glass: the child lifts as the preview and the actions are a `UIMenu` (title, SF Symbol, disabled, destructive). iOS <26 and Android are unchanged. Pass an SF Symbol name as `icon` for the iOS 26 menu (@itsatifsiddiqui, #161)
* **NEW**: The plugin now also gains `iOS26ContextMenuView`; CocoaPods users on a path or git dependency may need `pod install` to pick up the new Swift files
* **FIX**: Adding or removing `AdaptiveAppBar.actions` within the same page now reaches the iOS 26 native toolbar even when the list starts out `null`. Before, the change only showed after leaving and re-entering the page (#84)
* **FIX**: `AdaptiveScaffold` with a native tab bar mounted its body once per destination, so every page's `initState` ran as many times as there were tabs, and again on each tab switch. The body is now mounted once and kept across tab switches (#76)
* **FIX**: `AdaptiveSwitch` on iOS 18 and below is system green again instead of the theme's blue tint, matching every other switch on those versions (#94)
* **NEW**: `AdaptiveScaffold.extendBody` lets the body run under a custom floating bottom bar on Android and iOS 18 and below, so the bar's margins show the content instead of the scaffold background (#144)
* **NEW**: `AdaptiveScaffold.backgroundColor` sets the page background on every platform, including the iOS 26 native scaffold (#60, #95)
* **NEW**: `AdaptivePopupMenuButton.icon` takes `iconSize`, the glyph's point size on Android, iOS 18 and the iOS 26 native button (#139)
* **FIX**: Example: the Info page no longer overflows on the repository URL row (#50)
* **FIX**: `AdaptiveTabBarView` labels are readable on every background: on Android a custom or transparent `backgroundColor` now gets contrasting labels instead of white, and on iOS the selected segment's label contrasts with `selectedColor` (black thumb, white text). `unselectedColor` now reaches the iOS segments, and `selectedLabelColor` sets the selected label explicitly (#37)
* **FIX**: An opaque `AdaptiveScaffold.backgroundColor` also sets the status bar style, so a dark page in a light theme keeps light status icons. A page's own `AnnotatedRegion<SystemUiOverlayStyle>` still takes precedence (#77)

Thanks to everyone who shaped this release with code, reports and reviews: @luflow, @sergi-labhouse, @DFelten, @gem85247, @Anderzzon, @itsatifsiddiqui, @Danilo-Mota, @terrykang90, @KhalidSaud, @Qian-Samuel, @goalbypro, @bryandelgado99, @primer03, @pento, @Crucialjun, @robert-virkus and the reporters of #76, #84, #94, #144, #37, #77, #50, #139, #60 and #95. Who did what is in [CONTRIBUTORS.md](https://github.com/berkaycatak/adaptive_platform_ui/blob/main/CONTRIBUTORS.md).

## [1.0.1]
* **FIX**: 📱 **iPhone Duo: the tab bar now lives in the vertical bar**, at the bottom of it, the way the system lays it out. In 1.0.0 it stayed at the bottom of the screen. The strip now reads, from the top: status cluster, back button, toolbar items, tab bar. Measured against a native UIKit app on the iPhone Duo simulator
* **FIX**: iPhone Duo: the vertical bar follows the hardware through every rotation. On the cover display in landscape it stays on the side, including the rotation that puts the strip on the left, and it keeps clear of the camera wherever the rotation puts it (top or bottom of the strip). In 1.0.0 rotating fell back to horizontal bars. The inner display in portrait keeps horizontal bars, as it does in UIKit
* **IMPROVEMENT**: iPhone Duo: toolbar items are grouped into native Liquid Glass capsules, one per group (groups are split by `spacerAfter`), with the back button as a round control on top, matching the system's sizes and spacing. The title moves to the leading edge, and content scrolling under it is blurred and faded like the system's scroll edge effect
* **NEW**: iPhone Duo: when the strip runs out of room, toolbar items move, from the bottom up, into the system overflow menu while the tab bar stays whole. A group can be split, so its first items stay visible
* **NEW**: `label` on `AdaptiveAppBarAction`, a short name such as "Undo". It names the action in the iPhone Duo overflow menu, for VoiceOver on iOS, and as the tooltip on Android. Unlike `title`, it never replaces the icon with text. Give every icon action one
* **FIX**: iPhone Duo: an action with only `icon` or `iconWidget` (no `iosSymbol`) showed up empty in the vertical bar
* **FIX**: A custom bottom bar (`useNativeBottomBar: false`) is left where it is on iPhone Duo; only the native tab bar moves into the vertical bar
* **FIX**: Example app: the Profile tab had no route, so Search could not be opened and Profile opened Search

## [1.0.0]
* **BREAKING**: The minimum iOS deployment target is now 15.0 (was 13.0). Xcode 27 no longer builds below 15.0. Set `platform :ios, '15.0'` in your `ios/Podfile` and `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in the Runner project
* **BREAKING**: On iOS 26+ the native toolbar is no longer part of a page. With `AdaptiveApp`, every `AdaptiveScaffold` with `AdaptiveAppBar(useNativeToolbar: true)` hands its app bar to one fixed toolbar above the navigator. No code change is needed for ordinary pages. `AdaptiveAppBar.leading`, `titleWidget` and `AdaptiveAppBarAction.iconWidget` are now built above the navigator, so they must not look up `Navigator.of(context)` or page-level inherited widgets from their own `context`; capture the page's context in the callback instead. `useHeroBackButton` has no effect while the fixed toolbar is in use, because the back button already stays in place. See "Migrating to 1.0.0" in the README
* **NEW**: 📱 **iPhone Duo support.** Apple's foldable iPhone works out of the box, open and folded. On the inner display, and on the cover display while folded, toolbar controls move into a fixed vertical bar in the trailing strip the system reserves, clear of the camera and status cluster, while the title stays on top. Nothing to set up
* **NEW**: On iPhone Duo the scaffold keeps the page body out of the trailing strip, the way UIKit does, so a page that does not use `SafeArea` no longer runs underneath the status cluster and the vertical bar
* **NEW**: Fixed Liquid Glass toolbar on iOS 26+. One toolbar stays in place while pages slide underneath it, and only its items change. The outgoing page's items fade out and the incoming page's fade in, driven by the route's own animation, so the change lasts exactly as long as the page transition, follows a back swipe under the finger and reverses when the swipe is cancelled. A back button that both pages show stays put. Dialogs and sheets leave the toolbar in place, dimmed and not tappable
* **NEW**: `AdaptiveToolbarHost`, for apps that do not use `AdaptiveApp`. Install it in the app `builder`. It is router-agnostic: it relies on the widget tree only, not on a `NavigatorObserver`, so it works with `Navigator`, GoRouter (including `StatefulShellRoute`), auto_route, nested navigators and tabs
* **NEW**: `useFixedToolbar` on `AdaptiveScaffold` (default `true`). Set it to `false` for a scaffold that does not fill the screen from the top, such as one pane of a side by side layout, so it keeps its own toolbar. Scaffolds shown in a sheet, dialog or popup do this automatically
* **NEW**: Depends on `foldable` ^1.0.3 for the iPhone Duo reserved regions
* **FIX**: Builds with Xcode 27: `Package.swift` now declares its `FlutterFramework` dependency

## [0.1.111]
* **NEW**: Custom SF Symbols on iOS. `AdaptiveAppBarAction`, native buttons, and the tab bar now fall back to a bundle asset (`UIImage(named:)`) when a name is not a system SF Symbol, so custom symbols or images from the app's asset catalog work (@hieutbui)
* **NEW**: `iconWidget` on `AdaptiveAppBarAction` for a custom fallback widget (e.g. an SVG) on iOS <26 and Android (@hieutbui)
* **NEW**: Per-state SF Symbols on the iOS 26+ native tab bar. `AdaptiveNavigationDestination.selectedIcon` now accepts a distinct SF Symbol name for the selected state (outline when unselected, filled when selected) (@hieutbui, @philipgiuliani)
* **NEW**: `minuteInterval` on `AdaptiveTimePicker` and `AdaptiveDatePicker` restricts selectable minutes to a fixed grid (e.g. 15-minute steps). iOS uses the native `minuteInterval`; Android snaps the picked value onto the grid (@luflow)
* **NEW**: `AdaptiveDatePicker` now honors `dateAndTime` and `monthYear` modes on Android too, with `use24HourFormat` support (@luflow)

## [0.1.110]
* **NEW**: `subtitle` and `titleWidget` on `AdaptiveAppBar`. Show a smaller subtitle below the title, or replace the title area with any widget. Works on iOS 26+ native toolbar (centered overlay), iOS <26 `CupertinoNavigationBar`, and Material `AppBar` (@luflow)
* **NEW**: `subtitle` and `imageBytes` on `AdaptivePopupMenuItem`. Subtitles render natively via `UIAction.subtitle` on iOS 15+, and image bytes (e.g. avatars) are shown clipped to a circle on iOS 26+ native menus, Material popup menus, and the iOS <26 action-sheet fallback (@luflow)
* **IMPROVEMENT**: iOS 26+ native toolbar now insets the body's top padding by the toolbar height, so `SafeArea`/`SliverSafeArea` inside a page clear the Liquid Glass toolbar automatically, matching how `CupertinoPageScaffold` handles a translucent navigation bar. Removes the need for per-screen top-offset hacks (@luflow)
* **FIX**: Material alert dialogs now place the cancel (dismissive) button on the left, matching the Material 3 dialog guidelines (@luflow)
* **FIX**: iOS status bar style now follows the effective theme brightness on the Cupertino path, so it stays legible when a forced `ThemeMode` differs from the system brightness (@luflow)
* **FIX**: Fixed iOS 16+ popup menu items being reordered by the system by setting `preferredMenuElementOrder = .fixed`, so items keep their declared order (@Sahil-Kundaliya)
* **FIX**: Fixed an unbounded-width crash when an iOS 26 text popup button is placed directly in a `Row`, before its native intrinsic width has been measured
* **FIX**: Silenced an iOS 26 native button Auto Layout constraint conflict that logged on every layout pass

## [0.1.109]
* **NEW**: `triggerOnLongPress` and `onTap` on popup menu buttons — tap fires `onTap`, long-press opens the menu (@yuriylybimov)
* **NEW**: `isDestructive` on `AdaptivePopupMenuItem` — renders destructive (red) styling on Material, iOS <26, and iOS 26+ native menus (@yuriylybimov)
* **FIX**: destructive menu items now use the theme `colorScheme.error` instead of a hardcoded red (@yuriylybimov)
* **FIX**: `IOSSpringCurve` no longer clamps its output to [0,1], restoring the natural spring overshoot in the mid-range (endpoints remain exact) (@yuriylybimov)
* **NEW**: Exported `IOSSpringCurve` from the package's public API (@yuriylybimov)

## [0.1.108]
* **IMPROVEMENT**: Migrated the iOS plugin from CocoaPods to Swift Package Manager — apps with SPM enabled (`flutter config --enable-swift-package-manager`) now consume the plugin as a Swift package, while CocoaPods-based projects keep working unchanged (@philipgiuliani)
* **IMPROVEMENT**: Raised the iOS minimum deployment target from 12.0 to 13.0, matching Flutter's supported minimum (@philipgiuliani)

## [0.1.107]
* **NEW**: Added `resizeToAvoidBottomInset` prop to `AdaptiveScaffold` for explicit control over keyboard-driven scaffold resizing across all platform paths (iOS 26+, iOS <26, Android) (@philasmar)
* **FIX**: Fixed iOS 26+ native tab bar rendering with truncated/ellipsized labels on cold launch — replaced timing-based retry with a layout-aware container that rebuilds items when the platform view receives its real width (@philasmar)

## [0.1.106]
* **NEW**: Added `ImageProvider` support (`AssetImage`, `FileImage`, `NetworkImage`) for `AdaptiveBottomNavigationBar` icons — including async network image loading with caching and circular avatar rendering for iOS 26+ native tab bar (@philasmar)
* **NEW**: Added `textColor` and `selectedTextColor` props to `AdaptiveSegmentedControl` for explicit label color customization across iOS 26+, iOS <26, and Android (@philasmar)
* **FIX**: Fixed dimmed background removal delay when closing iOS 26+ alert dialogs — removed redundant Flutter-side overlays so only the native `UIAlertController` dim is used (@ctrl-Felix)

## [0.1.105]
* **NEW**: Added `ImageIcon` / `AssetImage` support for iOS 26+ native tab bar — custom asset icons (with optional per-state selected icon) can now be used alongside SF Symbols (@Mohamed-7018)
* **NEW**: Added automatic RTL (right-to-left) layout support for iOS 26+ native tab bar — mirrors automatically based on `Directionality.of(context)` (@Mohamed-7018)
* **NEW**: Added `hideBottomDivider` prop to `AdaptiveListTile` for removing the bottom separator, useful for the last tile in a grouped list (@ctrl-Felix)
* **NEW**: Added `separatorColor` prop to `AdaptiveListTile` for customizing the iOS bottom separator color (@philasmar)
* **FIX**: Fixed iOS 26+ alert dialog incorrectly tinting the cancel button red when no primary action was present (@philasmar)
* **FIX**: Removed unnecessary empty vertical space in message-only alert dialogs on Android and iOS <26 (@philasmar)
* **FIX**: Fixed iOS segmented control inactive label colors not following the app theme on iOS 26+, and removed vertical overflow on older iOS versions (@philasmar)

## [0.1.104]
* **NEW**: Added `tabBarHidden` prop to `AdaptiveScaffold` to hide the native iOS 26+ tab bar — prevents native `UITabBar` from bleeding through `showModalBottomSheet` (@DmitriiSer)
* **NEW**: Added `tintColor` support for iOS 26+ native toolbar and `prominent` button style for `AdaptiveAppBarAction` (@luflow)
* **FIX**: Fixed dynamic title updates not reflecting on iOS 26+ native toolbar (@Qian-Samuel)
* **FIX**: Fixed back button being obscured by window toolbar in iPadOS 26 windowed mode (@rivafarabi)

## [0.1.103]
* **FIX**: Fixed iOS 18 navigation bar not being displayed (@adrianorios)

## [0.1.102]
* **IMPROVEMENT**: Adjusted back button leading position on iOS 26+ native toolbar for better alignment
* **NEW**: Added brightness synchronization for iOS 26+ components — native buttons, switches, sliders, segmented controls, toolbar, and blur view now react to light/dark mode changes
* **NEW**: Added `cupertinoDecoration` property to AdaptiveTextField and AdaptiveTextFormField for customizable iOS styling
* **NEW**: Added drawer and endDrawer support to AdaptiveScaffold with full Material drawer behavior on all platforms
* **FIX**: Prevented native tab bar from floating above keyboard on iOS 26+ (@marcofucito)

## [0.1.101]
* **NEW**: Added `enableToolbarGradient` option to AdaptiveScaffold for iOS 26+ toolbar gradient customization (@nadavfima)
* **NEW**: Added `extendBodyBehindAppBar` option to AdaptiveScaffold (@Crucialjun)
* **NEW**: Added `scaffoldMessengerKey` parameter to AdaptiveApp (@Crucialjun)
* **NEW**: Added `autofillHints` support to AdaptiveTextFormField (@Crucialjun)
* **NEW**: Added `onTapOutside` callback to AdaptiveTextFormField
* **FIX**: Fixed missing return result from AdaptiveDatePicker (@obrunsmann)
* **FIX**: Fixed AdaptiveSwitch iOS 26 flutter container size (@PetrKubes97)
* **FIX**: Improved AdaptiveButton icon alignment and sizing

## [0.1.100]
* **FIX**: Theme color support across all components
  * All adaptive components now properly use theme colors when no explicit color provided
  * iOS: Uses `CupertinoTheme.of(context).primaryColor`
  * Android: Uses `Theme.of(context).colorScheme.primary`
  * Material button styles now respect `elevatedButtonTheme`, `textButtonTheme`, etc.
* **FIX**: iOS button width handling in Row/Flex layouts
  * iOS 26+ native buttons now properly size to content width
  * Removed forced full-width constraint in Swift implementation
  * Buttons work correctly with `mainAxisAlignment: MainAxisAlignment.spaceBetween`
* **FIX**: Dark mode text color issues on iOS
  * Text now automatically switches to white in dark mode, black in light mode
  * Applied to all scaffold implementations (iOS 26+ and legacy)
* **FIX**: Android TextField suffix spacing issue
  * Suffix widget now uses `suffixIcon` internally to prevent extra vertical space
  * Added `isDense: true` to reduce padding
* **FIX**: Android AppBar back button visibility
  * Back button now shows even when title is not provided
* **FIX**: Material context issues in AdaptiveScaffold
  * Scaffold now always used on Android to ensure Material context

## [0.1.99]
* **NEW**: Added `AdaptiveBlurView` widget - iOS 26+ Liquid Glass blur effects
  * iOS 26+: Native UIVisualEffectView with system blur styles (systemMaterial, systemThick, systemThin, etc.)
  * iOS <26 & Android: Flutter-based BackdropFilter with gaussian blur
  * Supports custom blur styles and border radius
  * Perfect for overlays, card backgrounds, and glassmorphic effects
* **FIX**: Fixed `unselectedItemColor` behavior in AdaptiveBottomNavigationBar
  * When `unselectedItemColor` is null, now uses theme's default color instead of forcing a color
  * iOS 26+: Uses `.alwaysTemplate` rendering mode when no custom color provided
  * CupertinoTabBar: Removed forced `CupertinoColors.inactiveGray` fallback
* **FIX**: Fixed iOS 26 toolbar layout issues
  * Back button now stays on the left when title is missing
  * Actions now properly align to the right when title is missing
  * Improved flexible space handling for all layout combinations

## [0.1.98]
* **NEW**: Added `selectedItemColor` and `unselectedItemColor` support for AdaptiveBottomNavigationBar
  * iOS 26+: Icon colors via renderingMode (`.alwaysOriginal` for unselected, `.alwaysTemplate` for selected)
  * iOS <26 & Android: Native color properties
  * Customizable tab bar item colors for better UI flexibility
* **NEW**: Added `useSmoothRectangleBorder` parameter to AdaptiveButton (iOS 26+)
  * Default `true`: Smooth rectangle corners
  * Set to `false`: Perfect circular/capsule shape for icon buttons
* **BREAKING**: Split AdaptiveAlertDialog methods for different use cases
  * `show()` - Standard dialog (returns void)
  * `inputShow()` - Text input dialog (returns String?)
  * Cancel button now correctly returns null for input dialogs
* **FIX**: Fixed dynamic label updates not working in AdaptivePopupMenuItem
  * Labels now properly update when state changes
* **FIX**: Fixed dark mode not updating in AdaptiveDatePicker and AdaptiveTimePicker
  * Pickers now respond to theme changes dynamically
## [0.1.97]
* **NEW**: Added `spacerAfter` parameter (ToolbarSpacerType) to AdaptiveAppBarAction for iOS 26+ Liquid Glass toolbar grouping
  * `ToolbarSpacerType.fixed` - 12pt fixed space using UIBarButtonItem.fixedSpace() for spacing within groups
  * `ToolbarSpacerType.flexible` - Flexible space using UIBarButtonItem.flexibleSpace() for left/right group separation
  * `ToolbarSpacerType.none` - No spacer (default)
  * Follows iOS 26+ Liquid Glass design guidelines per Apple HIG
  * Example: `AdaptiveAppBarAction(iosSymbol: 'arrow.uturn.forward', onPressed: () {}, spacerAfter: ToolbarSpacerType.flexible)`


## [0.1.96]
* **FIX**: Added automatic localization support for AdaptiveDatePicker, AdaptiveTimePicker, and popup menu buttons
  * Platform-specific localizations: CupertinoLocalizations for iOS, MaterialLocalizations for Android
  * Supports 70+ languages automatically based on system locale
* **FIX**: Increased default height of AdaptiveSegmentedControl from 32 to 36 pixels to prevent overflow on iOS <26
  * Resolves RenderConstraintsTransformBox overflow issue with CupertinoSlidingSegmentedControl
* **FIX**: Fixed tab bar minimizing during pull-to-refresh bounce animation
  * Tab bar now ignores scroll events when content is overscrolling (pixels outside minScrollExtent/maxScrollExtent)
  * Prevents unwanted tab bar animation during iOS elastic scroll bounce

## [0.1.95]
* **NEW**: Added `AdaptiveTabBarView` widget - Platform-specific swipeable tab bar view with color customization
* **NEW**: Added `AdaptiveFloatingActionButton` widget - Platform-specific FAB with custom colors, mini size, hero transitions
* **NEW**: Added `AdaptiveFormSection` widget - Platform-specific form sections (iOS: CupertinoFormSection, Android: Card)
  * Two constructors: default and insetGrouped
  * Works with CupertinoFormRow and adaptive components
* **NEW**: Added `AdaptiveExpansionTile` widget - Modern expandable/collapsible content
  * iOS: Custom design with rounded corners, smooth shadows, animated chevron, gradient separator, modern child items with tap feedback
  * Android: Material ExpansionTile with InkWell effects
  * Full customization support (colors, padding, callbacks, alignment)
* **BREAKING CHANGE**: Renamed `AdaptiveAppBarAction.androidIcon` to `icon`
  * `iosSymbol` for iOS 26+ only, `icon` for iOS <26 and Android
  * Migration: Replace `androidIcon:` with `icon:`
* **IMPROVEMENT**: Updated `AdaptiveSegmentedControl` for iOS <26 to use CupertinoSlidingSegmentedControl
* Added comprehensive tests and demo pages for all new widgets

## [0.1.94+1]
* fix: improve pub.dev score and CI compatibility

## [0.1.94]
* **NEW**: Added `AdaptiveTextField` for platform-specific text input
  * iOS: Uses `CupertinoTextField` with tertiarySystemBackground color and rounded corners
  * Android: Uses Material `TextField` with outlined border
  * Supports all standard text field parameters: placeholder, keyboard type, obscure text, max length, etc.
  * Supports prefix and suffix icons on both platforms
  * Automatic platform-specific styling and behavior
* **NEW**: Added `AdaptiveTextFormField` for form validation support
  * iOS: Uses custom `FormField` wrapper with `CupertinoTextField` for proper validation
  * Android: Uses Material `TextFormField`
  * Full form validation support with validator, onSaved, and autovalidateMode
  * Displays error messages with red border on iOS, standard Material error styling on Android
  * Supports prefix and suffix icons with proper validation state handling
* **FIX**: Fixed prefix/suffix icon support in text fields
  * Icons now display correctly on both iOS and Android
  * iOS icons wrapped in proper padding for consistent spacing
  * Added GestureDetector to prevent focus when tapping icons
* **FIX**: Fixed iOS26 button icon tap area issue
  * Child widgets in `IOS26Button.child` now wrapped with `IgnorePointer`
  * Icon buttons now respond to taps anywhere on the icon, not just the edges
  * Resolves issue where `AdaptiveButton.icon` had limited tap area
* **IMPROVEMENT**: Added `iconColor` parameter to `AdaptiveButton.icon`
  * Separate color control for icon buttons
  * `textColor` remains for label buttons, `iconColor` for icon buttons
  * Consistent API across all button constructors
* Added comprehensive demo page showcasing all text field features
*
* @amolon615, thanks for the changes below.
* Updated documentation with text field examples
* * **NEW**: Added badge counter support to `AdaptiveNavigationDestination`
  * Added `badgeCount` parameter to `AdaptiveNavigationDestination` class
  * iOS 26+: Uses native `UITabBarItem.badgeValue` for native badge display
  * iOS <26 and Android: Uses `AdaptiveBadge` widget for cross-platform badge display
  * Supports dynamic badge updates and proper badge clearing
  * Badge counts > 99 display as "99+" following iOS conventions
  * Added comprehensive demo page showcasing badge navigation functionality


## [0.1.93]
* **NEW**: Added `AdaptiveDatePicker` for platform-specific date selection
  * iOS: Uses `CupertinoDatePicker` in a modal bottom sheet with Cancel/Done buttons
  * Android: Uses Material `DatePickerDialog`
  * Supports date, dateTime, and time modes
  * Configurable date range with firstDate and lastDate parameters
  * Returns `Future<DateTime?>` with selected date or null if cancelled
* **NEW**: Added `AdaptiveTimePicker` for platform-specific time selection
  * iOS: Uses `CupertinoDatePicker` in time mode in a modal bottom sheet
  * Android: Uses Material `TimePickerDialog`
  * Supports both 12-hour and 24-hour formats
  * Returns `Future<TimeOfDay?>` with selected time or null if cancelled
* **NEW**: Added `AdaptiveListTile` for platform-specific list item tiles
  * iOS: Uses CupertinoListTile-like styling with bottom border separator
  * Android: Uses Material `ListTile`
  * Supports leading, title, subtitle, and trailing widgets
  * Includes onTap and onLongPress callbacks
  * Supports selected state and disabled state
  * Customizable backgroundColor and padding
* Updated README with comprehensive examples for new widgets
* Updated widget catalog to include all new widgets

## [0.1.92]
* AdaptiveSegmentedControl now renders icons directly based on platform.
* Maintained existing height, padding, and shrinkWrap behavior.

## [0.1.91]
* Enhance AdaptivePopupMenuButton to support dynamic icon types for iOS and Android

## [0.1.9]
* **NEW**: Added text input support to `AdaptiveAlertDialog`
  * Added `AdaptiveAlertDialogInput` class for input configuration
  * iOS 26+: Native UITextField with native keyboard types
  * iOS <26: CupertinoTextField with scrollable content
  * Android: Material TextField
  * Returns `Future<String?>` with user input
  * Supports placeholder, initial value, keyboard type, obscure text, and max length
* **NEW**: Added `AdaptiveContextMenu` widget for long-press context menus
  * iOS: Uses `CupertinoContextMenu.builder` with native animations
  * Android: Uses `PopupMenuButton` with Material Design styling
  * Supports icons, destructive actions, and disabled states
  * Long press to show, tap to select action
* **IMPROVEMENT**: Changed `AdaptiveAlertDialog` icon parameter to dynamic type
  * iOS 26+: Accepts SF Symbol strings (e.g., "checkmark.circle.fill")
  * iOS <26 and Android: Accepts IconData
  * Automatically handles platform-specific icon rendering

## [0.1.8]
* **NEW**: Added `AdaptiveBottomNavigationBar` class for cleaner bottom navigation configuration
  * Centralized bottom navigation configuration with `bottomNavigationBar` parameter in `AdaptiveScaffold`
  * Replaces individual `destinations`, `selectedIndex`, `onDestinationSelected` parameters
  * If `bottomNavigationBar` is null, no bottom navigation will be shown
* **NEW**: Added custom bottom navigation bar support via `AdaptiveBottomNavigationBar`
  * `items` parameter: Navigation items (renamed from `destinations`)
  * `selectedIndex` parameter: Currently selected item index
  * `onTap` parameter: Callback when item is tapped (renamed from `onDestinationSelected`)
  * `useNativeBottomBar` parameter: Control iOS 26+ native bottom bar (default: `true`)
  * `cupertinoTabBar` parameter: Provide custom `CupertinoTabBar` for iOS
  * `bottomNavigationBar` parameter: Provide custom `NavigationBar` or `BottomNavigationBar` for Android
* **IMPORTANT**: `useNativeBottomBar` priority behavior on iOS
  * iOS 26+ with `useNativeBottomBar: true`: Native UITabBar with Liquid Glass effect is shown, custom `cupertinoTabBar` is ignored
  * iOS 26+ with `useNativeBottomBar: false`: Custom `cupertinoTabBar` is used if provided, otherwise auto-generated from items
  * iOS <26: Custom `cupertinoTabBar` is used if provided, otherwise auto-generated from items (useNativeBottomBar is ignored)
* **FIX**: Fixed icon type handling in bottom navigation
  * SF Symbol strings (e.g., "house.fill") are now properly converted to IconData for CupertinoTabBar
  * Android NavigationBar handles both IconData and SF Symbol strings with appropriate fallbacks
* **BREAKING CHANGE**: `AdaptiveScaffold` bottom navigation parameters refactored
  * Removed: Direct `destinations`, `selectedIndex`, `onDestinationSelected` parameters
  * Added: Single `bottomNavigationBar` parameter of type `AdaptiveBottomNavigationBar?`
  * Migration: Wrap existing parameters in `AdaptiveBottomNavigationBar()`
  ```dart
  // Before
  AdaptiveScaffold(
    destinations: [...],
    selectedIndex: 0,
    onDestinationSelected: (index) {},
  )

  // After
  AdaptiveScaffold(
    bottomNavigationBar: AdaptiveBottomNavigationBar(
      items: [...],
      selectedIndex: 0,
      onTap: (index) {},
    ),
  )
  ```

## [0.1.7+1]
  * Updated README.md

## [0.1.7]
* **NEW**: Added `AdaptiveAppBar` class for cleaner app bar configuration
  * Centralized app bar configuration with `appBar` parameter in `AdaptiveScaffold`
  * Replaces individual `title`, `actions`, `leading`, `useNativeToolbar` parameters
  * If `appBar` is null, no app bar or toolbar will be shown
* **NEW**: Added custom navigation bar support via `AdaptiveAppBar`
  * `cupertinoNavigationBar` parameter: Provide custom `CupertinoNavigationBar` for iOS
  * `appBar` parameter: Provide custom `AppBar` for Android
  * Custom navigation bars take priority over auto-generated ones
* **IMPORTANT**: `useNativeToolbar` priority behavior on iOS
  * When `useNativeToolbar: true`: Native iOS 26 toolbar is shown, custom `cupertinoNavigationBar` is ignored
  * When `useNativeToolbar: false` or not set: Custom `cupertinoNavigationBar` is used if provided
* **BREAKING CHANGE**: `AdaptiveScaffold` parameters refactored
  * Removed: Direct `title`, `actions`, `leading`, `useNativeToolbar` parameters
  * Added: Single `appBar` parameter of type `AdaptiveAppBar?`
  * Migration: Wrap existing parameters in `AdaptiveAppBar()`
  ```dart
  // Before
  AdaptiveScaffold(
    title: 'My App',
    actions: [...],
    useNativeToolbar: true,
  )

  // After
  AdaptiveScaffold(
    appBar: AdaptiveAppBar(
      title: 'My App',
      actions: [...],
      useNativeToolbar: true,
    ),
  )
  ```

## [0.1.6]
* **NEW**: Added `AdaptivePopupMenuButton.widget()` constructor for custom widget support
  * iOS <26: GestureDetector with CupertinoActionSheet fallback
  * Android: Material PopupMenuButton with custom child
  * Added demo examples: Custom Button, Card Style, and Chip Style

## [0.1.5+2]
  * Updated README.md

## [0.1.5+1]
  * Updated README.md

## [0.1.5]

* **NEW**: Added `AdaptiveSnackBar` widget for platform-specific notifications
  * iOS: Banner-style notification at the top with slide/fade animations
    - Tap to dismiss
    - Icon indicators for different types
    - Action button support with blur effect
    - Automatic dismissal
  * Android: Material SnackBar at the bottom
    - Standard Material Design appearance
    - Action button support
  * Supports 4 types: info, success, warning, error
  * Customizable duration and action callbacks
* **BREAKING CHANGE**: iOS 26 Native Toolbar is now optional due to stability issues with GoRouter and other router packages
  * Native toolbar can still be enabled via `useNativeToolbar: true` parameter in `AdaptiveScaffold`
  * Default behavior now uses `CupertinoNavigationBar` for better compatibility
  * iOS 26+ users will get custom animated back button when `useNativeToolbar: false`
  * Resolves touch callback issues and navigation conflicts with router-based navigation
* **IMPROVEMENT**: Added automatic back button with fade animation for iOS 26+ when using `useNativeToolbar: false`
  * Appears automatically when page can pop
  * Prevents native back button conflicts during transitions
  * Smooth fade-out animation on tap
* **FIX**: Fixed icon handling in bottom navigation - icons now properly support both SF Symbol strings and IconData
* Updated demo app with comprehensive snackbar examples

## [0.1.4+1]
  * Updated README.md

## [0.1.4]

* **NEW**: Added `AdaptiveCard` widget for platform-specific card styling
  * iOS: Custom iOS-style card with Cupertino design (border, subtle shadow, rounded corners)
  * Android: Material Design Card with elevation support
  * Support for custom colors, border radius, padding, margin, and clip behavior
* **NEW**: Added `AdaptiveRadio` widget for radio button groups
  * iOS: Custom iOS-style radio with circular design
  * Android: Material Design Radio
  * Support for custom colors, toggleable mode, and disabled state
* **NEW**: Added `AdaptiveBadge` widget for notification badges
  * iOS: Custom iOS-style badge with rounded design
  * Android: Material Design Badge
  * Support for count/label display, custom colors, show zero option, and large size
* **NEW**: Added `AdaptiveTooltip` widget for platform-specific tooltips
  * iOS: Custom iOS-style tooltip with animation and theme support
  * Android: Material Design Tooltip
  * Long press/tap to show, auto-hide after duration
* **NEW**: Added `AdaptiveCheckbox` widget (Cupertino & Material only)
  * iOS: Custom iOS-style checkbox with Cupertino design
  * Android: Material Design Checkbox
  * Support for tristate, custom colors, and dark/light mode
* **EXPERIMENTAL**: Added `IOS26NativeSearchTabBar` for iOS 26+ native search tab bar
  * App-level UITabBarController integration replacing Flutter's navigation
  * Native search tab transformation with UISearchController
  * Liquid Glass effects and native animations
  * Method channel for Flutter ↔ Native communication
  * Search query callbacks and tab selection handling
  * ⚠️ **WARNING**: This feature is highly experimental and unstable:
    - Replaces Flutter's root view controller
    - Breaks widget lifecycle and state management
    - Hot reload may not work properly
    - Navigation stack becomes invalid
    - Only recommended for prototyping and demos
  * See demo page for detailed technical explanation of architectural conflicts
* Added comprehensive demo pages for all new widgets

## [0.1.3]

* **BREAKING CHANGE**: Renamed `AdaptiveScaffold.child` parameter to `body` to match standard Scaffold API
* **NEW**: Added `AdaptiveApp` widget for automatic platform-specific app configuration
  * `AdaptiveApp()` - Constructor for normal navigation
  * `AdaptiveApp.router()` - Constructor for router-based navigation (GoRouter, etc.)
  * Direct theme parameters: `themeMode`, `materialLightTheme`, `materialDarkTheme`, `cupertinoLightTheme`, `cupertinoDarkTheme`
  * Platform-specific callbacks: `material()` and `cupertino()` for advanced configuration
  * Automatic platform detection (iOS uses CupertinoApp, Android uses MaterialApp)
  * Full support for all MaterialApp and CupertinoApp properties
* Debug banner now hidden by default (`debugShowCheckedModeBanner: false`)
* Updated all example code to use new `body` parameter

## [0.1.2]

* Fix image links in README.md to use GitHub raw URLs
* Images now display correctly on pub.dev

## [0.1.1]

* Documentation improvements
* Added comprehensive README with images for all widgets
* Added visual showcase for toolbar, tab bar, buttons, segmented controls, switches, sliders, alerts, and popup menus
* Improved code examples and usage documentation

## [0.1.0]

* Initial release with iOS 26+ support
* Features:
  * `AdaptiveScaffold` - Platform-adaptive scaffold with native iOS 26 toolbar and tab bar
  * `AdaptiveButton` - Adaptive buttons with iOS 26 Liquid Glass design
  * `AdaptiveSegmentedControl` - Native segmented controls for all platforms
  * `AdaptiveSwitch` - Platform-adaptive switches
  * `AdaptiveSlider` - Platform-adaptive sliders
  * `AdaptiveAlertDialog` - Native alert dialogs
  * `AdaptivePopupMenuButton` - Platform-adaptive popup menus
* iOS 26+ features:
  * Native UIToolbar with Liquid Glass blur effects
  * Native UITabBar with minimize behavior
  * Native UISegmentedControl
  * Native SF Symbol support
  * Haptic feedback
  * Automatic light/dark mode adaptation
* Platform support:
  * iOS 26+ with native Liquid Glass designs
  * iOS <26 (iOS 18 and below) with traditional Cupertino widgets
  * Android with Material Design 3
