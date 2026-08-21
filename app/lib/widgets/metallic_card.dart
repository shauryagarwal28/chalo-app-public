import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/metallic_painter.dart';

class MetallicCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool hasOrangeAccent;
  final List<BoxShadow>? shadows;

  const MetallicCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.hasOrangeAccent = false,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasOrangeAccent
              ? const [
                  Color(0xFF3A2818), // warm gunmetal top-left
                  Color(0xFF2D2218), // mid warm
                  Color(0xFF1E1F23), // base gunmetal
                  Color(0xFF242B30), // cool gunmetal
                ]
              : const [
                  Color(0xFF353D44), // lighter gunmetal — light hitting top
                  Color(0xFF2A3038), // base gunmetal
                  Color(0xFF222930), // slight shadow center
                  Color(0xFF2D3540), // slight highlight bottom-right
                ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ),
        border: Border.all(
          color: hasOrangeAccent
              ? ChaloColors.primary.withOpacity(0.45)
              : ChaloColors.borderShine.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              // Inner top highlight (simulates light catching top edge)
              BoxShadow(
                color: Colors.white.withOpacity(0.04),
                blurRadius: 0,
                offset: const Offset(0, -1),
                spreadRadius: 0,
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: CustomPaint(
          painter: const BrushedMetalPainter(),
          child: Stack(
            children: [
              // Diagonal shine streak
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-1.2, -1.2),
                        end: const Alignment(1.2, 1.2),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.03),
                          Colors.white.withOpacity(0.07),
                          Colors.white.withOpacity(0.03),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              if (padding != null)
                Padding(padding: padding!, child: child)
              else
                child,
            ],
          ),
        ),
      ),
    );
  }
}
