// The visual half of the inbox <-> conversation slide.
//
// The WebView is a native Android platform view. Wrapping it in a Flutter
// transform (the first attempt) forced the view to be re-created, which reset
// it to the inbox before the thread's `pushState` ever became a navigation. So
// the motion is drawn as Flutter-only content that sits *on top of* the WebView
// as a sibling in the Stack — never an ancestor. It never moves the platform
// view, never decides navigation and never blocks input.
//
// Entering a conversation (forward) slides in the conversation skeleton from the
// right; leaving it (back) slides in the inbox skeleton from the left. Both hold
// a beat and fade out, masking the WebView's otherwise instant swap.

import 'package:flutter/material.dart';

import '../../navigation/dm_transition.dart';
import 'loading_skeleton.dart';

/// A pointer-transparent overlay that masks the WebView's instant inbox <->
/// thread swap.
///
/// Driven by an [Animation] and a [DmTransition] direction. When idle it renders
/// nothing; it is always wrapped in an [IgnorePointer] so taps pass through.
class DmTransitionOverlay extends AnimatedWidget {
  /// Creates the overlay, listening to [animation].
  const DmTransitionOverlay({
    super.key,
    required Animation<double> animation,
    required this.direction,
  }) : super(listenable: animation);

  /// Which way the surface is travelling. [DmTransition.none] renders nothing.
  final DmTransition direction;

  /// Key on the overlay's [IgnorePointer], so tests can assert pointer
  /// transparency without tripping over the WebView or scrollable's own
  /// `IgnorePointer`s further up the tree.
  static const Key ignorePointerKey = ValueKey<String>(
    'DmTransitionOverlay.ignorePointer',
  );

  /// Fraction of the total timeline spent sliding in, for [skeletonSlideX] and
  /// [skeletonOpacity]. The first forward of a session is 750 ms, so 0.32 is
  /// ~240 ms; faster runs shrink everything proportionally.
  static const double _slideInEnd = 0.32;
  static const double _holdEnd = 0.75;

  /// Horizontal slide of the skeleton, in fractions of the width.
  ///
  /// Forward arrives from the right (1 -> 0); back arrives from the left
  /// (-1 -> 0). Both ease to 0 by [_slideInEnd] and hold there through the fade.
  /// Exposed so the geometry is testable.
  static double skeletonSlideX(DmTransition direction, double progress) {
    final double p = progress.clamp(0.0, 1.0);
    if (p >= _slideInEnd) return 0;
    final double t = Curves.easeOutCubic.transform(p / _slideInEnd);
    final double amount = 1 - t;
    return direction == DmTransition.forward ? amount : -amount;
  }

  /// Opacity of the skeleton, in fractions.
  ///
  /// 1 through the slide-in and hold, easing to 0 by the end of the timeline.
  /// Exposed so the geometry is testable.
  static double skeletonOpacity(double progress) {
    final double p = progress.clamp(0.0, 1.0);
    if (p <= _holdEnd) return 1;
    final double t = (p - _holdEnd) / (1 - _holdEnd);
    return 1 - Curves.easeIn.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (listenable as Animation<double>).value;
    return Positioned.fill(
      child: IgnorePointer(
        key: ignorePointerKey,
        child: direction == DmTransition.none
            ? const SizedBox.shrink()
            : FractionalTranslation(
                translation: Offset(skeletonSlideX(direction, progress), 0),
                child: Opacity(
                  opacity: skeletonOpacity(progress),
                  child: direction == DmTransition.forward
                      ? const ConversationSkeleton()
                      : const InboxSkeleton(),
                ),
              ),
      ),
    );
  }
}
