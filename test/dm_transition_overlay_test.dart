// Tests for the inbox <-> conversation transition overlay.
//
// The overlay is Flutter-only and sits on top of the WebView, so it is tested in
// isolation. The geometry lives in pure static helpers, asserted directly; the
// widget tests confirm the idle state renders nothing, forward shows the
// conversation skeleton, back shows the inbox skeleton, and everything is
// pointer-transparent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/navigation/dm_transition.dart';
import 'package:minimal_instagram/ui/common/dm_transition_overlay.dart';
import 'package:minimal_instagram/ui/common/loading_skeleton.dart';

void main() {
  test('forward skeleton slides in from the right and settles', () {
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 0), 1);
    // Mid-slide is strictly between the edges.
    expect(
      DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 0.16),
      greaterThan(0),
    );
    expect(
      DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 0.16),
      lessThan(1),
    );
    // Settles to 0 at the end of the slide-in and holds through the fade.
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 0.32), 0);
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 0.5), 0);
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.forward, 1), 0);
  });

  test('back skeleton slides in from the left and settles', () {
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.back, 0), -1);
    expect(
      DmTransitionOverlay.skeletonSlideX(DmTransition.back, 0.16),
      lessThan(0),
    );
    expect(
      DmTransitionOverlay.skeletonSlideX(DmTransition.back, 0.16),
      greaterThan(-1),
    );
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.back, 0.32), 0);
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.back, 0.5), 0);
    expect(DmTransitionOverlay.skeletonSlideX(DmTransition.back, 1), 0);
  });

  test('skeleton holds fully opaque then fades out', () {
    expect(DmTransitionOverlay.skeletonOpacity(0), 1);
    expect(DmTransitionOverlay.skeletonOpacity(0.5), 1);
    expect(DmTransitionOverlay.skeletonOpacity(0.75), 1);
    // Mid-fade is strictly between opaque and transparent.
    expect(DmTransitionOverlay.skeletonOpacity(0.875), greaterThan(0));
    expect(DmTransitionOverlay.skeletonOpacity(0.875), lessThan(1));
    expect(DmTransitionOverlay.skeletonOpacity(1), closeTo(0, 1e-9));
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

  testWidgets('idle renders nothing and does not obscure the page', (
    WidgetTester tester,
  ) async {
    await pumpOverlay(tester, direction: DmTransition.none, value: 1);

    expect(find.text('page'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DmTransitionOverlay),
        matching: find.byType(FractionalTranslation),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'forward shows the conversation skeleton and is pointer-transparent',
    (WidgetTester tester) async {
      await pumpOverlay(tester, direction: DmTransition.forward, value: 0.5);

      expect(find.byType(ConversationSkeleton), findsOneWidget);
      expect(find.byType(InboxSkeleton), findsNothing);
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(DmTransitionOverlay.ignorePointerKey),
            )
            .ignoring,
        isTrue,
      );

      // Unmount so the skeleton's repeating shimmer controller is disposed before
      // the test framework checks for stray tickers.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('back shows the inbox skeleton and is pointer-transparent', (
    WidgetTester tester,
  ) async {
    await pumpOverlay(tester, direction: DmTransition.back, value: 0.5);

    expect(find.byType(InboxSkeleton), findsOneWidget);
    expect(find.byType(ConversationSkeleton), findsNothing);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(DmTransitionOverlay.ignorePointerKey),
          )
          .ignoring,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
