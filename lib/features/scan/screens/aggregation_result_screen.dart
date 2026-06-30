import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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

class AggregationResultScreen extends ConsumerStatefulWidget {
  final File parentImage;
  final List<ScanModel> scans;
  final List<Map<String, double>> allProbabilitiesList;
  final List<List<List<double>>> heatmaps;

  const AggregationResultScreen({
    super.key,
    required this.parentImage,
    required this.scans,
    required this.allProbabilitiesList,
    required this.heatmaps,
  });

  @override
  ConsumerState<AggregationResultScreen> createState() => _AggregationResultScreenState();
}

class _AggregationResultScreenState extends ConsumerState<AggregationResultScreen> {
  bool _isSaved = false;
  bool _metadataLoading = true;
  String _aggDisease = "";
  double _aggConfidence = 0.0;
  String _aggSeverity = "Low";
  String _aggScientificName = "";
  String _aggDescription = "";
  List<String> _aggRecommendations = [];

  @override
  void initState() {
    super.initState();
    _calculateAggregates();
  }

  Future<void> _calculateAggregates() async {
    // 1. Calculate average probabilities across all leaves
    final Map<String, double> sumProbs = {};
    int count = widget.allProbabilitiesList.length;

    for (var probs in widget.allProbabilitiesList) {
      probs.forEach((key, val) {
        sumProbs[key] = (sumProbs[key] ?? 0.0) + val;
      });
    }

    final Map<String, double> avgProbs = {};
    String maxDisease = "";
    double maxVal = -1.0;

    sumProbs.forEach((key, val) {
      double avg = val / count;
      avgProbs[key] = avg;
      if (avg > maxVal) {
        maxVal = avg;
        maxDisease = key;
      }
    });

    // Replace spaces back to underscores to match database/rule format
    final String formattedDisease = maxDisease.replaceAll(' ', '_');

    // 2. Determine average severity level
    int highCount = 0;
    int mediumCount = 0;
    for (var scan in widget.scans) {
      if (scan.severity.toLowerCase() == 'high') {
        highCount++;
      } else if (scan.severity.toLowerCase() == 'medium') {
        mediumCount++;
      }
    }

    String avgSeverity = "Low";
    if (highCount >= count / 2.0) {
      avgSeverity = "High";
    } else if ((highCount + mediumCount) >= count / 2.0) {
      avgSeverity = "Medium";
    }

    setState(() {
      _aggDisease = formattedDisease;
      _aggConfidence = maxVal;
      _aggSeverity = avgSeverity;
    });

    // 3. Load disease details & recommendations from JSON configs
    try {
      final String diseasesString = await rootBundle.loadString('assets/models/diseases.json');
      final List<dynamic> diseasesData = jsonDecode(diseasesString);
      
      final diseaseInfo = diseasesData.firstWhere(
        (element) => element['id'].toString().toLowerCase() == formattedDisease.toLowerCase(),
        orElse: () => null,
      );

      final String rulesString = await rootBundle.loadString('assets/models/rules.json');
      final Map<String, dynamic> rulesData = jsonDecode(rulesString);

      List<String> recs = [];
      if (rulesData.containsKey(formattedDisease)) {
        final diseaseRules = rulesData[formattedDisease] as Map<String, dynamic>;
        if (diseaseRules.containsKey(avgSeverity)) {
          recs = List<String>.from(diseaseRules[avgSeverity]);
        }
      }

      setState(() {
        if (diseaseInfo != null) {
          _aggScientificName = diseaseInfo['scientificName'] ?? '';
          _aggDescription = diseaseInfo['description'] ?? '';
        } else {
          _aggScientificName = 'Musa spp.';
          _aggDescription = 'Diagnostic aggregation completed.';
        }
        _aggRecommendations = recs;
        _metadataLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading aggregated metadata: $e");
      setState(() {
        _metadataLoading = false;
      });
    }
  }

  Future<void> _saveTreeToHistory() async {
    if (_isSaved) return;
    try {
      // Save each individual leaf scan to the local database to record detailed diagnostics
      for (var scan in widget.scans) {
        await ref.read(historyProvider.notifier).addScan(scan);
      }
      setState(() {
        _isSaved = true;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All leaf scans saved to history successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save tree records: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _exportTreeReport() async {
    try {
      await ref.read(pdfServiceProvider).generateAndPrintTreeReport(
        parentImage: widget.parentImage,
        scans: widget.scans,
        aggDisease: _aggDisease,
        aggScientificName: _aggScientificName,
        aggConfidence: _aggConfidence,
        aggSeverity: _aggSeverity,
        aggDescription: _aggDescription,
        aggRecommendations: _aggRecommendations,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF Tree Report generation failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(getTranslation('tree_level_diagnosis', locale), style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      // Tree Header Summary Card
                      _buildTreeSummaryHeader(),
                      const SizedBox(height: 20),
  
                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSaved ? null : _saveTreeToHistory,
                              icon: Icon(_isSaved ? Icons.check : Icons.bookmark_add),
                              label: Text(_isSaved ? getTranslation('tree_saved', locale) : getTranslation('save_tree_to_history', locale)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            onPressed: _exportTreeReport,
                            icon: const Icon(Icons.picture_as_pdf),
                            tooltip: getTranslation('export_aggregated_report', locale),
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
  
                      // Leaf List Heading
                      Text(
                        getTranslation('individual_leaf_breakdown', locale),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
  
                      // Leaf Grid/List
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.scans.length,
                        itemBuilder: (context, index) {
                          final scan = widget.scans[index];
                          return _buildLeafDetailCard(index, scan);
                        },
                      ),
                      const SizedBox(height: 24),
  
                      // Aggregated Guidelines
                      Text(
                        getTranslation('tree_level_action', locale),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildAggregatedRecommendationsList(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTreeSummaryHeader() {
    final locale = ref.watch(localeProvider);
    return GlassCard(
      borderRadius: 20.0,
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  widget.parentImage,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getTranslation('disease_$_aggDisease', locale),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _getColorForDisease(_aggDisease),
                      ),
                    ),
                    Text(
                      _aggScientificName,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildSeverityChip(_aggSeverity),
                        const SizedBox(width: 8),
                        Text(
                          '${getTranslation('confidence', locale)}: ${_aggConfidence.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Text(
            _aggDescription,
            style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildLeafDetailCard(int index, ScanModel scan) {
    final locale = ref.watch(localeProvider);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 16.0,
      padding: const EdgeInsets.all(12.0),
      onTap: () => _showLeafDetailSheet(index, scan),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 70,
              height: 70,
              child: SeverityOverlay(
                imageFile: File(scan.originalImagePath),
                rawHeatmap: widget.heatmaps[index],
                diseaseName: scan.diseaseName,
                baseOpacity: 0.5,
                showGradCam: true,
                showSeverityMask: true,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getTranslation('leaf_crop_num', locale).replaceAll('{number}', '${index + 1}'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  getTranslation('disease_${scan.diseaseName}', locale),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _getColorForDisease(scan.diseaseName),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${getTranslation('confidence', locale)}: ${scan.confidence.toStringAsFixed(1)}% • ${getTranslation('latency', locale)}: ${scan.inferenceTimeMs} ms',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          _buildSeverityChip(scan.severity),
        ],
      ),
    );
  }

  void _showLeafDetailSheet(int index, ScanModel scan) {
    final Map<String, double> probs = widget.allProbabilitiesList[index];
    final List<List<double>> heatmap = widget.heatmaps[index];
    
    double sheetOpacity = 0.55;
    int sheetViewMode = 3; // Combined default

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool sheetShowEnhanced = true;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bool showGradCam = sheetViewMode == 1 || sheetViewMode == 3;
            final bool showSeverityMask = sheetViewMode == 2 || sheetViewMode == 3;
            final String baseImgPath = (sheetShowEnhanced || scan.originalUnenhancedPath == null)
                ? scan.originalImagePath
                : scan.originalUnenhancedPath!;
            
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.black.withValues(alpha: 0.65) 
                        : Colors.white.withValues(alpha: 0.65),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                      top: BorderSide(
                        color: isDark 
                            ? Colors.white.withValues(alpha: 0.12) 
                            : Colors.white.withValues(alpha: 0.32),
                        width: 1.5,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Pull Handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.grey[400],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              getTranslation('leaf_crop_details', ref.watch(localeProvider)).replaceAll('{number}', '${index + 1}'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // View Selector Row
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                 _buildSheetSegmentButton(0, getTranslation('view_mode_original', ref.watch(localeProvider)), sheetViewMode, (val) => setSheetState(() => sheetViewMode = val)),
                                 _buildSheetSegmentButton(1, getTranslation('view_mode_gradcam', ref.watch(localeProvider)), sheetViewMode, (val) => setSheetState(() => sheetViewMode = val)),
                                 _buildSheetSegmentButton(2, getTranslation('view_mode_severity', ref.watch(localeProvider)), sheetViewMode, (val) => setSheetState(() { sheetShowEnhanced = true; sheetViewMode = val; })),
                                 _buildSheetSegmentButton(3, getTranslation('view_mode_combined', ref.watch(localeProvider)), sheetViewMode, (val) => setSheetState(() { sheetShowEnhanced = true; sheetViewMode = val; })),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Severity Overlay Viewport
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: 200,
                            child: SeverityOverlay(
                              imageFile: File(baseImgPath),
                              rawHeatmap: heatmap,
                              diseaseName: scan.diseaseName,
                              baseOpacity: sheetOpacity,
                              showGradCam: showGradCam,
                              showSeverityMask: showSeverityMask,
                            ),
                          ),
                        ),
                        
                        // Compare Switch Row
                        if (scan.originalUnenhancedPath != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.compare_rounded, color: Colors.green, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    "Compare Original vs Enhanced",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                  sheetShowEnhanced ? getTranslation('low_light_badge', ref.watch(localeProvider)) : getTranslation('view_mode_original', ref.watch(localeProvider)),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: sheetShowEnhanced ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Switch(
                                    value: sheetShowEnhanced,
                                    activeThumbColor: Colors.green,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (val) {
                                      setSheetState(() {
                                        sheetShowEnhanced = val;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Opacity Slider
                        if (sheetViewMode != 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(getTranslation('overlay_opacity', ref.watch(localeProvider)), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Text('${(sheetOpacity * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          Slider(
                            value: sheetOpacity,
                            min: 0.3,
                            max: 0.8,
                            divisions: 5,
                            activeColor: Colors.green,
                            onChanged: (val) {
                              setSheetState(() {
                                sheetOpacity = val;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Stats Details GlassCard
                        GlassCard(
                          borderRadius: 12.0,
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      getTranslation('disease_${scan.diseaseName}', ref.watch(localeProvider)),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: _getColorForDisease(scan.diseaseName),
                                      ),
                                    ),
                                  _buildSeverityChip(scan.severity),
                                ],
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                   _buildInfoDetail(getTranslation('confidence', ref.watch(localeProvider)), '${scan.confidence.toStringAsFixed(1)}%'),
                                   _buildInfoDetail(getTranslation('latency', ref.watch(localeProvider)), '${scan.inferenceTimeMs} ms'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Probabilities List
                         Text(getTranslation('probability_distribution', ref.watch(localeProvider)), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        ...probs.entries.map((entry) {
                          final double percent = entry.value;
                          final isHighest = entry.key.toLowerCase() == scan.diseaseName.replaceAll('_', ' ').toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        color: isHighest ? Colors.green[700] : Colors.grey[700],
                                        fontSize: 12,
                                        fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      '${percent.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        color: isHighest ? Colors.green[700] : Colors.grey[700],
                                        fontSize: 12,
                                        fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                LinearProgressIndicator(
                                  value: percent / 100.0,
                                  backgroundColor: Colors.grey[200],
                                  color: isHighest ? Colors.green : Colors.grey[400],
                                  minHeight: 4,
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                        FeedbackWidget(scan: scan),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetSegmentButton(int index, String label, int currentMode, Function(int) onSelected) {
    final bool isSelected = currentMode == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => onSelected(index),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected 
              ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.white) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected 
                ? (isDark ? Colors.white : Colors.black87) 
                : (isDark ? Colors.white38 : Colors.grey[600]),
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoDetail(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSeverityChip(String severity) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color color = isDark ? const Color(0xFF29B6F6) : const Color(0xFF0288D1); // Default to low
    if (severity.toLowerCase() == 'high') {
      color = isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F);
    } else if (severity.toLowerCase() == 'medium') {
      color = isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        getTranslation('severity_$severity', ref.watch(localeProvider)).toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildAggregatedRecommendationsList() {
    if (_aggRecommendations.isEmpty) {
      return GlassCard(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: 12.0,
        child: const Text(
          'Tree condition stable. Continue standard organic maintenance and monitoring.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    return Column(
      children: _aggRecommendations.map((rec) {
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          borderRadius: 12.0,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.eco, color: Colors.green[600], size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rec,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
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
