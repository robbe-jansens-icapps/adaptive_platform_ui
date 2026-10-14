import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('on iPhone Duo the tabs of a page with its own bottom bar and a native toolbar are in the vertical bar', (tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(debugFold: duo(), child: child!),
        home: ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, value, _) => AdaptiveScaffold(
            appBar: const AdaptiveAppBar(title: 'Tabs', useNativeToolbar: true),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              useNativeBottomBar: false,
              selectedIndex: value,
              onTap: (i) => index.value = i,
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(icon: Icons.info, label: 'Info'),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(HostedDuoBar);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.home)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.info)), findsOneWidget);
  });

  testWidgets('a tab page without a toolbar draws no bottom bar of its own beside them', (tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(debugFold: duo(), child: child!),
        home: AdaptiveScaffold(
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            useNativeBottomBar: false,
            selectedIndex: 0,
            onTap: (_) {},
            items: const [
              AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
              AdaptiveNavigationDestination(icon: Icons.info, label: 'Info'),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(HostedDuoBar), matching: find.byIcon(Icons.home)), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
  });
}
