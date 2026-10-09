import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What a fixed iOS 26 bar has behind it: nothing while [visible] is false,
/// and the system's own scroll edge effect while it is true.
///
/// Like the system bars, the bar itself has no background: show this while
/// content is scrolled underneath it. UIKit draws the effect for its own
/// scroll views; this lets it draw it for Flutter content, and since the
/// effect is UIKit's, it also covers native views underneath. It animates in
/// and out by itself; never wrap it in a fade or a clip. It never takes
/// touches.
///
/// Where there is no UIKit (other platforms, widget tests) it draws nothing.
class IOS26BarBackdrop extends StatefulWidget {
  const IOS26BarBackdrop({super.key, required this.visible, this.fade = 16});

  final bool visible;

  /// How far below the bar the effect may soften out, at the bottom of this
  /// widget.
  final double fade;

  @override
  State<IOS26BarBackdrop> createState() => _IOS26BarBackdropState();
}

class _IOS26BarBackdropState extends State<IOS26BarBackdrop> {
  MethodChannel? _channel;
  Map<String, Object>? _sent;

  static bool get _hasUIKit => !kIsWeb && Platform.isIOS;

  Map<String, Object> get _params => <String, Object>{
    'isDark': MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark,
    'visible': widget.visible,
    'fade': widget.fade,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IOS26BarBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _onCreated(int id) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_bar_backdrop_$id');
    _sync();
  }

  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    final params = _params;
    if (mapEquals(params, _sent)) return;
    _sent = params;
    channel.invokeMethod<void>('update', params);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUIKit) return const SizedBox.expand();
    return IgnorePointer(
      child: UiKitView(
        viewType: 'adaptive_platform_ui/ios26_bar_backdrop',
        // What the view is created with; later changes go through `update`.
        creationParams: _sent ??= _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
      ),
    );
  }
}
