import 'package:flutter/widgets.dart';

/// Jeepney icon using PNG image asset
/// Place your jeepney PNG file at: assets/images/jeep.png
/// Recommended: Square (1:1), transparent background, PNG format
class JeepIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const JeepIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/jeepIcon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to placeholder if image not found
        return _JeepPlaceholder(size: size, color: color ?? const Color(0xFF000000));
      },
    );
  }
}

/// Fallback placeholder widget when PNG is not available
class _JeepPlaceholder extends StatelessWidget {
  final double size;
  final Color color;

  const _JeepPlaceholder({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(size * 0.1),
      ),
      child: Center(
        child: Text(
          '🚐',
          style: TextStyle(fontSize: size * 0.6),
        ),
      ),
    );
  }
}

