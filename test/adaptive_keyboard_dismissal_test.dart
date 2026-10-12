import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pressed = <String>[];

  setUp(pressed.clear);

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveKeyboardDismissal(child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              Row(
                children: [
                  const Expanded(child: TextField()),
                  // Part of the field, as a field's own icons are.
                  TextFieldTapRegion(
                    child: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => pressed.add('clear'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => pressed.add('send'),
                child: const Text('Send'),
              ),
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> focusField(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
  }

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('a tap anywhere but on a text field closes the keyboard', (
    tester,
  ) async {
    await pumpPage(tester);
    await focusField(tester);

    await tester.tap(find.text('row 3'));
    await tester.pump();

    expect(fieldHasFocus(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('scrolling leaves the keyboard up', (tester) async {
    await pumpPage(tester);
    await focusField(tester);

    // Not so far that the field scrolls out of the list.
    await tester.drag(find.text('row 3'), const Offset(0, -40));
    await tester.pumpAndSettle();
    await tester.drag(find.text('row 3'), const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(fieldHasFocus(tester), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a tap on the field or on what belongs to it leaves it up', (
    tester,
  ) async {
    await pumpPage(tester);
    await focusField(tester);

    await tester.tap(find.byType(TextField));
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(pressed, ['clear']);
    expect(fieldHasFocus(tester), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a tap on a button closes the keyboard and presses the button', (
    tester,
  ) async {
    await pumpPage(tester);
    await focusField(tester);

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(pressed, ['send']);
    expect(fieldHasFocus(tester), isFalse);
  });

  testWidgets('closes a keyboard that no text field holds any more', (
    tester,
  ) async {
    await pumpPage(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    tester.testTextInput.log.clear();

    await tester.tap(find.text('row 3'));
    await tester.pump();

    expect(
      tester.testTextInput.log.map((call) => call.method),
      contains('TextInput.hide'),
    );
  });

  testWidgets('leaves the system alone while there is no keyboard', (
    tester,
  ) async {
    await pumpPage(tester);
    tester.testTextInput.log.clear();

    await tester.tap(find.text('row 3'));
    await tester.pump();

    expect(tester.testTextInput.log, isEmpty);
  });

  testWidgets('dismiss closes the keyboard of the field focused now', (
    tester,
  ) async {
    await pumpPage(tester);
    await focusField(tester);

    AdaptiveKeyboardDismissal.dismiss();
    await tester.pump();

    expect(fieldHasFocus(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
