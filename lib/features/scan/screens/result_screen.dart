import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scan_model.dart';
import '../../../core/services/providers.dart';
import '../widgets/severity_overlay.dart';
import '../widgets/feedback_widget.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_background.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final ScanModel scan;
  final Map<String, double> allProbabilities;
  final List<double> rawPredictions;
  final List<List<double>> rawHeatmap;
  final bool isSavedRecord;
  final String? warningMessage;

  const ResultScreen({
    super.key,
    required this.scan,
    required this.allProbabilities,
    required this.rawPredictions,
    required this.rawHeatmap,
    required this.isSavedRecord,
    this.warningMessage,
  });

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  int _selectedViewMode = 3; // 0 = Original, 1 = Grad-CAM, 2 = Severity, 3 = Combined
  double _opacity = 0.55;
  bool _showResearchMode = false;
  bool _metadataLoading = true;
  bool _isSaved = false;
  bool _showEnhancedImage = true;

  String _scientificName = "";
  String _description = "";
  List<String> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSavedRecord;
    _showResearchMode = ref.read(researchModeProvider);
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      // Load diseases.json
      final String diseasesString = await rootBundle.loadString('assets/models/diseases.json');
      final List<dynamic> diseasesData = jsonDecode(diseasesString);
      
      final diseaseInfo = diseasesData.firstWhere(
        (element) => element['id'].toString().toLowerCase() == widget.scan.diseaseName.toLowerCase(),
        orElse: () => null,
      );

      // Load rules.json
      final String rulesString = await rootBundle.loadString('assets/models/rules.json');
      final Map<String, dynamic> rulesData = jsonDecode(rulesString);

      List<String> recs = [];
      if (rulesData.containsKey(widget.scan.diseaseName)) {
        final diseaseRules = rulesData[widget.scan.diseaseName] as Map<String, dynamic>;
        if (diseaseRules.containsKey(widget.scan.severity)) {
          recs = List<String>.from(diseaseRules[widget.scan.severity]);
        }
      }

      setState(() {
        if (diseaseInfo != null) {
          _scientificName = diseaseInfo['scientificName'] ?? '';
          _description = diseaseInfo['description'] ?? '';
        } else {
          _scientificName = 'Musa spp.';
          _description = 'Information currently unavailable.';
        }
        _recommendations = recs;
        _metadataLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading metadata in ResultScreen: $e");
      setState(() {
        _metadataLoading = false;
      });
    }
  }

  Future<void> _saveToHistory() async {
    if (_isSaved) return;
    try {
      await ref.read(historyProvider.notifier).addScan(widget.scan);
      setState(() {
        _isSaved = true;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to history successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save record: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _exportReport() async {
    try {
      await ref.read(pdfServiceProvider).generateAndPrintReport(
        scan: widget.scan,
        scientificName: _scientificName,
        description: _description,
        recommendations: _recommendations,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF generation failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(getTranslation('diagnostic_results', locale), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: GlassBackground(
        child: _metadataLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.warningMessage != null && widget.warningMessage!.isNotEmpty) ...[
                      GlassCard(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: 12.0,
                        borderColor: Colors.amber.withValues(alpha: 0.5),
                        borderWidth: 1.5,
                        padding: const EdgeInsets.all(14.0),
                        animateOnTap: false,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Borderline Severity Warning',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.warningMessage!,
                                    style: TextStyle(
                                      fontSize: 12.0,
                                      height: 1.35,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.scan.originalUnenhancedPath != null) ...[
                      GlassCard(
                        color: Colors.amber.withValues(alpha: 0.06),
                        borderRadius: 12.0,
                        borderColor: Colors.amber.withValues(alpha: 0.25),
                        borderWidth: 1.0,
                        padding: const EdgeInsets.all(12.0),
                        animateOnTap: false,
                        child: Row(
                          children: [
                            const Icon(Icons.wb_sunny_rounded, color: Colors.amber),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    getTranslation('low_light_title', locale),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    getTranslation('low_light_desc', locale),
                                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Image Toggle Control (Original, Grad-CAM, Severity, Combined)
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSegmentButton(0, getTranslation('view_mode_original', locale)),
                            if (!widget.isSavedRecord && widget.rawHeatmap.isNotEmpty) ...[
                              _buildSegmentButton(1, getTranslation('view_mode_gradcam', locale)),
                              _buildSegmentButton(2, getTranslation('view_mode_severity', locale)),
                              _buildSegmentButton(3, getTranslation('view_mode_combined', locale)),
                            ] else ...[
                              _buildSegmentButton(2, getTranslation('view_mode_overlay', locale)),
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Animated Hero Image Display Box
                    Stack(
                      children: [
                        Hero(
                          tag: 'scan_image_${widget.scan.id ?? widget.scan.createdAt.millisecondsSinceEpoch}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 280,
                              color: Colors.black12,
                              child: _buildImageDisplayWidget(),
                            ),
                          ),
                        ),
                        // Low Light Badge overlay
                        if (widget.scan.originalUnenhancedPath != null)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amberAccent, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    getTranslation('low_light_badge', locale),
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    if (widget.scan.originalUnenhancedPath != null) ...[
                      const SizedBox(height: 12),
                      GlassCard(
                        borderRadius: 12.0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.compare_rounded, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    getTranslation('compare_original_enhanced', locale),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                    _showEnhancedImage ? getTranslation('low_light_badge', locale) : getTranslation('view_mode_original', locale),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _showEnhancedImage ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: _showEnhancedImage,
                                    activeThumbColor: Colors.green,
                                    onChanged: (val) {
                                      setState(() {
                                        _showEnhancedImage = val;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Opacity & Legend Controls (only if view mode is not Original and raw heatmap is available)
                    if (_selectedViewMode != 0 && widget.rawHeatmap.isNotEmpty) ...[
                      _buildOverlayControlsCard(),
                      const SizedBox(height: 16),
                    ],

                    // Primary Diagnoses Info Card
                    GlassCard(
                      borderRadius: 16.0,
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        getTranslation('disease_${widget.scan.diseaseName}', locale),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: _getColorForDisease(widget.scan.diseaseName),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _scientificName,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildSeverityChip(widget.scan.severity),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildInfoDetail(getTranslation('confidence', locale), '${widget.scan.confidence.toStringAsFixed(1)}%'),
                                _buildInfoDetail(getTranslation('latency', locale), '${widget.scan.inferenceTimeMs} ms'),
                                _buildInfoDetail(getTranslation('status', locale), _isSaved ? getTranslation('status_archived', locale) : getTranslation('status_temporary', locale)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Color-changing animated confidence indicator
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.0, end: widget.scan.confidence / 100.0),
                              duration: const Duration(milliseconds: 1000),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.grey[200],
                                  color: _getProgressColor(widget.scan.confidence),
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(10),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _description,
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[300] : Colors.grey[800], height: 1.4),
                            ),
                          ],
                        ),
                    ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaved ? null : _saveToHistory,
                            icon: Icon(_isSaved ? Icons.check : Icons.bookmark_add),
                            label: Text(_isSaved ? getTranslation('saved_to_history', locale) : getTranslation('save_to_history', locale)),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: _exportReport,
                          icon: const Icon(Icons.picture_as_pdf),
                          tooltip: getTranslation('export_pdf_report', locale),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Expandable Recommendations Section
                    Text(
                      getTranslation('treatment_recommendations', locale),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildRecommendationsList(),
                    const SizedBox(height: 28),

                    // Research Mode Toggle (Only if predictions/heatmap are available)
                    if (!widget.isSavedRecord && widget.rawPredictions.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            getTranslation('enable_research_mode', locale),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Switch.adaptive(
                            value: _showResearchMode,
                            activeThumbColor: Colors.green,
                            onChanged: (val) {
                              setState(() {
                                _showResearchMode = val;
                              });
                            },
                          ),
                        ],
                      ),
                      if (_showResearchMode) ...[
                        const SizedBox(height: 16),
                        _buildResearchModeUI(),
                      ],
                      const SizedBox(height: 24),
                      FeedbackWidget(scan: widget.scan),
                      const SizedBox(height: 40),
                    ]
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildImageDisplayWidget() {
    final String baseImagePath = (_showEnhancedImage || widget.scan.originalUnenhancedPath == null)
        ? widget.scan.originalImagePath
        : widget.scan.originalUnenhancedPath!;

    if (widget.rawHeatmap.isEmpty) {
      // Fallback for saved records where raw heatmap is not available
      final String imagePath = _selectedViewMode == 0
          ? baseImagePath
          : widget.scan.overlayImagePath;
      final File imageFile = File(imagePath);
      if (imageFile.existsSync()) {
        return Image.file(imageFile, fit: BoxFit.cover, width: double.infinity);
      } else {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Image file not found on device', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }
    }

    final bool showGradCam = _selectedViewMode == 1 || _selectedViewMode == 3;
    final bool showSeverityMask = _selectedViewMode == 2 || _selectedViewMode == 3;
    final File imageFile = File(baseImagePath);

    return SeverityOverlay(
      imageFile: imageFile,
      rawHeatmap: widget.rawHeatmap,
      diseaseName: widget.scan.diseaseName,
      baseOpacity: _opacity,
      showGradCam: showGradCam,
      showSeverityMask: showSeverityMask,
    );
  }

  Color _getProgressColor(double confidence) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (confidence >= 75.0) {
      return isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
    } else if (confidence >= 45.0) {
      return isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);
    } else {
      return isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F);
    }
  }

  Widget _buildOverlayControlsCard() {
    final locale = ref.watch(localeProvider);
    return GlassCard(
      borderRadius: 16.0,
      padding: const EdgeInsets.all(16.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  getTranslation('overlay_opacity', locale),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${(_opacity * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                ),
              ],
            ),
            Slider(
              value: _opacity,
              min: 0.3,
              max: 0.8,
              divisions: 5,
              activeColor: Colors.green,
              onChanged: (val) {
                setState(() {
                  _opacity = val;
                });
              },
            ),
            const Divider(height: 20),
            Text(
              getTranslation('severity_legend', locale),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildLegendItem(Colors.greenAccent, getTranslation('legend_low', locale)),
                const SizedBox(width: 8),
                _buildLegendItem(Colors.amberAccent, getTranslation('legend_medium', locale)),
                const SizedBox(width: 8),
                _buildLegendItem(Colors.redAccent, getTranslation('legend_high', locale)),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton(int index, String label) {
    // If the raw heatmap is empty, force mode mapping for segment display
    final int mappedIndex = widget.rawHeatmap.isEmpty && index == 2 ? 2 : index;
    final bool isSelected = _selectedViewMode == mappedIndex;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedViewMode = mappedIndex;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected && !isDark
              ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white54 : Colors.grey[600]),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSeverityChip(String severity) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color color = isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32); // Low = Green
    if (severity.toLowerCase() == 'high') {
      color = isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F); // High = Red
    } else if (severity.toLowerCase() == 'medium') {
      color = isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800); // Medium = Amber
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        getTranslation('severity_$severity', ref.watch(localeProvider)).toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildInfoDetail(String label, String value) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsList() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (_recommendations.isEmpty) {
      return Card(
        color: Colors.green.withValues(alpha: 0.02),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No specific actions required. Maintain standard agricultural hygiene and monitor regularly.',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      );
    }

    return Column(
      children: _recommendations.map((rec) {
        final parts = rec.split('.');
        final title = parts[0];
        final details = parts.length > 1 ? parts.sublist(1).join('.').trim() : "";

        if (details.isEmpty) {
          return Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green[600], size: 18),
              title: Text(
                title,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          );
        }

        return Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Icon(Icons.check_circle_outline, color: Colors.green[600], size: 18),
            title: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 48.0, right: 16.0, bottom: 12.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    details,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[300] : Colors.grey[700], height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResearchModeUI() {
    return GlassCard(
      borderRadius: 16.0,
      color: Colors.blueGrey[900]?.withValues(alpha: 0.65),
      borderColor: Colors.tealAccent.withValues(alpha: 0.2),
      padding: const EdgeInsets.all(16.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.science_outlined, color: Colors.tealAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Research Analytics Mode',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),

            // Class Probabilities Chart
            const Text(
              'Model Class Probabilities:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...widget.allProbabilities.entries.map((entry) {
              final double percent = entry.value;
              final isHighest = entry.key.toLowerCase() == widget.scan.diseaseName.replaceAll('_', ' ').toLowerCase();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            color: isHighest ? Colors.greenAccent : Colors.white60,
                            fontSize: 11,
                            fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${percent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: isHighest ? Colors.greenAccent : Colors.white60,
                            fontSize: 11,
                            fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: percent / 100.0,
                      backgroundColor: Colors.white12,
                      color: isHighest ? Colors.greenAccent : Colors.tealAccent.withValues(alpha: 0.5),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),

            // 7x7 Grad-CAM Map Grid
            const Text(
              'Grad-CAM 7x7 Raw Activation Matrix:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: List.generate(7, (y) {
                    return Row(
                      children: List.generate(7, (x) {
                        final double val = widget.rawHeatmap[y][x];
                        final Color c = _getHeatmapColor(val).withValues(alpha: 0.8);
                        return Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              color: c,
                              alignment: Alignment.center,
                              child: Text(
                                val.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetadataValue('Architecture', 'MobileNetV2'),
                _buildMetadataValue('Input Shape', '224x224x3'),
                _buildMetadataValue('Model Size', '9.5 MB'),
              ],
            ),
          ],
        ),
    );
  }

  static Widget _buildMetadataValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Color _getHeatmapColor(double value) {
    if (value < 0.15) {
      return Colors.transparent;
    }
    double normalized = (value - 0.15) / 0.85;
    if (normalized < 0.25) {
      double t = normalized / 0.25;
      return Color.fromARGB(255, 0, (t * 255).toInt(), 255);
    } else if (normalized < 0.5) {
      double t = (normalized - 0.25) / 0.25;
      return Color.fromARGB(255, 0, 255, (255 * (1.0 - t)).toInt());
    } else if (normalized < 0.75) {
      double t = (normalized - 0.5) / 0.25;
      return Color.fromARGB(255, (t * 255).toInt(), 255, 0);
    } else {
      double t = (normalized - 0.75) / 0.25;
      return Color.fromARGB(255, 255, (255 * (1.0 - t)).toInt(), 0);
    }
  }

  Color _getColorForDisease(String diseaseName) {
    switch (diseaseName) {
      case 'Black_Sigatoka':
        return const Color(0xFF1B5E20);
      case 'Cordana':
        return const Color(0xFFFF9800);
      case 'Healthy':
        return const Color(0xFF4CAF50);
      case 'Panama_Disease':
        return const Color(0xFFD32F2F);
      case 'Moko_Disease':
        return const Color(0xFFD32F2F);
      case 'Pestalotiopsis':
        return const Color(0xFF8D6E63);
      case 'Yellow_Sigatoka':
        return const Color(0xFFFBC02D);
      default:
        return const Color(0xFFD32F2F);
    }
  }
}
