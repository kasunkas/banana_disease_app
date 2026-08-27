import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart' as tfl;
import 'package:path_provider/path_provider.dart';

class IqaException implements Exception {
  final String message;
  final double brightness;
  final double contrast;

  IqaException(this.message, this.brightness, this.contrast);

  @override
  String toString() => 'IQA Warning: $message (Brightness: ${brightness.toStringAsFixed(2)}, Contrast: ${contrast.toStringAsFixed(3)})';
}

class InferenceResult {
  final List<double> predictions; // shape [7] (disease probabilities)
  final List<double> severityPredictions; // shape [3] (low, medium, high probabilities)
  final String predictedDisease;
  final String predictedSeverity;
  final double diseaseConfidence;
  final double severityConfidence;
  final String? warningMessage;
  final List<List<List<double>>> featureMaps;
  final List<double> denseActivations;
  final Duration inferenceTime;

  InferenceResult({
    required this.predictions,
    required this.severityPredictions,
    required this.predictedDisease,
    required this.predictedSeverity,
    required this.diseaseConfidence,
    required this.severityConfidence,
    this.warningMessage,
    required this.featureMaps,
    required this.denseActivations,
    required this.inferenceTime,
  });
}

class TfliteService {
  tfl.Interpreter? _interpreter;
  List<String> _labels = [];

  TfliteService();

  Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      debugPrint("Initializing Multitask TFLite Interpreter...");
      // Load interpreter
      _interpreter = await tfl.Interpreter.fromAsset('assets/models/banana_multitask_model.tflite');
      debugPrint("Interpreter loaded successfully.");

