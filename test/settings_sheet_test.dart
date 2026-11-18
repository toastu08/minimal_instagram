// Widget tests for the settings sheet.
//
// The destructive action is the point of these tests: clearing the session must
// never happen on a single tap, and cancelling must call nothing. The sheet is
// tested on its own (no WebView, no platform channel) because the deletion
// itself belongs to the browser screen, which M7 covers on-device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/ui/settings/settings_sheet.dart';

void main() {
  Future<void> openSheet(WidgetTester tester, VoidCallback onClear) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (BuildContext context) =>
                      SettingsSheet(onClearSession: () async => onClear()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the available settings and the disclaimer', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, () {});

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Clear session'), findsOneWidget);
    expect(find.textContaining('unofficial'), findsOneWidget);
  });

  testWidgets('clearing asks for confirmation and can be cancelled', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await openSheet(tester, () => calls++);

    await tester.tap(find.text('Clear session'));
    await tester.pumpAndSettle();

    expect(find.text('Clear session?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0, reason: 'cancelling must not delete anything');
    expect(find.text('Clear session'), findsOneWidget, reason: 'sheet stays');
  });

  testWidgets('confirming calls the callback once and closes the sheet', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await openSheet(tester, () => calls++);

    await tester.tap(find.text('Clear session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Settings'), findsNothing);
  });
}
