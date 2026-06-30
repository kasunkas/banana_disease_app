import 'dart:ui';
import 'package:flutter/material.dart';

class RefractiveBorderPainter extends CustomPainter {
  final double borderRadius;
  final double borderWidth;
  final List<Color> colors;

  RefractiveBorderPainter({
    required this.borderRadius,
    required this.borderWidth,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    
    final paint = Paint()
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant RefractiveBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.colors != colors;
  }
}

class GlassCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final bool animateOnTap;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.blur = 15.0,
    this.color,
    this.borderColor,
    this.borderWidth = 1.2,
    this.onTap,
    this.animateOnTap = true,
    this.shadow,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _sheenController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _sheenAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    // Tactile spring controller for scale transition
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // Sheen sweep reflection controller
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _sheenAnimation = Tween<double>(begin: -1.8, end: 1.8).animate(
      CurvedAnimation(parent: _sheenController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _sheenController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null && widget.animateOnTap) {
      _scaleController.forward();
      _sheenController.forward(from: 0.0);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap != null && widget.animateOnTap) {
      _scaleController.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null && widget.animateOnTap) {
      _scaleController.reverse();
    }
  }

  void _triggerHoverEffect(bool isHovered) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isHovered = isHovered;
      });
      if (isHovered && widget.onTap != null && widget.animateOnTap) {
        _sheenController.forward(from: 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Premium default glass colors with subtle translucency
    final defaultColor = widget.color ?? 
        (isDark 
            ? Colors.black.withValues(alpha: 0.22) 
            : Colors.white.withValues(alpha: 0.42));
            
    // Setup glass refractive colors: Top-Left highlights (white/glow) vs Bottom-Right shadow (translucent grey/black)
    final List<Color> refractiveBorderColors = widget.borderColor != null 
        ? [widget.borderColor!, widget.borderColor!]
        : (isDark 
            ? [
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.22),
              ]
            : [
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.08),
              ]);

    final Widget cardBody = Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      child: Stack(
        children: [
          // 1. Frosted blur layer
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                child: Container(
                  decoration: BoxDecoration(
                    color: defaultColor,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    boxShadow: widget.shadow ?? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.06 : 0.03),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Content overlay with padding
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Padding(
              padding: widget.padding ?? const EdgeInsets.all(16.0),
              child: widget.child,
            ),
          ),

          // 3. Dynamic Sheen sweep reflection overlay
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sheenAnimation,
                builder: (context, child) {
                  if (_sheenController.isAnimating) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      child: FractionalTranslation(
                        translation: Offset(_sheenAnimation.value, 0.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              stops: const [0.35, 0.5, 0.65],
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(alpha: isDark ? 0.12 : 0.22),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),

          // 4. Refractive outline border layer painted on top
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: RefractiveBorderPainter(
                  borderRadius: widget.borderRadius,
                  borderWidth: widget.borderWidth,
                  colors: refractiveBorderColors,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.onTap == null) {
      return cardBody;
    }

    return MouseRegion(
      onEnter: (_) => _triggerHoverEffect(true),
      onExit: (_) => _triggerHoverEffect(false),
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: _isHovered && widget.animateOnTap
                  ? [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.12),
                        blurRadius: 18,
                        spreadRadius: 3,
                      )
                    ]
                  : [],
            ),
            child: cardBody,
          ),
        ),
      ),
    );
  }
}
