import 'dart:ui';
import 'package:flutter/material.dart';

class GlassSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;
  final double blur;

  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 52.0,
    this.height = 28.0,
    this.blur = 10.0,
  });

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      _scaleController.forward().then((_) => _scaleController.reverse());
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color activeColor = theme.primaryColor;

    final Color trackColor = widget.value
        ? activeColor.withValues(alpha: 0.28)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));

    final Color borderColor = widget.value
        ? activeColor.withValues(alpha: 0.45)
        : (isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.12));

    final double knobSize = widget.height - 6.0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: _handleTap,
        child: MouseRegion(
          cursor: widget.onChanged != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.height / 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.height / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(widget.height / 2),
                    border: Border.all(
                      color: borderColor,
                      width: 1.2,
                    ),
                    boxShadow: widget.value
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.15),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ]
                        : [],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.value)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  activeColor.withValues(alpha: 0.15),
                                  Colors.transparent,
                                ],
                                radius: 1.0,
                              ),
                            ),
                          ),
                        ),
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        alignment: widget.value
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: knobSize,
                          height: knobSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                              if (widget.value)
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  offset: const Offset(0, 0),
                                ),
                            ],
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.8) 
                                  : Colors.white,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
