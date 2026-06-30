import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class GradCamResult {
  final File overlayImageFile;
  final String severity; // Low, Medium, High
  final double affectedAreaPercentage;
  final List<List<double>> rawHeatmap;

  GradCamResult({
    required this.overlayImageFile,
    required this.severity,
    required this.affectedAreaPercentage,
    required this.rawHeatmap,
  });
}

class GradCamService {
  List<List<double>>? _w1; // Shape: [1280, 128]
  List<List<double>>? _w2; // Shape: [128, 6]
  bool _isLoaded = false;

  GradCamService();

  Future<void> loadWeights() async {
    if (_isLoaded) return;
    try {
      debugPrint("Loading dense weights for Grad-CAM...");
      final jsonString = await rootBundle.loadString('assets/models/dense_weights.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Parse w1
      final List<dynamic> w1List = data['w1'];
      _w1 = w1List.map((row) => (row as List).map((val) => (val as num).toDouble()).toList()).toList();

      // Parse w2
      final List<dynamic> w2List = data['w2'];
      _w2 = w2List.map((row) => (row as List).map((val) => (val as num).toDouble()).toList()).toList();

      _isLoaded = true;
      debugPrint("Grad-CAM weights loaded successfully.");
    } catch (e) {
      debugPrint("Error loading Grad-CAM weights: $e");
      rethrow;
    }
  }

  Future<GradCamResult> generateGradCam({
    required File originalImageFile,
    required int predictedClassIndex,
    required String diseaseName,
    required List<List<List<double>>> featureMaps, // Shape: [7, 7, 1280]
    required List<double> denseActivations, // Shape: [128]
  }) async {
    await loadWeights();

    // 1. Calculate the active units mask (M_j = 1 if H_j > 0 else 0)
    final int hiddenUnits = denseActivations.length; // 128
    final List<double> mask = List.filled(hiddenUnits, 0.0);
    for (int j = 0; j < hiddenUnits; j++) {
      mask[j] = denseActivations[j] > 0.0 ? 1.0 : 0.0;
    }

    // 2. Compute the channel weights alpha_k for the predicted class c
    // alpha_k = sum_j ( W2[j][c] * M[j] * W1[k][j] )
    final int numChannels = featureMaps[0][0].length; // 1280
    final List<double> alphas = List.filled(numChannels, 0.0);

    for (int k = 0; k < numChannels; k++) {
      double sum = 0.0;
      for (int j = 0; j < hiddenUnits; j++) {
        // _w2 shape: [128, 6]. Column predictedClassIndex corresponds to the class
        double w2Val = _w2![j][predictedClassIndex];
        double w1Val = _w1![k][j];
        sum += w2Val * mask[j] * w1Val;
      }
      alphas[k] = sum;
    }

    // 3. Compute the 2D heatmap (7x7) by taking weighted sum of features
    // heatmap(y, x) = max(0, sum_k (alpha_k * features(y, x, k)))
    final List<List<double>> heatmap = List.generate(7, (i) => List.filled(7, 0.0));
    double maxVal = 0.0;

    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        double sum = 0.0;
        for (int k = 0; k < numChannels; k++) {
          sum += alphas[k] * featureMaps[y][x][k];
        }
        // ReLU
        double val = max(0.0, sum);
        heatmap[y][x] = val;
        if (val > maxVal) {
          maxVal = val;
        }
      }
    }

    // 4. Normalize the heatmap to [0.0, 1.0]
    if (maxVal > 0.0) {
      for (int y = 0; y < 7; y++) {
        for (int x = 0; x < 7; x++) {
          heatmap[y][x] /= maxVal;
        }
      }
    }

