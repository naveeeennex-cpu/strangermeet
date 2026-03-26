import 'dart:math';
import 'package:flutter/material.dart';

/// WhatsApp-style chat background color constant.
/// Use this in all chat screens for consistency.
const Color kChatBackgroundColor = Color(0xFFECE5DD);

/// A subtle doodle-pattern painter for chat backgrounds.
/// Draws very faint icons (chat bubbles, hearts, stars, etc.) in a grid,
/// similar to WhatsApp's default wallpaper pattern.
class ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const spacing = 60.0;
    final cols = (size.width / spacing).ceil() + 1;
    final rows = (size.height / spacing).ceil() + 1;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = col * spacing + (row.isOdd ? spacing / 2 : 0);
        final y = row * spacing;
        final iconIndex = (row * cols + col) % 6;

        canvas.save();
        canvas.translate(x, y);
        _drawIcon(canvas, paint, iconIndex);
        canvas.restore();
      }
    }
  }

  void _drawIcon(Canvas canvas, Paint paint, int index) {
    switch (index) {
      case 0:
        // Chat bubble
        final path = Path()
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(-8, -6, 16, 12),
            const Radius.circular(4),
          ))
          ..moveTo(-4, 6)
          ..lineTo(-8, 10)
          ..lineTo(-2, 6);
        canvas.drawPath(path, paint);
        break;
      case 1:
        // Heart
        final path = Path()
          ..moveTo(0, 3)
          ..cubicTo(-8, -4, -8, -8, -2, -8)
          ..cubicTo(0, -8, 0, -6, 0, -5)
          ..cubicTo(0, -6, 0, -8, 2, -8)
          ..cubicTo(8, -8, 8, -4, 0, 3);
        canvas.drawPath(path, paint);
        break;
      case 2:
        // Star
        final path = Path();
        for (int i = 0; i < 5; i++) {
          final outerAngle = (i * 72 - 90) * pi / 180;
          final innerAngle = ((i * 72) + 36 - 90) * pi / 180;
          if (i == 0) {
            path.moveTo(7 * cos(outerAngle), 7 * sin(outerAngle));
          } else {
            path.lineTo(7 * cos(outerAngle), 7 * sin(outerAngle));
          }
          path.lineTo(3 * cos(innerAngle), 3 * sin(innerAngle));
        }
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 3:
        // Smiley face
        canvas.drawCircle(Offset.zero, 7, paint);
        canvas.drawCircle(const Offset(-2.5, -2), 1, paint..style = PaintingStyle.fill);
        canvas.drawCircle(const Offset(2.5, -2), 1, paint);
        paint.style = PaintingStyle.stroke;
        final smilePath = Path()
          ..addArc(const Rect.fromLTRB(-3.5, -1, 3.5, 5), 0.2, 2.7);
        canvas.drawPath(smilePath, paint);
        break;
      case 4:
        // Camera icon
        final body = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-8, -4, 16, 11),
          const Radius.circular(2),
        );
        canvas.drawRRect(body, paint);
        canvas.drawCircle(const Offset(0, 2), 3.5, paint);
        final lensPath = Path()
          ..moveTo(-3, -4)
          ..lineTo(-1, -7)
          ..lineTo(3, -7)
          ..lineTo(5, -4);
        canvas.drawPath(lensPath, paint);
        break;
      case 5:
        // Music note
        canvas.drawLine(const Offset(0, -8), const Offset(0, 4), paint);
        canvas.drawOval(const Rect.fromLTWH(-4, 2, 5, 4), paint);
        final flagPath = Path()
          ..moveTo(0, -8)
          ..quadraticBezierTo(6, -6, 4, -3);
        canvas.drawPath(flagPath, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
