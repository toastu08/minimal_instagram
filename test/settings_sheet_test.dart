// Widget tests for the settings sheet.
//
// The destructive action is the point of these tests: clearing the session must
// never happen on a single tap, and cancelling must call nothing. The reels
// preference is also checked here. The sheet is tested on its own (no WebView,
// no platform channel) because the deletion itself belongs to the browser
// screen, which is verified on-device.
//
// `shared_preferences` is not involved: the sheet only reports the user's
// choice, the browser screen persists it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/navigation/url_policy.dart';
import 'package:minimal_instagram/ui/settings/settings_sheet.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required ValueNotifier<ReelPolicy> policy,
    ValueChanged<ReelPolicy>? onPolicyChanged,
    VoidCallback? onClear,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (BuildContext context) => SettingsSheet(
                    reelPolicy: policy,
                    onReelPolicyChanged: onPolicyChanged ?? (ReelPolicy _) {},
                    onClearSession: () async => onClear?.call(),
                    version: '9.9.9',
                  ),
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

  testWidgets('shows the settings, the version and the disclaimer', (
    WidgetTester tester,
  ) async {
    await openSheet(
      tester,
      policy: ValueNotifier<ReelPolicy>(ReelPolicy.allow),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Clear session'), findsOneWidget);
    expect(find.text('Minimal Instagram 9.9.9'), findsOneWidget);
    expect(find.textContaining('unofficial'), findsOneWidget);
    expect(find.text('Single reel'), findsOneWidget);
    expect(find.text('Block reels'), findsOneWidget);
  });

  testWidgets('reports a reels preference change', (WidgetTester tester) async {
    final List<ReelPolicy> changes = <ReelPolicy>[];
    await openSheet(
      tester,
      policy: ValueNotifier<ReelPolicy>(ReelPolicy.allow),
      onPolicyChanged: changes.add,
    );

    await tester.tap(find.text('Block reels'));
    await tester.pumpAndSettle();

    expect(changes, <ReelPolicy>[ReelPolicy.block]);
  });

  testWidgets('follows the notifier when the preference changes elsewhere', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<ReelPolicy> policy = ValueNotifier<ReelPolicy>(
      ReelPolicy.allow,
    );
    addTearDown(policy.dispose);
    await openSheet(tester, policy: policy);

    policy.value = ReelPolicy.block;
    await tester.pumpAndSettle();

    final SegmentedButton<ReelPolicy> control = tester.widget(
      find.byType(SegmentedButton<ReelPolicy>),
    );
    expect(control.selected, <ReelPolicy>{ReelPolicy.block});
  });

  testWidgets('clearing asks for confirmation and can be cancelled', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await openSheet(
      tester,
      policy: ValueNotifier<ReelPolicy>(ReelPolicy.allow),
      onClear: () => calls++,
    );

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
    await openSheet(
      tester,
      policy: ValueNotifier<ReelPolicy>(ReelPolicy.allow),
      onClear: () => calls++,
    );

    await tester.tap(find.text('Clear session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Settings'), findsNothing);
  });
}
