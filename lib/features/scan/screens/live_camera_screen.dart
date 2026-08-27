import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

import '../../../core/services/providers.dart';
import '../../../core/services/tflite_service.dart';
import '../../../core/services/image_enhancement_service.dart';
import '../../../core/models/scan_model.dart';
import 'result_screen.dart';
import 'aggregation_result_screen.dart';
import '../../../core/widgets/glass_card.dart';

class LiveCameraScreen extends ConsumerStatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  ConsumerState<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends ConsumerState<LiveCameraScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _isCameraInitialized = false;
  int _selectedCameraIndex = 0;
  bool _isFlashOn = false;

  // Inference state
  Timer? _inferenceTimer;
  bool _isProcessingInference = false;
  bool _isEnhancedActive = false;
  String? _lastResultLabel;
  double? _lastConfidence;
  String? _lastSeverity;
  String _guidanceMessage = "Initializing Live Camera Mode...";
  bool _hasCameraPermission = true;

  // Live leaf detection boxes
  List<Rect> _detectedLeafBoxes = [];
  DateTime _lastBoxDetectionTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _guidanceMessage = "No camera hardware detected.";
        });
        return;
      }
      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      setState(() {
        _hasCameraPermission = false;
        _guidanceMessage = "Camera access denied. Please enable permission in Settings.";
      });
    }
  }

  Future<void> _setupCameraController(CameraDescription camera) async {
    setState(() {
      _isCameraInitialized = false;
      _guidanceMessage = "Setting up camera controller...";
    });

    if (_controller != null) {
      await _controller!.dispose();
    }

    // Use ResolutionPreset.medium (e.g. 720p or 480p) to preserve battery and thermal performance
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      // Lock capture orientation to portrait to match layout
      await _controller!.lockCaptureOrientation();
      
      setState(() {
        _isCameraInitialized = true;
        _guidanceMessage = "Good quality – hold steady";
      });

      // 1. Start live YUV image stream for real-time leaf bounding boxes
      _controller!.startImageStream((CameraImage image) {
        _onAvailableImage(image);
      });

      // 2. Start periodic timer to run TFLite classification (every 1.5 seconds)
      _inferenceTimer?.cancel();
      _inferenceTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
        _runPeriodicInference();
      });
    } catch (e) {
      debugPrint("Camera setup error: $e");
      setState(() {
        _guidanceMessage = "Could not initialize camera preview.";
      });
    }
  }

  // Fast, low-power green/yellow grid detector to locate banana leaves on the live preview
  void _onAvailableImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastBoxDetectionTime).inMilliseconds < 400) {
      return; // Cap processing at ~2.5 FPS for thermal efficiency
    }
    _lastBoxDetectionTime = now;

    final boxes = _detectLeafBoxesHeuristic(image);
    if (!mounted) return;
    setState(() {
      _detectedLeafBoxes = boxes;
      if (boxes.length > 1 && _guidanceMessage == "Good quality – hold steady") {
        _guidanceMessage = "Multiple leaves detected";
      }
    });
  }

  List<Rect> _detectLeafBoxesHeuristic(CameraImage image) {
    if (image.planes.isEmpty) return [];

    final int width = image.width;
    final int height = image.height;
    final List<Point<int>> leafPoints = [];

    // Sample an 8x8 grid to minimize CPU usage
    const int cols = 8;
    const int rows = 8;
    final double stepX = width / cols;
    final double stepY = height / rows;

    final bool isYuv = image.format.group == ImageFormatGroup.yuv420;
    final bool isBgra = image.format.group == ImageFormatGroup.bgra8888;

    if (isYuv && image.planes.length >= 3) {
      final yBytes = image.planes[0].bytes;
      final uBytes = image.planes[1].bytes;
      final vBytes = image.planes[2].bytes;

      final yRowStride = image.planes[0].bytesPerRow;
      final uvRowStride = image.planes[1].bytesPerRow;
      final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int r = 1; r < rows - 1; r++) {
        for (int c = 1; c < cols - 1; c++) {
          final int px = (c * stepX).toInt();
          final int py = (r * stepY).toInt();

          final int yIndex = py * yRowStride + px;
          final int uvX = px >> 1;
          final int uvY = py >> 1;
          final int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

          if (yIndex < yBytes.length && uvIndex < uBytes.length && uvIndex < vBytes.length) {
            final int yVal = yBytes[yIndex];
            final int uVal = uBytes[uvIndex];
            final int vVal = vBytes[uvIndex];

            // Fast integer conversion to RGB
            final double rVal = yVal + 1.402 * (vVal - 128);
            final double gVal = yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128);
            final double bVal = yVal + 1.772 * (uVal - 128);

            // Leaf detection: check for high green/yellow saturation
            if (gVal > rVal + 12 && gVal > bVal + 12) {
              leafPoints.add(Point(c, r));
            } else if (rVal > gVal && rVal > bVal + 28 && gVal > bVal + 18) {
              leafPoints.add(Point(c, r));
            }
          }
        }
      }
    } else if (isBgra && image.planes.isNotEmpty) {
      final bytes = image.planes[0].bytes;
      final rowStride = image.planes[0].bytesPerRow;
      final pixelStride = image.planes[0].bytesPerPixel ?? 4;

      for (int r = 1; r < rows - 1; r++) {
        for (int c = 1; c < cols - 1; c++) {
          final int px = (c * stepX).toInt();
          final int py = (r * stepY).toInt();
          final int index = py * rowStride + px * pixelStride;

          if (index + 2 < bytes.length) {
            final int bVal = bytes[index];
            final int gVal = bytes[index + 1];
            final int rVal = bytes[index + 2];

            if (gVal > rVal + 12 && gVal > bVal + 12) {
              leafPoints.add(Point(c, r));
            } else if (rVal > gVal && rVal > bVal + 28 && gVal > bVal + 18) {
              leafPoints.add(Point(c, r));
            }
          }
        }
      }
    }

    if (leafPoints.isEmpty) return [];

    final List<Rect> boxes = [];
    if (leafPoints.length >= 2) {
      // Split points into left and right halves to allow detecting multiple leaves
      final leftPoints = leafPoints.where((p) => p.x < cols / 2).toList();
      final rightPoints = leafPoints.where((p) => p.x >= cols / 2).toList();

      if (leftPoints.length >= 2) {
        boxes.add(_getBoxFromPoints(leftPoints, cols, rows));
      }
      if (rightPoints.length >= 2) {
        boxes.add(_getBoxFromPoints(rightPoints, cols, rows));
      }

      if (boxes.isEmpty) {
        boxes.add(_getBoxFromPoints(leafPoints, cols, rows));
      }
    }

    return boxes;
  }

  Rect _getBoxFromPoints(List<Point<int>> points, int cols, int rows) {
    int minX = cols;
    int maxX = 0;
    int minY = rows;
    int maxY = 0;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    // Add extra padding around coordinates
    double left = (minX - 0.5).clamp(0, cols) / cols;
    double top = (minY - 0.5).clamp(0, rows) / rows;
    double width = (maxX - minX + 1.5).clamp(1.0, cols) / cols;
    double height = (maxY - minY + 1.5).clamp(1.0, rows) / rows;

    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _runPeriodicInference() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessingInference) {
      return;
    }

    setState(() {
      _isProcessingInference = true;
    });

    try {
      // 1. Temporarily pause the stream to prevent platform channel resource collisions
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      // 2. Capture a frame to a temp file
      final XFile imageFile = await _controller!.takePicture();
      final file = File(imageFile.path);

      // 3. Restart the stream immediately to keep preview feedback live
      if (mounted && _controller != null) {
        await _controller!.startImageStream((CameraImage img) {
          _onAvailableImage(img);
        });
      }

      // 4. Run classification and Image Quality Assessment (IQA)
      final tfliteService = ref.read(tfliteServiceProvider);
      
      // Run enhancement if enabled
      final enhancementService = ref.read(imageEnhancementServiceProvider);
      final enhancementEnabled = ref.read(imageEnhancementEnabledProvider);
      final enhancementStrength = ref.read(imageEnhancementStrengthProvider);
      
      final EnhancementResult enhancementResult = await enhancementService.enhanceImage(
        file,
        enabled: enhancementEnabled,
        strength: enhancementStrength,
      );
      
      final fileToAnalyze = enhancementResult.enhancedFile;
      final inferenceResult = await tfliteService.runInference(fileToAnalyze);

      // 5. Parse classification outputs
      final String rawClassName = inferenceResult.predictedDisease;
      final double confidence = inferenceResult.diseaseConfidence;
      final String severity = inferenceResult.predictedSeverity;

      if (mounted) {
        setState(() {
          _lastResultLabel = rawClassName;
          _lastConfidence = confidence;
          _lastSeverity = severity;
          _guidanceMessage = enhancementResult.wasEnhanced
              ? "Low light detected — Image enhanced for better accuracy"
              : "Good quality – hold steady";
          _isEnhancedActive = enhancementResult.wasEnhanced;
          _isProcessingInference = false;
        });
      }

      // Delete temporary file to avoid local disk clutter
      await file.delete();
      if (enhancementResult.wasEnhanced && fileToAnalyze.path != file.path) {
        try {
          await fileToAnalyze.delete();
        } catch (_) {}
      }
    } on IqaException catch (e) {
      if (mounted) {
        setState(() {
          // Map technical IQA exceptions to clear guidance suggestions
          if (e.message.toLowerCase().contains("dark")) {
            _guidanceMessage = "Poor lighting – please adjust";
          } else if (e.message.toLowerCase().contains("exposed")) {
            _guidanceMessage = "Poor lighting – glare detected";
          } else if (e.message.toLowerCase().contains("contrast") || e.message.toLowerCase().contains("blurry")) {
            _guidanceMessage = "Move closer to the leaf";
          } else {
            _guidanceMessage = "Quality low – hold steady";
          }
          _lastResultLabel = null;
          _lastConfidence = null;
          _lastSeverity = null;
          _isProcessingInference = false;
        });
      }
    } catch (e) {
      debugPrint("Periodic inference error: $e");
      if (mounted) {
        setState(() {
          _isProcessingInference = false;
        });
      }
    }
  }

  // Taps capture button: stops timers/streams, saves current frame, runs Grad-CAM, and opens details
  Future<void> _captureAndAnalyzeSingle() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _guidanceMessage = "Capturing high-resolution diagnosis...";
      _isProcessingInference = true;
    });

    try {
      _inferenceTimer?.cancel();
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final XFile imageFile = await _controller!.takePicture();
      final file = File(imageFile.path);

      if (!mounted) return;

      // Show processing overlay dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Enhancing & Generating Grad-CAM..."),
            ],
          ),
        ),
      );

      final tfliteService = ref.read(tfliteServiceProvider);
      final gradCamService = ref.read(gradCamServiceProvider);

      // Run enhancement
      final enhancementService = ref.read(imageEnhancementServiceProvider);
      final enhancementEnabled = ref.read(imageEnhancementEnabledProvider);
      final enhancementStrength = ref.read(imageEnhancementStrengthProvider);
      
      final EnhancementResult enhancementResult = await enhancementService.enhanceImage(
        file,
        enabled: enhancementEnabled,
        strength: enhancementStrength,
      );
      
      final fileToAnalyze = enhancementResult.enhancedFile;

      // Run inference
      final inferenceResult = await tfliteService.runInference(fileToAnalyze, bypassIqa: true);

      // Parse predictions
      final String rawClassName = inferenceResult.predictedDisease;
      final double confidence = inferenceResult.diseaseConfidence;
      final String severity = inferenceResult.predictedSeverity;
      int predictedIndex = tfliteService.labels.indexOf(rawClassName);
      if (predictedIndex < 0) predictedIndex = 0;

      // Generate Grad-CAM overlays
      final gradCamResult = await gradCamService.generateGradCam(
        originalImageFile: fileToAnalyze,
        predictedClassIndex: predictedIndex,
        diseaseName: rawClassName,
        featureMaps: inferenceResult.featureMaps,
        denseActivations: inferenceResult.denseActivations,
      );

      final scan = ScanModel(
        originalImagePath: fileToAnalyze.path,
        overlayImagePath: gradCamResult.overlayImageFile.path,
        diseaseName: rawClassName,
        confidence: confidence,
        severity: severity,
        inferenceTimeMs: inferenceResult.inferenceTime.inMilliseconds,
        createdAt: DateTime.now(),
        originalUnenhancedPath: enhancementResult.wasEnhanced ? file.path : null,
      );

      final Map<String, double> allProbabilities = {};
      for (int i = 0; i < inferenceResult.predictions.length; i++) {
        final label = tfliteService.labels[i].replaceAll('_', ' ');
        allProbabilities[label] = inferenceResult.predictions[i] * 100.0;
      }

      // Close processing overlay
      if (mounted) {
        Navigator.pop(context); // Pop dialog
        
        // Push ResultScreen and replace camera screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              scan: scan,
              allProbabilities: allProbabilities,
              rawPredictions: inferenceResult.predictions,
              rawHeatmap: gradCamResult.rawHeatmap,
              isSavedRecord: false,
              warningMessage: inferenceResult.warningMessage,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Full capture error: $e");
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog if shown
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error processing capture: $e")),
        );
        _setupCameraController(_cameras[_selectedCameraIndex]);
      }
    }
  }

  // Taps capture tree button: crops all detected leaf boxes from frame, runs inference on each, aggregates, and shows aggregation result
  Future<void> _captureAndAggregateMulti() async {
    if (_controller == null || !_controller!.value.isInitialized || _detectedLeafBoxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No leaves detected in screen bounds.")),
      );
      return;
    }

    setState(() {
      _guidanceMessage = "Extracting leaf segments...";
      _isProcessingInference = true;
    });

    try {
      _inferenceTimer?.cancel();
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final XFile imageFile = await _controller!.takePicture();
      final file = File(imageFile.path);

      if (!mounted) return;

      // Show processing overlay dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Processing multi-leaf crop..."),
            ],
          ),
        ),
      );

      final tfliteService = ref.read(tfliteServiceProvider);
      final gradCamService = ref.read(gradCamServiceProvider);

      // Run enhancement
      final enhancementService = ref.read(imageEnhancementServiceProvider);
      final enhancementEnabled = ref.read(imageEnhancementEnabledProvider);
      final enhancementStrength = ref.read(imageEnhancementStrengthProvider);
      
      final EnhancementResult enhancementResult = await enhancementService.enhanceImage(
        file,
        enabled: enhancementEnabled,
        strength: enhancementStrength,
      );
      
      final fileToAnalyze = enhancementResult.enhancedFile;

      final List<ScanModel> scans = [];
      final List<Map<String, double>> leafProbabilities = [];
      final List<List<List<double>>> leafHeatmaps = [];

      for (int i = 0; i < _detectedLeafBoxes.length; i++) {
        final box = _detectedLeafBoxes[i];
        
        // Crop the detected zone out of the full image
        final File croppedFile = await tfliteService.cropImage(
          fileToAnalyze,
          box.left,
          box.top,
          box.width,
          box.height,
        );

        // Crop unenhanced crop as well for comparison if enhanced
        File? unenhancedCropFile;
        if (enhancementResult.wasEnhanced) {
          try {
            unenhancedCropFile = await tfliteService.cropImage(
              file,
              box.left,
              box.top,
              box.width,
              box.height,
            );
          } catch (_) {}
        }

        // Run inference on crop
        final inferenceResult = await tfliteService.runInference(croppedFile, bypassIqa: true);

        // Parse class
        int predictedIndex = 0;
        double maxProb = -1.0;
        for (int k = 0; k < inferenceResult.predictions.length; k++) {
          if (inferenceResult.predictions[k] > maxProb) {
            maxProb = inferenceResult.predictions[k];
            predictedIndex = k;
          }
        }

        final int uiIndex = tfliteService.mapModelIndexToUiIndex(predictedIndex);
        final String rawClassName = tfliteService.labels[uiIndex];
        final double confidence = maxProb * 100.0;

        // Generate Grad-CAM for this leaf segment
        final gradCamResult = await gradCamService.generateGradCam(
          originalImageFile: croppedFile,
          predictedClassIndex: predictedIndex,
          diseaseName: rawClassName,
          featureMaps: inferenceResult.featureMaps,
          denseActivations: inferenceResult.denseActivations,
        );

        final scan = ScanModel(
          originalImagePath: croppedFile.path,
          overlayImagePath: gradCamResult.overlayImageFile.path,
          diseaseName: rawClassName,
          confidence: confidence,
          severity: gradCamResult.severity,
          inferenceTimeMs: inferenceResult.inferenceTime.inMilliseconds,
          createdAt: DateTime.now(),
          originalUnenhancedPath: unenhancedCropFile?.path,
        );

        final Map<String, double> probs = {};
        for (final label in tfliteService.labels) {
          probs[label.replaceAll('_', ' ')] = 0.0;
        }
        for (int k = 0; k < inferenceResult.predictions.length; k++) {
          final int mappingUiIndex = tfliteService.mapModelIndexToUiIndex(k);
          final label = tfliteService.labels[mappingUiIndex].replaceAll('_', ' ');
          probs[label] = inferenceResult.predictions[k] * 100.0;
        }

        scans.add(scan);
        leafProbabilities.add(probs);
        leafHeatmaps.add(gradCamResult.rawHeatmap);
      }

      // Pop loading dialog
      if (mounted) {
        Navigator.pop(context);

        // Open tree-level Aggregation screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AggregationResultScreen(
              parentImage: file,
              scans: scans,
              allProbabilitiesList: leafProbabilities,
              heatmaps: leafHeatmaps,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Multi-capture error: $e");
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Multi-leaf aggregation failed: $e")),
        );
        _setupCameraController(_cameras[_selectedCameraIndex]);
      }
    }
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final nextFlash = !_isFlashOn;
      await _controller!.setFlashMode(nextFlash ? FlashMode.torch : FlashMode.off);
      setState(() {
        _isFlashOn = nextFlash;
      });
    } catch (e) {
      debugPrint("Flash error: $e");
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    _inferenceTimer?.cancel();
    if (_controller != null) {
      // Discard image stream safely
      if (_controller!.value.isStreamingImages) {
        _controller!.stopImageStream();
      }
      _controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCameraPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text("Camera Access Denied")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, size: 72, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  _guidanceMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initializeCamera,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry Permissions"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Live Camera Preview
          Positioned.fill(
            child: _isCameraInitialized && _controller != null
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.greenAccent),
                        SizedBox(height: 16),
                        Text(
                          "Starting camera preview...",
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
          ),

          // 2. Custom Painter Overlays for Bounding Boxes
          if (_isCameraInitialized && _controller != null)
            Positioned.fill(
              child: CustomPaint(
                painter: LeafOverlayPainter(
                  boxes: _detectedLeafBoxes,
                  primaryLabel: _lastResultLabel,
                  confidence: _lastConfidence,
                ),
              ),
            ),

          // 3. Top HUD: Toolbar Controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 12,
                left: 12,
                right: 12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Live Scan Mode",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          "MokoGuard AI Engine Active",
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Flash toggle button
                  IconButton(
                    icon: Icon(
                      _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: _isFlashOn ? Colors.yellowAccent : Colors.white,
                    ),
                    onPressed: _toggleFlash,
                  ),
                  // Switch camera button
                  if (_cameras.length > 1)
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                      onPressed: _switchCamera,
                    ),
                ],
              ),
            ),
          ),

          // 4. Bottom HUD: Real-time Diagnostics & Shutter Buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(bottom: 24, top: 16, left: 16, right: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Suggestions & Feedback Card
                  GlassCard(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: 16.0,
                    blur: 20.0,
                    borderColor: _lastResultLabel != null && _lastResultLabel!.toLowerCase() != 'healthy'
                        ? Colors.redAccent.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.12),
                    borderWidth: 1.0,
                    padding: const EdgeInsets.all(16.0),
                    animateOnTap: false,
                    child: Column(
                      children: [
                        // Guidance Message
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _guidanceMessage.contains("Poor") || _guidanceMessage.contains("Move")
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline_outlined,
                              color: _guidanceMessage.contains("Poor") || _guidanceMessage.contains("Move")
                                  ? Colors.yellowAccent
                                  : Colors.greenAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _guidanceMessage,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_isEnhancedActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amberAccent, width: 0.5),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 10),
                                    SizedBox(width: 2),
                                    Text(
                                      "ENHANCED",
                                      style: TextStyle(
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 9,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 16),
                        
                        // Classification & Severity Display
                        if (_lastResultLabel != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Anomaly Class", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  Text(
                                    _lastResultLabel!.replaceAll('_', ' '),
                                    style: TextStyle(
                                      color: _lastResultLabel!.toLowerCase() == 'healthy'
                                          ? Colors.greenAccent
                                          : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text("Confidence", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  Text(
                                    "${_lastConfidence!.toStringAsFixed(1)}%",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("Severity", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _lastSeverity == 'High'
                                          ? Colors.red.withValues(alpha: 0.2)
                                          : _lastSeverity == 'Medium'
                                              ? Colors.orange.withValues(alpha: 0.2)
                                              : Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _lastSeverity ?? "Low",
                                      style: TextStyle(
                                        color: _lastSeverity == 'High'
                                            ? Colors.redAccent
                                            : _lastSeverity == 'Medium'
                                                ? Colors.orangeAccent
                                                : Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ] else ...[
                          const Text(
                            "Point your camera at a banana leaf",
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Floating Actions: Multi-Leaf Aggregator & Single Shutter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Multi-Leaf Aggregation Button
                      Opacity(
                        opacity: _detectedLeafBoxes.isNotEmpty ? 1.0 : 0.5,
                        child: FloatingActionButton.extended(
                          heroTag: "aggregate_fab",
                          backgroundColor: Colors.blueGrey[900],
                          foregroundColor: Colors.white,
                          onPressed: _detectedLeafBoxes.isNotEmpty ? _captureAndAggregateMulti : null,
                          icon: const Icon(Icons.photo_album_outlined, size: 20),
                          label: const Text("Capture Tree Diagnostics", style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      
                      // Core Capture & Analyze Shutter
                      GestureDetector(
                        onTap: _isProcessingInference ? null : _captureAndAnalyzeSingle,
                        child: Container(
                          height: 72,
                          width: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          child: Center(
                            child: _isProcessingInference
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Container(
                                    height: 54,
                                    width: 54,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LeafOverlayPainter extends CustomPainter {
  final List<Rect> boxes;
  final String? primaryLabel;
  final double? confidence;

  LeafOverlayPainter({
    required this.boxes,
    this.primaryLabel,
    this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < boxes.length; i++) {
      // Scale relative box coordinates to canvas preview dimensions
      final rect = Rect.fromLTWH(
        boxes[i].left * size.width,
        boxes[i].top * size.height,
        boxes[i].width * size.width,
        boxes[i].height * size.height,
      );

      // Draw box interior fill and border stroke
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        borderPaint,
      );

      // Construct dynamic label text for boxes
      final String labelText = i == 0 && primaryLabel != null
          ? 'Leaf #${i + 1}: ${primaryLabel!.replaceAll('_', ' ')} (${confidence?.toStringAsFixed(0)}%)'
          : 'Leaf #${i + 1}';

      textPainter.text = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          backgroundColor: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rect.left + 6, (rect.top - 18).clamp(8.0, size.height)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LeafOverlayPainter oldDelegate) {
    return oldDelegate.boxes != boxes ||
        oldDelegate.primaryLabel != primaryLabel ||
        oldDelegate.confidence != confidence;
  }
}