      // Load labels
      final labelsData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelsData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      debugPrint("Labels loaded: $_labels");
    } catch (e) {
      debugPrint("Error initializing TfliteService: $e");
      rethrow;
    }
  }

  List<String> get labels => _labels;

  int mapModelIndexToUiIndex(int modelIndex) {
    return modelIndex;
  }

  Future<InferenceResult> runInference(File imageFile, {bool bypassIqa = false}) async {
    await initialize();

    final stopwatch = Stopwatch()..start();

    // 1. Preprocess image with optional Image Quality Assessment
    final inputTensor = await _preprocessImage(imageFile, bypassIqa: bypassIqa);

    // 2. Prepare output buffers & determine tensor indices dynamically
    final output0Shape = _interpreter!.getOutputTensor(0).shape;
    final output1Shape = _interpreter!.getOutputTensor(1).shape;

    int diseaseOutputIndex = 1;
    int severityOutputIndex = 0;

    if (output0Shape.last == 7) {
      diseaseOutputIndex = 0;
      severityOutputIndex = 1;
    } else if (output1Shape.last == 7) {
      diseaseOutputIndex = 1;
      severityOutputIndex = 0;
    }

    var diseaseOut = List.generate(1, (i) => List.filled(7, 0.0));
    var severityOut = List.generate(1, (i) => List.filled(3, 0.0));

    final outputs = {
      diseaseOutputIndex: diseaseOut,
      severityOutputIndex: severityOut,
    };

    // 3. Run inference
    _interpreter!.runForMultipleInputs([inputTensor], outputs);

    stopwatch.stop();

    List<double> diseaseProbs = diseaseOut[0];
    List<double> severityProbs = severityOut[0];

    // 4. Parse Disease Prediction
    int maxDiseaseIdx = 0;
    double maxDiseaseProb = -1.0;
    for (int i = 0; i < diseaseProbs.length; i++) {
      if (diseaseProbs[i] > maxDiseaseProb) {
        maxDiseaseProb = diseaseProbs[i];
        maxDiseaseIdx = i;
      }
    }

    String predictedDisease = (maxDiseaseIdx < _labels.length) ? _labels[maxDiseaseIdx] : "Healthy";
    double diseaseConfidence = maxDiseaseProb * 100.0;

    // 5. Parse Severity Prediction (0: Low, 1: Medium, 2: High)
    const List<String> severityLabels = ["Low", "Medium", "High"];
    int maxSeverityIdx = 0;
    double maxSeverityProb = -1.0;
    for (int i = 0; i < severityProbs.length; i++) {
      if (severityProbs[i] > maxSeverityProb) {
        maxSeverityProb = severityProbs[i];
        maxSeverityIdx = i;
      }
    }

    String predictedSeverity = severityLabels[maxSeverityIdx];
    double severityConfidence = maxSeverityProb * 100.0;

    if (predictedDisease.toLowerCase() == 'healthy') {
      predictedSeverity = "Low";
    }

    // 6. Borderline Severity Warning Logic
    String? warningMessage;
    if (predictedDisease.toLowerCase() != 'healthy') {
      double pLow = severityProbs[0];
      double pMedium = severityProbs[1];
      double pHigh = severityProbs[2];

      if (predictedSeverity == "Medium") {
        if ((pMedium - pHigh) <= 0.15) {
          warningMessage = "Borderline Severity Warning: High severity probability is within 15% of Medium. The true severity may be higher than reported.";
        } else if ((pMedium - pLow) <= 0.15) {
          warningMessage = "Borderline Severity Warning: Low severity probability is close to Medium. Monitor closely.";
        }
      } else if (predictedSeverity == "Low") {
        if ((pLow - pMedium) <= 0.15) {
          warningMessage = "Borderline Severity Warning: Medium severity probability is within 15% of Low. The true severity may be higher than reported.";
        }
      }
    }

    // Fallback feature maps & dense activations for Grad-CAM backward compatibility
    var featureMapsOut = List.generate(
      7,
      (j) => List.generate(
        7,
        (k) => List.filled(1280, 0.0),
      ),
    );
    var denseActivationsOut = List.filled(128, 0.0);

    return InferenceResult(
      predictions: diseaseProbs,
      severityPredictions: severityProbs,
      predictedDisease: predictedDisease,
      predictedSeverity: predictedSeverity,
      diseaseConfidence: diseaseConfidence,
      severityConfidence: severityConfidence,
      warningMessage: warningMessage,
      featureMaps: featureMapsOut,
      denseActivations: denseActivationsOut,
      inferenceTime: stopwatch.elapsed,
    );
  }

  Future<List<List<List<List<double>>>>> _preprocessImage(File file, {bool bypassIqa = false}) async {
    final bytes = await file.readAsBytes();
    
    // Use native Skia codec to resize to 224x224
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 224,
      targetHeight: 224,
    );
    final frame = await codec.getNextFrame();
    final ui.Image uiImage = frame.image;
    
    final ByteData? byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception("Could not retrieve byte data from image");
    }
    
    final Uint8List rgbaBytes = byteData.buffer.asUint8List();
    
    // Create preprocessed array: [1, 224, 224, 3]
    var input = List.generate(
      1,
      (i) => List.generate(
        224,
        (j) => List.generate(
          224,
          (k) => List.filled(3, 0.0),
        ),
      ),
    );

    double totalIntensity = 0.0;
    List<double> intensities = List.filled(224 * 224, 0.0);

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        int index = (y * 224 + x) * 4;
        
        // Normalize pixels to [0.0, 1.0]
        double r = rgbaBytes[index] / 255.0;
        double g = rgbaBytes[index + 1] / 255.0;
        double b = rgbaBytes[index + 2] / 255.0;
        
        input[0][y][x][0] = r;
        input[0][y][x][1] = g;
        input[0][y][x][2] = b;

        // Gray intensity for IQA: Y = 0.299*R + 0.587*G + 0.114*B
        double yVal = 0.299 * r + 0.587 * g + 0.114 * b;
        totalIntensity += yVal;
        intensities[y * 224 + x] = yVal;
      }
    }

    double meanIntensity = totalIntensity / (224 * 224);

    // Calculate Variance & StdDev (Contrast metric)
    double sumVariance = 0.0;
    for (int i = 0; i < intensities.length; i++) {
      double diff = intensities[i] - meanIntensity;
      sumVariance += diff * diff;
    }
    double variance = sumVariance / intensities.length;
    double stdDev = math.sqrt(variance);

    // Image Quality Assessment (IQA) checks
    if (!bypassIqa) {
      if (meanIntensity < 0.15) {
        throw IqaException(
          "The photo is too dark. Please scan in a well-lit area or turn on your flash.",
          meanIntensity,
          stdDev,
        );
      }
      if (meanIntensity > 0.85) {
        throw IqaException(
          "The photo is overexposed. Please avoid direct sunlight reflection or harsh glare.",
          meanIntensity,
          stdDev,
        );
      }
      if (stdDev < 0.075) {
        throw IqaException(
          "Low contrast or blurry image detected. Please make sure the banana leaf is in focus.",
          meanIntensity,
          stdDev,
        );
      }
    }

    // Clean up ui.Image memory
    uiImage.dispose();

    return input;
  }

  Future<File> cropImage(File originalFile, double left, double top, double width, double height) async {
    final bytes = await originalFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ui.Image uiImage = frame.image;

    final double imageWidth = uiImage.width.toDouble();
    final double imageHeight = uiImage.height.toDouble();

    final double cropX = left * imageWidth;
    final double cropY = top * imageHeight;
    final double cropW = width * imageWidth;
    final double cropH = height * imageHeight;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    
    canvas.drawImageRect(
      uiImage,
      ui.Rect.fromLTWH(cropX, cropY, cropW, cropH),
      ui.Rect.fromLTWH(0, 0, cropW, cropH),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image croppedUiImage = await picture.toImage(cropW.toInt(), cropH.toInt());
    
    final ByteData? pngBytes = await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) {
      throw Exception("Could not crop image");
    }

    final tempDir = await getTemporaryDirectory();
    final String filename = "crop_${DateTime.now().microsecondsSinceEpoch}.png";
    final File croppedFile = File('${tempDir.path}/$filename');
    await croppedFile.writeAsBytes(pngBytes.buffer.asUint8List());

    // Clean up memory
    uiImage.dispose();
    croppedUiImage.dispose();

    return croppedFile;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
