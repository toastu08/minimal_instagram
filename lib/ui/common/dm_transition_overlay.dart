// The visual half of the inbox <-> conversation slide.
//
// The WebView is a native Android platform view. Wrapping it in a Flutter
// transform (the first attempt) forced the view to be re-created, which reset
// it to the inbox before the thread's `pushState` ever became a navigation. So
// the motion is drawn as a Flutter-only curtain that sits *on top of* the
// WebView as a sibling in the Stack — never an ancestor. It never moves the
// platform view, never decides navigation and never blocks input.

import 'package:flutter/material.dart';

import '../../navigation/dm_transition.dart';

/// An opaque, pointer-transparent curtain that sweeps across the screen to mask
/// the WebView's otherwise instant inbox <-> thread swap.
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

  /// Which way the curtain travels. [DmTransition.none] renders nothing.
  final DmTransition direction;

  /// Where the curtain sits for a given [progress] (0..1).
  ///
  /// Forward sweeps right -> left (the content appears to arrive from the
  /// right); back sweeps left -> right. Exposed so the geometry is testable.
  static Offset curtainOffset(DmTransition direction, double progress) {
    final double eased = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final double x = direction == DmTransition.forward
        ? 1 - 2 * eased
        : -1 + 2 * eased;
    return Offset(x, 0);
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (listenable as Animation<double>).value;
    return Positioned.fill(
      child: IgnorePointer(
        child: direction == DmTransition.none
            ? const SizedBox.shrink()
            : FractionalTranslation(
                translation: curtainOffset(direction, progress),
                child: ColoredBox(color: Theme.of(context).colorScheme.surface),
              ),
      ),
    );
  }
}
