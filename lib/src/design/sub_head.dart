// Sub-screen chrome: a back affordance on the left, optional actions on the right.
//
// Design source: the demo's `.sub-head`, used by the chapters, about, analysis, explorer
// and board-editor scenes. A back text button with a 16px chevron-left, the destination
// named in words ("Review", "Library"), and — for analysis — a "Flip board" text button on
// the right. No title, no app bar elevation, no fill: the scene's own heading carries the
// name, and on wide layouts the heading moves into the side panel (see SrsSceneLayout).
//
// It replaces the Lichess `AppBar` on those scenes. The design's rule is "drop Lichess
// widgets and icons" (design/docs/03 §12), so the chevron is painted here rather than
// pulled from the icon font.
import 'package:chess_srs/src/design/primitives.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

class SrsSubHead extends StatelessWidget implements PreferredSizeWidget {
  const SrsSubHead({
    super.key,
    required this.backLabel,
    required this.onBack,
    this.trailing = const SizedBox.shrink(),
  });

  /// Height: 8px of padding above and below a 44px control.
  static const double height = 60;

  /// Where this screen came from, named the way the demo names it: `‹ Review`,
  /// `‹ Library`. Not a generic "Back" — the destination should be predictable.
  final String backLabel;

  final VoidCallback onBack;

  /// Optional right-hand action, e.g. a screen's overflow menu.
  ///
  /// Deliberately a single slot. A screen that used `AppBar.bottom` for a second row
  /// (the explorer's move list) puts it in the body instead: a variable-height app bar
  /// has to report its own size back to the `Scaffold` before layout, which is more
  /// machinery than one strip of moves is worth.
  final Widget trailing;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _BackButton(label: backLabel, onPressed: onBack),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      radius: 10,
      builder: (context, hover, _) => Container(
        constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hover ? c.hairlineSoft : const Color(0x00000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(16, 16),
              painter: _ChevronLeftPainter(color: c.ink),
            ),
            const SizedBox(width: 5),
            Text(label, style: SrsText.textButton(hover ? c.ink : c.ink)),
          ],
        ),
      ),
    );
  }
}

/// 16x16 chevron-left, stroke 1.8.
class _ChevronLeftPainter extends CustomPainter {
  const _ChevronLeftPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.625, size.height * 0.1875)
      ..lineTo(size.width * 0.3125, size.height * 0.5)
      ..lineTo(size.width * 0.625, size.height * 0.8125);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronLeftPainter old) => old.color != color;
}
