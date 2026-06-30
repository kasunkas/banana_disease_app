import 'dart:math';
import 'package:flutter/material.dart';

class GlassBackground extends StatefulWidget {
  final Widget child;
  final bool showSecondaryBlob;

  const GlassBackground({
    super.key,
    required this.child,
    this.showSecondaryBlob = true,
  });

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // A slow, organic drift loop
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    // Use theme-aligned colors for the background blobs
    final primaryBlobColor = theme.primaryColor.withValues(alpha: isDark ? 0.16 : 0.24);
    final secondaryBlobColor = theme.colorScheme.secondary.withValues(alpha: isDark ? 0.12 : 0.18);
    final tertiaryBlobColor = Colors.orangeAccent.withValues(alpha: isDark ? 0.05 : 0.1);

    return Stack(
      children: [
        // Solid background matching theme
        Container(
          color: theme.scaffoldBackgroundColor,
        ),
        
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value * 2 * pi;

            // Compute slow liquid shifts for positions
            final blob1Left = -80 + sin(t) * 35;
            final blob1Top = -80 + cos(t) * 25;
            
            final blob2Right = -60 + cos(t + pi/2) * 40;
            final blob2Bottom = 80 + sin(t + pi/2) * 30;

            final blob3Left = -50 + sin(t * 1.5) * 20;
            final blob3Top = size.height * 0.45 + cos(t * 1.5) * 35;

            // Liquid breathing scales
            final scale1 = 1.0 + sin(t) * 0.12;
            final scale2 = 1.0 + cos(t + pi) * 0.15;
            final scale3 = 1.0 + sin(t * 2) * 0.1;

            return Stack(
              children: [
                // Glow Blob 1: Top Left
                Positioned(
                  top: blob1Top,
                  left: blob1Left,
                  child: Transform.scale(
                    scale: scale1,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryBlobColor,
                        gradient: RadialGradient(
                          colors: [
                            primaryBlobColor,
                            primaryBlobColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Glow Blob 2: Bottom Right
                if (widget.showSecondaryBlob)
                  Positioned(
                    bottom: blob2Bottom,
                    right: blob2Right,
                    child: Transform.scale(
                      scale: scale2,
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: secondaryBlobColor,
                          gradient: RadialGradient(
                            colors: [
                              secondaryBlobColor,
                              secondaryBlobColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Glow Blob 3: Center Left (subtle)
                Positioned(
                  top: blob3Top,
                  left: blob3Left,
                  child: Transform.scale(
                    scale: scale3,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tertiaryBlobColor,
                        gradient: RadialGradient(
                          colors: [
                            tertiaryBlobColor,
                            tertiaryBlobColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        
        // The actual page content
        Positioned.fill(
          child: widget.child,
        ),
      ],
    );
  }
}