    // 5. Calculate severity based on affected leaf area (pixels > 0.4) and mean activation intensity
    int affectedPixels = 0;
    double sumActivation = 0.0;
    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        if (heatmap[y][x] > 0.4) {
          affectedPixels++;
          sumActivation += heatmap[y][x];
        }
      }
    }
    
    final double affectedAreaPercentage = (affectedPixels / 49.0) * 100.0;
    final double meanIntensity = affectedPixels > 0 ? (sumActivation / affectedPixels) : 0.0;
    final double severityScore = affectedAreaPercentage * meanIntensity;
    
    String severity = "Low";
    if (diseaseName.toLowerCase() == 'healthy') {
      severity = "Low";
    } else {
      if (severityScore < 10.0) {
        severity = "Low";
      } else if (severityScore < 30.0) {
        severity = "Medium";
      } else {
        severity = "High";
      }
    }

    // 6. Generate the overlay image
    final File overlayFile = await _createOverlayImage(
      originalImageFile: originalImageFile,
      heatmap: heatmap,
    );

    return GradCamResult(
      overlayImageFile: overlayFile,
      severity: severity,
      affectedAreaPercentage: affectedAreaPercentage,
      rawHeatmap: heatmap,
    );
  }

  Future<File> _createOverlayImage({
    required File originalImageFile,
    required List<List<double>> heatmap,
  }) async {
    // Load original image
    final Uint8List imgBytes = await originalImageFile.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(imgBytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image originalImage = frameInfo.image;

    final int width = originalImage.width;
    final int height = originalImage.height;

    // Create 7x7 raw heatmap image
    final ui.Image heatmapImage = await _createRawHeatmapImage(heatmap);

    // Create a canvas to draw composite image
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    // Draw original image
    canvas.drawImage(originalImage, ui.Offset.zero, ui.Paint());

    // Draw the 7x7 heatmap image stretched over the original image size using high-quality bilinear filtering
    canvas.drawImageRect(
      heatmapImage,
      const ui.Rect.fromLTWH(0, 0, 7, 7),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    // Extract composite image
    final ui.Picture picture = recorder.endRecording();
    final ui.Image compositeImage = await picture.toImage(width, height);
    final ByteData? pngBytes = await compositeImage.toByteData(format: ui.ImageByteFormat.png);
    
    if (pngBytes == null) {
      throw Exception("Could not serialize composite image to PNG");
    }

    // Save composite image to temporary/app directory
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String filename = "gradcam_${DateTime.now().millisecondsSinceEpoch}.png";
    final File overlayFile = File('${appDir.path}/$filename');
    await overlayFile.writeAsBytes(pngBytes.buffer.asUint8List());

    // Clean up ui.Image memory
    originalImage.dispose();
    heatmapImage.dispose();
    compositeImage.dispose();

    return overlayFile;
  }

  Future<ui.Image> _createRawHeatmapImage(List<List<double>> heatmap) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        final double val = heatmap[y][x];
        final Color color = _getHeatmapColor(val);
        final ui.Paint paint = ui.Paint()..color = color;
        canvas.drawRect(ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0), paint);
      }
    }

    final ui.Picture picture = recorder.endRecording();
    return await picture.toImage(7, 7);
  }

  ui.Color _getHeatmapColor(double value) {
    if (value < 0.15) {
      return const ui.Color(0x00000000); // Fully transparent for low-importance regions
    }

    // Rescale value from [0.15, 1.0] to [0.0, 1.0]
    double normalized = (value - 0.15) / 0.85;

    // Heatmap opacity ranges up to 180/255 to keep leaf details visible underneath
    int alpha = (normalized * 150 + 40).toInt().clamp(0, 190);

    if (normalized < 0.25) {
      // Blue to Cyan
      double t = normalized / 0.25;
      return ui.Color.fromARGB(alpha, 0, (t * 255).toInt(), 255);
    } else if (normalized < 0.5) {
      // Cyan to Green
      double t = (normalized - 0.25) / 0.25;
      return ui.Color.fromARGB(alpha, 0, 255, (255 * (1.0 - t)).toInt());
    } else if (normalized < 0.75) {
      // Green to Yellow
      double t = (normalized - 0.5) / 0.25;
      return ui.Color.fromARGB(alpha, (t * 255).toInt(), 255, 0);
    } else {
      // Yellow to Red
      double t = (normalized - 0.75) / 0.25;
      return ui.Color.fromARGB(alpha, 255, (255 * (1.0 - t)).toInt(), 0);
    }
  }
}
