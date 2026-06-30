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
  final List<double> predictions; // shape [6]
  final List<List<List<double>>> featureMaps; // shape [7, 7, 1280]
  final List<double> denseActivations; // shape [128]
  final Duration inferenceTime;

  InferenceResult({
    required this.predictions,
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
      debugPrint("Initializing TFLite Interpreter...");
      // Load interpreter
      _interpreter = await tfl.Interpreter.fromAsset('assets/models/banana_disease_model.tflite');
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
    switch (modelIndex) {
      case 0: return 0; // Black_Sigatoka -> Black_Sigatoka
      case 1: return 1; // Cordana -> Cordana
      case 2: return 2; // Healthy -> Healthy
      case 3: return 3; // Panama_Disease -> Panama_Disease
      case 4: return 5; // Pestalotiopsis -> Pestalotiopsis
      case 5: return 6; // Yellow_Sigatoka -> Yellow_Sigatoka
      default: return 2; // Default to Healthy
    }
  }

  Future<InferenceResult> runInference(File imageFile, {bool bypassIqa = false}) async {
    await initialize();

    final stopwatch = Stopwatch()..start();

    // 1. Preprocess image with optional Image Quality Assessment
    final inputTensor = await _preprocessImage(imageFile, bypassIqa: bypassIqa);

    // 2. Prepare output buffers
    // Output 0: Predictions shape [1, 6]
    var predictionsOut = List.generate(1, (i) => List.filled(6, 0.0));
    
    // Output 1: Feature maps shape [1, 7, 7, 1280]
    var featureMapsOut = List.generate(
      1,
      (i) => List.generate(
        7,
        (j) => List.generate(
          7,
          (k) => List.filled(1280, 0.0),
        ),
      ),
    );
    
    // Output 2: Dense activations shape [1, 128]
    var denseActivationsOut = List.generate(1, (i) => List.filled(128, 0.0));

    final outputs = {
      0: featureMapsOut,
      1: denseActivationsOut,
      2: predictionsOut,
    };

    // 3. Run inference
    _interpreter!.runForMultipleInputs([inputTensor], outputs);

    stopwatch.stop();

    // Flatten first dimension [0] for easier usage
    return InferenceResult(
      predictions: predictionsOut[0],
      featureMaps: featureMapsOut[0],
      denseActivations: denseActivationsOut[0],
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
