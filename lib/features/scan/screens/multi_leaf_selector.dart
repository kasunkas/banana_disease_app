import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/providers.dart';
import '../../../core/models/scan_model.dart';
import 'aggregation_result_screen.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_background.dart';



class CropBox {
  double left; // 0.0 to 1.0 (relative)
  double top;  // 0.0 to 1.0 (relative)
  double width; // 0.0 to 1.0 (relative)
  double height; // 0.0 to 1.0 (relative)

  CropBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class MultiLeafSelector extends ConsumerStatefulWidget {
  final File imageFile;

  const MultiLeafSelector({super.key, required this.imageFile});

  @override
  ConsumerState<MultiLeafSelector> createState() => _MultiLeafSelectorState();
}

class _MultiLeafSelectorState extends ConsumerState<MultiLeafSelector> {
  final List<CropBox> _cropBoxes = [];
  bool _isProcessing = false;
  String _loadingMessage = "";

  @override
  void initState() {
    super.initState();
    // Add one default crop box at the center
    _cropBoxes.add(CropBox(left: 0.25, top: 0.25, width: 0.5, height: 0.5));
  }

  void _addCropBox() {
    if (_cropBoxes.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum of 5 leaves can be analyzed in one frame.')),
      );
      return;
    }
    setState(() {
      _cropBoxes.add(CropBox(
        left: 0.3,
        top: 0.3,
        width: 0.4,
        height: 0.4,
      ));
    });
  }

  void _removeCropBox(int index) {
    if (_cropBoxes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one leaf box must be defined for analysis.')),
      );
      return;
    }
    setState(() {
      _cropBoxes.removeAt(index);
    });
  }

  Future<void> _processTree() async {
    setState(() {
      _isProcessing = true;
      _loadingMessage = "Cropping individual leaves...";
    });

    try {
      final tfliteService = ref.read(tfliteServiceProvider);
      final gradCamService = ref.read(gradCamServiceProvider);

      final List<File> croppedFiles = [];
      final List<ScanModel> scans = [];
      final List<Map<String, double>> leafProbabilities = [];
      final List<List<List<double>>> leafHeatmaps = [];

      for (int i = 0; i < _cropBoxes.length; i++) {
        setState(() {
          _loadingMessage = "Analyzing leaf crop ${i + 1} of ${_cropBoxes.length}...";
        });

        final box = _cropBoxes[i];
        
        // 1. Crop image using native graphics
        final File croppedFile = await tfliteService.cropImage(
          widget.imageFile,
          box.left,
          box.top,
          box.width,
          box.height,
        );
        croppedFiles.add(croppedFile);

        // 2. Run inference on the crop
        // IQA is bypassed for user-cropped regions because they are sub-regions of an already vetted frame
        final inferenceResult = await tfliteService.runInference(croppedFile, bypassIqa: true);

        // Get predicted class details
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

        // 3. Generate Grad-CAM on crop
        final gradCamResult = await gradCamService.generateGradCam(
          originalImageFile: croppedFile,
          predictedClassIndex: predictedIndex, // Use the raw model index (0-5) for Grad-CAM weights mapping
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
        );

        final Map<String, double> probs = {};
        // Initialize all UI labels to 0.0%
        for (final label in tfliteService.labels) {
          probs[label.replaceAll('_', ' ')] = 0.0;
        }
        // Populate probabilities from model predictions
        for (int k = 0; k < inferenceResult.predictions.length; k++) {
          final int mappingUiIndex = tfliteService.mapModelIndexToUiIndex(k);
          final label = tfliteService.labels[mappingUiIndex].replaceAll('_', ' ');
          probs[label] = inferenceResult.predictions[k] * 100.0;
        }

        scans.add(scan);
        leafProbabilities.add(probs);
        leafHeatmaps.add(gradCamResult.rawHeatmap);
      }

      if (!mounted) return;

      // Navigate to Tree Aggregation Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AggregationResultScreen(
            parentImage: widget.imageFile,
            scans: scans,
            allProbabilitiesList: leafProbabilities,
            heatmaps: leafHeatmaps,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tree-level processing error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Multi-Leaf Crop Selector', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: GlassBackground(
        child: _isProcessing
            ? Center(
                child: GlassCard(
                  borderRadius: 16.0,
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.green),
                      const SizedBox(height: 20),
                      Text(
                        _loadingMessage,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Processing completely offline on-device',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final displayWidth = constraints.maxWidth;
                  // Leave space for buttons at the bottom
                  final displayHeight = constraints.maxHeight - 120;

                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: displayWidth,
                            height: displayHeight,
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Base Image
                                  Image.file(
                                    widget.imageFile,
                                    fit: BoxFit.contain,
                                    width: displayWidth,
                                    height: displayHeight,
                                  ),
                                  // Crop boxes overlay
                                  ...List.generate(_cropBoxes.length, (index) {
                                    final box = _cropBoxes[index];
                                    return _buildCropBoxWidget(
                                      index: index,
                                      box: box,
                                      maxWidth: displayWidth - 24, // accounting for margins
                                      maxHeight: displayHeight - 24,
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Action Buttons at the bottom
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addCropBox,
                                icon: const Icon(Icons.add_box_outlined),
                                label: const Text('Add Crop Box'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: const BorderSide(color: Colors.green, width: 1.5),
                                  foregroundColor: Colors.green[800],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _processTree,
                                icon: const Icon(Icons.psychology),
                                label: Text('Analyze Tree (${_cropBoxes.length})'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCropBoxWidget({
    required int index,
    required CropBox box,
    required double maxWidth,
    required double maxHeight,
  }) {
    // Convert relative coordinates to screen coordinates
    double leftPx = box.left * maxWidth;
    double topPx = box.top * maxHeight;
    double widthPx = box.width * maxWidth;
    double heightPx = box.height * maxHeight;

    const double minBoxSize = 50.0;
    const double handleSize = 24.0;

    return Positioned(
      left: leftPx,
      top: topPx,
      width: widthPx,
      height: heightPx,
      child: Stack(
        children: [
          // The Crop Area Container
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                // Drag the entire box
                box.left = (box.left + (details.delta.dx / maxWidth)).clamp(0.0, 1.0 - box.width);
                box.top = (box.top + (details.delta.dy / maxHeight)).clamp(0.0, 1.0 - box.height);
              });
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2.5),
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                    onPressed: () => _removeCropBox(index),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ),
          ),
          // Resizing Handle (Bottom Right)
          Positioned(
            right: 0,
            bottom: 0,
            width: handleSize,
            height: handleSize,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  double newWidth = (widthPx + details.delta.dx) / maxWidth;
                  double newHeight = (heightPx + details.delta.dy) / maxHeight;

                  box.width = newWidth.clamp(minBoxSize / maxWidth, 1.0 - box.left);
                  box.height = newHeight.clamp(minBoxSize / maxHeight, 1.0 - box.top);
                });
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: const Icon(
                  Icons.drag_handle,
                  size: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          // Index Tag (Top Left)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L${index + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
