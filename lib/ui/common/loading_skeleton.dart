// The "still loading" placeholders drawn over the WebView during a DM move.
//
// Instagram swaps between the inbox and a conversation with `history.pushState`,
// so the new surface appears instantly and a plain hard cut is jarring. The
// motion layer slides one of these skeletons over the WebView for a split second
// and then fades it out, so the change reads as a page that is still loading
// rather than a flash. They are pure decoration: they never decide navigation,
// never read the page and never absorb pointer events (the overlay shell owns
// the IgnorePointer).

import 'package:flutter/material.dart';

/// A dark, non-interactive skeleton of a text conversation.
///
/// Gray rounded rectangles stand in for message bubbles — incoming on the left,
/// outgoing on the right. Rendered inside the shared shimmer frame; see
/// [_SkeletonFrame].
class ConversationSkeleton extends StatelessWidget {
  /// Creates the conversation skeleton.
  const ConversationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SkeletonFrame(
      child: _ConversationPlaceholder(width: MediaQuery.sizeOf(context).width),
    );
  }
}

/// A dark, non-interactive skeleton of the inbox.
///
/// A row of circles on top stands in for the "notes" bubbles, and a list of
/// avatar + name + preview rows stands in for the conversation list.
class InboxSkeleton extends StatelessWidget {
  /// Creates the inbox skeleton.
  const InboxSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SkeletonFrame(
      child: _InboxPlaceholder(width: MediaQuery.sizeOf(context).width),
    );
  }
}

/// The shared dark backdrop and sweeping shimmer highlight.
///
/// Both skeletons wrap their layout in this frame, which owns the repeating
/// shimmer [AnimationController]. Its lifetime matches the widget's: when the
/// overlay removes the skeleton from the tree, the controller is disposed.
class _SkeletonFrame extends StatefulWidget {
  const _SkeletonFrame({required this.child});

  final Widget child;

  @override
  State<_SkeletonFrame> createState() => _SkeletonFrameState();
}

class _SkeletonFrameState extends State<_SkeletonFrame>
    with SingleTickerProviderStateMixin {
  /// Drives the shimmer sweep. Repeats the whole time the skeleton is visible.
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (BuildContext context, Widget? child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (Rect bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const <Color>[_bubble, _highlight, _bubble],
              stops: const <double>[0.35, 0.5, 0.65],
              transform: _SlideGradientTransform(_shimmer.value),
            ).createShader(bounds),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// The conversation layout: a header and a full-screen run of left/right bubbles.
class _ConversationPlaceholder extends StatelessWidget {
  const _ConversationPlaceholder({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        // Nudged a touch right and down so the header sits off the corner.
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: _header(width),
        ),
        const SizedBox(height: 24),
        ..._bubbles(width),
      ],
    );
  }

  static const SizedBox _gap = SizedBox(height: 12);

  Widget _header(double w) {
    return Row(
      children: <Widget>[
        const _Pill(width: 30, height: 30, radius: 15),
        const SizedBox(width: 12),
        _Pill(width: w * 0.34, height: 14, radius: 7),
      ],
    );
  }

  /// The back-and-forth of wide bubbles, repeated until the screen overflows.
  List<Widget> _bubbles(double width) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < 5; i++) {
      children.addAll(<Widget>[
        _bubble(Alignment.centerLeft, width * 0.78, 44),
        _gap,
        _bubble(Alignment.centerLeft, width * 0.56, 44),
        _gap,
        _bubble(Alignment.centerRight, width * 0.70, 44),
        _gap,
        _bubble(Alignment.centerLeft, width * 0.82, 56),
        _gap,
        _bubble(Alignment.centerRight, width * 0.52, 34),
        _gap,
        _bubble(Alignment.centerLeft, width * 0.64, 44),
        _gap,
        _bubble(Alignment.centerRight, width * 0.76, 44),
        _gap,
        _bubble(Alignment.centerLeft, width * 0.56, 34),
        _gap,
      ]);
    }
    return children;
  }

  Widget _bubble(Alignment alignment, double w, double h) {
    return Align(
      alignment: alignment,
      child: _Pill(width: w, height: h, radius: 16),
    );
  }
}

/// The inbox layout: a row of "notes" circles over a list of conversation rows.
class _InboxPlaceholder extends StatelessWidget {
  const _InboxPlaceholder({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      // The top padding pushes the notes circles clear of any device cutout;
      // on some handsets the very top row sat too close to the edge.
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 24),
      children: <Widget>[
        _notesRow(),
        const SizedBox(height: 20),
        ..._rows(width),
      ],
    );
  }

  Widget _notesRow() {
    return Row(
      children: <Widget>[
        for (int i = 0; i < 6; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 14),
          const _Pill(width: 48, height: 48, radius: 24),
        ],
      ],
    );
  }

  /// Conversation rows, generated to overfill the screen (clipped by the list).
  List<Widget> _rows(double width) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < 36; i++) {
      children
        ..add(_row(width, i))
        ..add(const SizedBox(height: 18));
    }
    return children;
  }

  Widget _row(double width, int i) {
    return Row(
      children: <Widget>[
        const _Pill(width: 40, height: 40, radius: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Pill(
              width: width * (0.30 + (i % 3) * 0.05),
              height: 12,
              radius: 6,
            ),
            const SizedBox(height: 6),
            _Pill(
              width: width * (0.48 + (i % 4) * 0.05),
              height: 10,
              radius: 5,
            ),
          ],
        ),
      ],
    );
  }
}

/// A single gray rounded rectangle or circle — a bubble, avatar, note or name bar.
///
/// Its real color is irrelevant under the shimmer (which replaces it), but it
/// is gray so it still reads as a skeleton if the shimmer were ever absent.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _bubble,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Slides a horizontal gradient by a fraction of the surface width.
///
/// A 0..1 value sweeps the highlight band from fully off-screen left to fully
/// off-screen right, so a plain `repeat()` loops seamlessly.
class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform(this.value);

  final double value;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (value * 3 - 1.5), 0, 0);
  }
}

/// The near-black backdrop the shapes sit on (a deliberate loading look, not
/// the app theme, so the reveal clearly reads as "still loading").
const Color _background = Color(0xFF141414);

/// The gray of the shapes.
const Color _bubble = Color(0xFF2E2E30);

/// The lighter band that sweeps across the shapes.
const Color _highlight = Color(0xFF4A4A4E);
