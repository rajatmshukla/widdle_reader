import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showTitle;
  final bool animate;

  const AppLogo({
    super.key,
    this.size = 80,
    this.showTitle = false,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final seedColor = themeProvider.seedColor;
    final isDarkMode = themeProvider.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;

    final primaryColor = seedColor;
    final secondaryColor =
        isDarkMode ? seedColor.withOpacity(0.6) : seedColor.withOpacity(0.4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.06),
          decoration: BoxDecoration(
            color: secondaryColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                color: seedColor.withOpacity(0.3),
                blurRadius: size * 0.1,
                offset: Offset(0, size * 0.05),
              ),
            ],
          ),
          child: Image.asset(
            'assets/icons/app_logo_holidays.png',
            width: size * 0.88,
            height: size * 0.88,
            errorBuilder: (context, error, stackTrace) => CustomPaint(
              size: Size(size * 0.88, size * 0.88),
              painter: SmileyBookHeadphonesPainter(
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                accentColor: colorScheme.surface,
                faceColor: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (showTitle) ...[
          SizedBox(height: size * 0.18),
          Text(
            'Widdle Reader',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: size * 0.05),
          Text(
            'Your cute audiobook companion',
            style: TextStyle(
              fontSize: size * 0.1,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ],
    );
  }
}

class SmileyBookHeadphonesPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color faceColor;

  SmileyBookHeadphonesPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.faceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Paints
    final bookPaint =
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.fill;

    final headphonePaint =
        Paint()
          ..color = secondaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.09
          ..strokeCap = StrokeCap.round;

    final facePaint =
        Paint()
          ..color = faceColor
          ..style = PaintingStyle.fill;

    // Book shape
    final bookRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(width * 0.2, height * 0.2, width * 0.6, height * 0.6),
      Radius.circular(width * 0.15),
    );
    canvas.drawRRect(bookRect, bookPaint);

    // Headphones arc
    final arcPath = Path();
    arcPath.moveTo(width * 0.1, height * 0.4);
    arcPath.arcToPoint(
      Offset(width * 0.9, height * 0.4),
      radius: Radius.circular(width * 0.5),
      clockwise: false,
    );
    canvas.drawPath(arcPath, headphonePaint);

    // Earpads
    canvas.drawCircle(
      Offset(width * 0.1, height * 0.4),
      width * 0.06,
      headphonePaint,
    );
    canvas.drawCircle(
      Offset(width * 0.9, height * 0.4),
      width * 0.06,
      headphonePaint,
    );

    // Eyes (dots)
    canvas.drawCircle(
      Offset(width * 0.38, height * 0.45),
      width * 0.04,
      facePaint,
    );
    canvas.drawCircle(
      Offset(width * 0.62, height * 0.45),
      width * 0.04,
      facePaint,
    );

    // Smile
    final smilePath = Path();
    smilePath.moveTo(width * 0.4, height * 0.6);
    smilePath.quadraticBezierTo(
      width * 0.5,
      height * 0.68,
      width * 0.6,
      height * 0.6,
    );
    final smilePaint =
        Paint()
          ..color = faceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.04
          ..strokeCap = StrokeCap.round;
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
