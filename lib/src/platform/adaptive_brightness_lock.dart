import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Holds the app, or the part of it below, in one [brightness] whatever the
/// device's: for an app without a design for the other one.
///
/// The pages below get [brightness] as their platform brightness, which the
/// native views of this package follow. On iOS the app's windows are held in
/// it as well, so that what UIKit draws on its own (menus, alerts, pickers,
/// glyphs measured off screen) matches the pages, instead of turning dark on
/// a device in dark mode under a light app. A lock taken out of the tree lets
/// the app follow the device again, unless another one is still mounted: the
/// one mounted last holds the windows.
class AdaptiveBrightnessLock extends StatefulWidget {
  const AdaptiveBrightnessLock({
    super.key,
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  State<AdaptiveBrightnessLock> createState() => _AdaptiveBrightnessLockState();
}

class _AdaptiveBrightnessLockState extends State<AdaptiveBrightnessLock> {
  static const _channel = MethodChannel('adaptive_platform_ui/device');

  /// The locks mounted now, oldest first.
  static final List<_AdaptiveBrightnessLockState> _mounted =
      <_AdaptiveBrightnessLockState>[];

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
    _holdWindows();
  }

  @override
  void didUpdateWidget(AdaptiveBrightnessLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness != widget.brightness) _holdWindows();
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _holdWindows();
    super.dispose();
  }

  /// Holds the windows in the brightness of the lock mounted last, or lets
  /// them follow the device without one.
  static void _holdWindows() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel
        .invokeMethod<void>('lockAppearance', <String, Object?>{
          'style': _mounted.lastOrNull?.widget.brightness.name,
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(platformBrightness: widget.brightness),
      child: widget.child,
    );
  }
}
