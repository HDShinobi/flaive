import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Flaive',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _BrandMarkPainter(
            color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Preserve the 100-unit aspect ratio even under non-square constraints.
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 100);
    final paint = Paint()..color = color;
    for (final bar in const [
      Rect.fromLTWH(24.9, 32.9, 7.4, 30.1),
      Rect.fromLTWH(35.6, 23.6, 7.4, 39.4),
      Rect.fromLTWH(46.2, 14.2, 7.5, 52.0),
      Rect.fromLTWH(56.9, 23.6, 7.4, 39.4),
      Rect.fromLTWH(67.6, 32.9, 7.4, 30.1),
    ]) {
      canvas.drawRect(bar, paint);
    }
    canvas.drawPath(
      Path()
        ..moveTo(28.5, 66.2)
        ..lineTo(71.5, 66.2)
        ..lineTo(50, 85.7)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      color != oldDelegate.color;
}
