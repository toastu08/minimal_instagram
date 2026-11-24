// Tests for the inbox <-> conversation slide curtain.
//
// The curtain is Flutter-only and sits on top of the WebView, so it is tested in
// isolation. The geometry lives in a pure static helper, which is asserted
// directly; the widget test confirms that the idle state renders nothing and the
// active state is pointer-transparent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/navigation/dm_transition.dart';
import 'package:minimal_instagram/ui/common/dm_transition_overlay.dart';

void main() {
  test('forward sweeps right-to-left', () {
    expect(DmTransitionOverlay.curtainOffset(DmTransition.forward, 0).dx, 1);
    expect(
      DmTransitionOverlay.curtainOffset(DmTransition.forward, 0.5).dx,
      closeTo(0, 1e-9),
    );
    expect(
      DmTransitionOverlay.curtainOffset(DmTransition.forward, 1).dx,
      closeTo(-1, 1e-9),
    );
  });

  test('back sweeps left-to-right', () {
    expect(DmTransitionOverlay.curtainOffset(DmTransition.back, 0).dx, -1);
    expect(
      DmTransitionOverlay.curtainOffset(DmTransition.back, 0.5).dx,
      closeTo(0, 1e-9),
    );
    expect(
      DmTransitionOverlay.curtainOffset(DmTransition.back, 1).dx,
      closeTo(1, 1e-9),
    );
  });

  Future<void> pumpOverlay(
    WidgetTester tester, {
    required DmTransition direction,
    required double value,
  }) {
    final AnimationController controller = AnimationController(
      vsync: const TestVSync(),
      value: value,
    );
    addTearDown(controller.dispose);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              const SizedBox.expand(child: Text('page')),
              DmTransitionOverlay(animation: controller, direction: direction),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('idle renders no curtain and does not obscure the page', (
    WidgetTester tester,
  ) async {
    await pumpOverlay(tester, direction: DmTransition.none, value: 1);

    expect(find.text('page'), findsOneWidget);
    // The overlay is a Positioned.fill with an empty child, so no curtain color.
    expect(
      find.descendant(
        of: find.byType(DmTransitionOverlay),
        matching: find.byType(FractionalTranslation),
      ),
      findsNothing,
    );
  });

  testWidgets('active state is pointer-transparent', (
    WidgetTester tester,
  ) async {
    await pumpOverlay(tester, direction: DmTransition.forward, value: 0.5);

    final IgnorePointer ignore = tester.widget(
      find.descendant(
        of: find.byType(DmTransitionOverlay),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignore.ignoring, isTrue);
    expect(
      find.descendant(
        of: find.byType(DmTransitionOverlay),
        matching: find.byType(FractionalTranslation),
      ),
      findsOneWidget,
    );
  });
}
