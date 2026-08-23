import 'dart:ui';
import 'package:flutter/cupertino.dart';

class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color color;
  final double blurStrength;

  const FrostedGlass({
    super.key,
    required this.child,
    this.borderRadius = 0.0,
    this.color = const Color(0x80FFFFFF),
    this.blurStrength = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurStrength, sigmaY: blurStrength),
        child: Container(
          color: color,
          child: child,
        ),
      ),
    );
  }
}

class FrostedPill extends StatelessWidget {
  final Widget child;
  final Color color;
  final double blurStrength;

  const FrostedPill({
    super.key,
    required this.child,
    this.color = const Color(0x80FFFFFF),
    this.blurStrength = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return FrostedGlass(
      borderRadius: 22.0,
      color: color,
      blurStrength: blurStrength,
      child: child,
    );
  }
}
