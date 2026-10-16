import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final field = FocusNode();

  Future<void> pump(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              TextField(focusNode: field),
              const AdaptiveKeyboardFade(child: Text('tabs')),
            ],
          ),
        ),
      ),
    );
  }

  double opacity(WidgetTester tester) => tester.widget<FadeTransition>(find.ancestor(of: find.text('tabs'), matching: find.byType(FadeTransition)).first).opacity.value;

  bool ignoring(WidgetTester tester) => tester.widget<IgnorePointer>(find.ancestor(of: find.text('tabs'), matching: find.byType(IgnorePointer)).first).ignoring;

  testWidgets('comes back as soon as the text field the keyboard came up for lets go of the focus', (tester) async {
    await pump(tester);
    field.requestFocus();
    await tester.pump();
    expect(opacity(tester), 1, reason: 'a hardware keyboard takes no room and hides nothing');

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(ignoring(tester), isTrue);

    field.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(AdaptiveKeyboardFade.fadeInDuration ~/ 2);
    expect(opacity(tester), inExclusiveRange(0, 1));
    expect(ignoring(tester), isFalse);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1, reason: 'the keyboard on its way down does not hide it again');

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
  });

  testWidgets('a keyboard no text field here brought up, as a web view\'s, hides it until it goes down', (tester) async {
    await pump(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);

    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    tester.view.viewInsets = const FakeViewPadding(bottom: 100);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
  });

  testWidgets('does nothing while not enabled', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: AdaptiveKeyboardFade(enabled: false, child: Text('tabs'))));
    expect(opacity(tester), 1);
  });
}
