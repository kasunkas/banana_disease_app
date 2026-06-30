import 'dart:io';
import 'package:flutter/material.dart';

class SeverityOverlay extends StatelessWidget {
  final File imageFile;
  final List<List<double>> rawHeatmap;
  final String diseaseName;
  final double baseOpacity;
  final bool showGradCam;
  final bool showSeverityMask;

  const SeverityOverlay({
    super.key,
    required this.imageFile,
    required this.rawHeatmap,
    required this.diseaseName,
    required this.baseOpacity,
    required this.showGradCam,
    required this.showSeverityMask,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Base image from local storage
        if (imageFile.existsSync())
          Image.file(
            imageFile,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          )
        else
          const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),

        // 2. CustomPainter layer for blending Grad-CAM and severity masks
        if (rawHeatmap.isNotEmpty && (showGradCam || showSeverityMask))
          Positioned.fill(
            child: CustomPaint(
              painter: SeverityOverlayPainter(
                rawHeatmap: rawHeatmap,
                diseaseName: diseaseName,
                baseOpacity: baseOpacity,
                showGradCam: showGradCam,
                showSeverityMask: showSeverityMask,
              ),
            ),
          ),
      ],
    );
  }
}

class SeverityOverlayPainter extends CustomPainter {
  final List<List<double>> rawHeatmap;
  final String diseaseName;
  final double baseOpacity;
  final bool showGradCam;
  final bool showSeverityMask;

  SeverityOverlayPainter({
    required this.rawHeatmap,
    required this.diseaseName,
    required this.baseOpacity,
    required this.showGradCam,
    required this.showSeverityMask,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rawHeatmap.isEmpty) return;

    final double cellWidth = size.width / 7;
    final double cellHeight = size.height / 7;

    // Calculate affected area percentage to determine severity color
    int activeCells = 0;
    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        if (rawHeatmap[y][x] > 0.4) {
          activeCells++;
        }
      }
    }
    final double affectedAreaPercentage = (activeCells / 49.0) * 100.0;

    // Color Coding Logic:
    // Green = Healthy or Low severity (<10% symptomatic area)
    // Yellow = Medium severity (10–40% symptomatic area)
    // Red = High severity (>40% symptomatic area)
    Color severityColor = Colors.greenAccent; 
    if (diseaseName.toLowerCase() != 'healthy') {
      if (affectedAreaPercentage > 40.0) {
        severityColor = Colors.redAccent;
      } else if (affectedAreaPercentage >= 10.0) {
        severityColor = Colors.amberAccent;
      }
    }

    // Draw overlays for each grid cell
    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        final double val = rawHeatmap[y][x];
        if (val < 0.15) continue; // Skip background / low importance regions

        final rect = Rect.fromLTWH(
          x * cellWidth,
          y * cellHeight,
          cellWidth,
          cellHeight,
        );

        if (showGradCam && !showSeverityMask) {
          // Mode: Grad-CAM only (Spectrum coloring)
          final Color gcColor = _getHeatmapColor(val).withValues(alpha: baseOpacity * val);
          canvas.drawRect(rect, Paint()..color = gcColor);
        } else if (showSeverityMask && !showGradCam) {
          // Mode: Severity Mask only (Solid severity color modulated by intensity)
          final Color maskColor = severityColor.withValues(alpha: baseOpacity * val);
          canvas.drawRect(rect, Paint()..color = maskColor);
        } else if (showGradCam && showSeverityMask) {
          // Mode: Combined - Blend spectrum and severity colors
          final Color gcColor = _getHeatmapColor(val);
          final Color blendedColor = Color.lerp(gcColor, severityColor, 0.45)!
              .withValues(alpha: baseOpacity * val);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            Paint()..color = blendedColor,
          );
        }
      }
    }
  }

  Color _getHeatmapColor(double value) {
    // Rescale from [0.15, 1.0] to [0.0, 1.0]
    double normalized = ((value - 0.15) / 0.85).clamp(0.0, 1.0);
    if (normalized < 0.25) {
      double t = normalized / 0.25;
      return Color.fromARGB(255, 0, (t * 255).toInt(), 255); // Blue to Cyan
    } else if (normalized < 0.5) {
      double t = (normalized - 0.25) / 0.25;
      return Color.fromARGB(255, 0, 255, (255 * (1.0 - t)).toInt()); // Cyan to Green
    } else if (normalized < 0.75) {
      double t = (normalized - 0.5) / 0.25;
      return Color.fromARGB(255, (t * 255).toInt(), 255, 0); // Green to Yellow
    } else {
      double t = (normalized - 0.75) / 0.25;
      return Color.fromARGB(255, 255, (255 * (1.0 - t)).toInt(), 0); // Yellow to Red
    }
  }

  @override
  bool shouldRepaint(covariant SeverityOverlayPainter oldDelegate) {
    return oldDelegate.rawHeatmap != rawHeatmap ||
        oldDelegate.diseaseName != diseaseName ||
        oldDelegate.baseOpacity != baseOpacity ||
        oldDelegate.showGradCam != showGradCam ||
        oldDelegate.showSeverityMask != showSeverityMask;
  }
}
