import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/models/scan_model.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/tflite_service.dart';
import '../../scan/screens/result_screen.dart';
import '../../scan/screens/multi_leaf_selector.dart';
import '../../scan/screens/live_camera_screen.dart';
import '../../education/screens/education_guide_screen.dart';
import '../../analytics/screens/analytics_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_background.dart';

class AnimatedCounterText extends StatefulWidget {
  final int targetValue;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounterText({
    super.key,
    required this.targetValue,
    required this.style,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<AnimatedCounterText> createState() => _AnimatedCounterTextState();
}

class _AnimatedCounterTextState extends State<AnimatedCounterText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0.0, end: widget.targetValue.toDouble()).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetValue != widget.targetValue) {
      _controller.reset();
      _animation = Tween<double>(begin: 0.0, end: widget.targetValue.toDouble()).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          _animation.value.toInt().toString(),
          style: widget.style,
        );
      },
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isAnalyzing = false;
  int _touchedIndex = -1;
  int _currentIndex = 0;

  Future<void> _scanLeaf(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image == null) return;

    final file = File(image.path);
    if (!mounted) return;

    // Show Mode Selection Dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Analysis Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
            'Choose "Single Leaf Scan" to analyze the entire image instantly, or "Multi-Leaf Crop" to segment and scan multiple leaves in one frame.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _runSingleLeafAnalysis(file);
              },
              child: const Text('Single Leaf Scan'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MultiLeafSelector(imageFile: file),
                  ),
                );
              },
              child: const Text('Multi-Leaf Crop'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runSingleLeafAnalysis(File file, {bool bypassIqa = false}) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      // 1. Run local TFLite inference
      final tfliteService = ref.read(tfliteServiceProvider);
      
      // Apply Low-Light Enhancement if applicable
      final enhancementService = ref.read(imageEnhancementServiceProvider);
      final enhancementEnabled = ref.read(imageEnhancementEnabledProvider);
      final enhancementStrength = ref.read(imageEnhancementStrengthProvider);
      
      final enhancementResult = await enhancementService.enhanceImage(
        file,
        enabled: enhancementEnabled,
        strength: enhancementStrength,
      );
      
      final File fileToAnalyze = enhancementResult.enhancedFile;
      final inferenceResult = await tfliteService.runInference(fileToAnalyze, bypassIqa: bypassIqa);

      // Get predicted class index and name
      int predictedIndex = 0;
      double maxProb = -1.0;
      for (int i = 0; i < inferenceResult.predictions.length; i++) {
        if (inferenceResult.predictions[i] > maxProb) {
          maxProb = inferenceResult.predictions[i];
          predictedIndex = i;
        }
      }
      
      final int uiIndex = tfliteService.mapModelIndexToUiIndex(predictedIndex);
      final String rawClassName = tfliteService.labels[uiIndex];
      final double confidence = maxProb * 100.0;

      // 2. Generate on-device Grad-CAM heatmap overlay
      final gradCamService = ref.read(gradCamServiceProvider);
      final gradCamResult = await gradCamService.generateGradCam(
        originalImageFile: file,
        predictedClassIndex: predictedIndex, // Use the raw model index (0-5) for Grad-CAM weights mapping
        diseaseName: rawClassName,
        featureMaps: inferenceResult.featureMaps,
        denseActivations: inferenceResult.denseActivations,
      );

      if (!mounted) return;

      // Create a temporary ScanModel (not saved to DB yet)
      final tempScan = ScanModel(
        originalImagePath: fileToAnalyze.path,
        overlayImagePath: gradCamResult.overlayImageFile.path,
        diseaseName: rawClassName,
        confidence: confidence,
        severity: gradCamResult.severity,
        inferenceTimeMs: inferenceResult.inferenceTime.inMilliseconds,
        createdAt: DateTime.now(),
        originalUnenhancedPath: enhancementResult.wasEnhanced ? file.path : null,
      );

      // Create a map of all probabilities for the UI (must include all 7 classes)
      final Map<String, double> allProbabilities = {};
      for (final label in tfliteService.labels) {
        allProbabilities[label.replaceAll('_', ' ')] = 0.0;
      }
      for (int i = 0; i < inferenceResult.predictions.length; i++) {
        final int mappingUiIndex = tfliteService.mapModelIndexToUiIndex(i);
        final label = tfliteService.labels[mappingUiIndex].replaceAll('_', ' ');
        allProbabilities[label] = inferenceResult.predictions[i] * 100.0;
      }

      // Navigate to ResultScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            scan: tempScan,
            allProbabilities: allProbabilities,
            rawPredictions: inferenceResult.predictions,
            rawHeatmap: gradCamResult.rawHeatmap,
            isSavedRecord: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      if (e is IqaException) {
        // Show IQA warning dialog
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Text('Image Quality Warning', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text('${e.message}\n\nAnalyzing this photo may lead to inaccurate results. Would you like to proceed anyway?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Retake Photo'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _runSingleLeafAnalysis(file, bypassIqa: true);
                  },
                  child: const Text('Ignore & Analyze'),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('On-device analysis error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  void _showImageSourceSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select Image Source',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.videocam, color: Colors.green),
                  title: const Text('Live Camera Mode (Real-Time)'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LiveCameraScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.green),
                  title: const Text('Take Photo (Camera Capture)'),
                  onTap: () {
                    Navigator.pop(context);
                    _scanLeaf(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.green),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _scanLeaf(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeatherAlertBanner(ThemeData theme, bool isDark, ColorScheme colorScheme) {
    final locale = ref.watch(localeProvider);
    return GlassCard(
      borderRadius: 16,
      color: isDark ? const Color(0xFF2C1E1A).withValues(alpha: 0.4) : const Color(0xFFFFF3CD).withValues(alpha: 0.55),
      borderColor: isDark ? Colors.redAccent.withValues(alpha: 0.2) : Colors.orangeAccent.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(14.0),
      child: Row(
          children: [
            Icon(
              Icons.wb_sunny_rounded,
              color: isDark ? Colors.orangeAccent : Colors.orange[800],
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        getTranslation('weather_alert', locale),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.orangeAccent : Colors.orange[900],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HIGH',
                          style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    getTranslation('weather_desc', locale),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch database stats and history
    final statsAsync = ref.watch(statsProvider);
    final historyAsync = ref.watch(historyProvider);
    final distributionAsync = ref.watch(distributionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final locale = ref.watch(localeProvider);

    final List<Widget> tabs = [
      // Tab 0: Dashboard
      Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(historyProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 120.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome & Slogan
                    Text(
                      getTranslation('welcome_back', locale),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getTranslation('offline_intel', locale),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Weather-Based Risk Alert Banner
                    _buildWeatherAlertBanner(theme, isDark, colorScheme),
                    const SizedBox(height: 18),

                    // Stats Dashboard
                    statsAsync.when(
                      data: (stats) => _buildStatsDashboard(stats, distributionAsync),
                      loading: () => const Card(
                        child: SizedBox(
                          height: 250,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                      error: (err, _) => Card(
                        child: Center(child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Error loading stats: $err'),
                        )),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Primary Action Buttons
                    _buildActionButtons(),
                    const SizedBox(height: 28),

                    // Recent Detections Heading
                    Text(
                      getTranslation('recent_diagnostics', locale),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // History List
                    historyAsync.when(
                      data: (scans) => _buildRecentDetectionsList(scans),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Text('Error loading diagnostics: $err'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isAnalyzing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.green),
                        SizedBox(height: 20),
                        Text(
                          'Analyzing Leaf Offline...',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Executing TFLite Model & Grad-CAM',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      // Tab 1: Education
      const EducationGuideScreen(),
      // Tab 2: Analytics
      const AnalyticsScreen(),
      // Tab 3: Settings
      const SettingsScreen(),
    ];

    return Scaffold(
      extendBody: true, // Content flows dynamically behind the bottom floating glass bar
      appBar: _currentIndex == 0
          ? AppBar(
              title: const Text(
                'MokoGuard AI',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                  ),
                  tooltip: themeMode == ThemeMode.dark
                      ? 'Switch to Light Mode'
                      : 'Switch to Dark Mode',
                  onPressed: () {
                    ref.read(themeModeProvider.notifier).toggleTheme();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    _showAboutDialog();
                  },
                ),
              ],
            )
          : null,
      body: GlassBackground(
        child: IndexedStack(
          index: _currentIndex,
          children: tabs,
        ),
      ),
      bottomNavigationBar: _buildGlassBottomBar(context, locale, isDark, theme),
    );
  }

  Widget _buildGlassBottomBar(BuildContext context, String locale, bool isDark, ThemeData theme) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0),
      child: GlassCard(
        borderRadius: 24.0,
        blur: 20.0,
        color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.45),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        borderWidth: 1.2,
        padding: EdgeInsets.zero,
        animateOnTap: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final itemWidth = totalWidth / 4;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Shared Sliding Active Indicator Capsule
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  left: _currentIndex * itemWidth + 8,
                  width: itemWidth - 16,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withValues(alpha: 0.2),
                          theme.primaryColor.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.28),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),

                // Navigation Items Row
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.dashboard_outlined, Icons.dashboard, getTranslation('dashboard_tab', locale), theme),
                      _buildNavItem(1, Icons.menu_book_outlined, Icons.menu_book, getTranslation('guide_tab', locale), theme),
                      _buildNavItem(2, Icons.analytics_outlined, Icons.analytics, getTranslation('analytics_tab', locale), theme),
                      _buildNavItem(3, Icons.settings_outlined, Icons.settings, getTranslation('settings_tab', locale), theme),
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

  Widget _buildNavItem(int index, IconData unselectedIcon, IconData selectedIcon, String label, ThemeData theme) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? theme.primaryColor : Colors.grey;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedScale(
                  scale: isSelected ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    isSelected ? selectedIcon : unselectedIcon,
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsDashboard(Map<String, int> stats, AsyncValue<Map<String, int>> distributionAsync) {
    final int total = stats['total'] ?? 0;
    final int healthy = stats['healthy'] ?? 0;
    final int diseased = stats['diseased'] ?? 0;
    final int moko = stats['moko'] ?? 0;
    final locale = ref.watch(localeProvider);

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18.0),
      child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(getTranslation('total_scans', locale), total, Colors.blue),
                _buildStatItem(getTranslation('healthy', locale), healthy, Colors.green),
                _buildStatItem(getTranslation('diseased', locale), diseased, Colors.orange),
                _buildStatItem(getTranslation('moko_wilts', locale), moko, Colors.red),
              ],
            ),
            const Divider(height: 28, thickness: 0.8),
            Text(
              getTranslation('disease_dist', locale),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: distributionAsync.when(
                data: (dist) {
                  if (dist.isEmpty) {
                    return Center(
                      child: Text(
                        getTranslation('no_dist', locale),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    );
                  }
                  
                  int touchIdx = 0;
                  final sections = dist.entries.map((entry) {
                    final isTouched = touchIdx == _touchedIndex;
                    final double radius = isTouched ? 55.0 : 45.0;
                    final double fontSize = isTouched ? 15.0 : 11.0;
                    final color = _getColorForDisease(entry.key);
                    
                    final section = PieChartSectionData(
                      color: color,
                      value: entry.value.toDouble(),
                      title: '${entry.value}',
                      radius: radius,
                      titleStyle: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                    touchIdx++;
                    return section;
                  }).toList();

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2.5,
                            centerSpaceRadius: 32,
                            pieTouchData: PieTouchData(
                              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection == null) {
                                    _touchedIndex = -1;
                                    return;
                                  }
                                  _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            sections: sections,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: dist.entries.map((entry) {
                              final color = _getColorForDisease(entry.key);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${entry.key.replaceAll('_', ' ')} (${entry.value})',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        AnimatedCounterText(
          targetValue: value,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final locale = ref.watch(localeProvider);
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showImageSourceSelector,
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: Text(
              getTranslation('scan_leaf_btn', locale),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _showHistorySheet();
            },
            icon: const Icon(Icons.history_edu, size: 20),
            label: Text(
              getTranslation('full_history_btn', locale),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green[800],
              side: BorderSide(color: Colors.green[600]!, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentDetectionsList(List<ScanModel> scans) {
    final locale = ref.watch(localeProvider);
    if (scans.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.spa_outlined, color: Colors.grey[400], size: 36),
            const SizedBox(height: 8),
            Text(
              getTranslation('no_prev_diagnostics', locale),
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }

    final recentScans = scans.take(4).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentScans.length,
      itemBuilder: (context, index) {
        final scan = recentScans[index];
        final file = File(scan.overlayImagePath);

        return GlassCard(
          borderRadius: 12,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.only(bottom: 12),
          onTap: () {
            _openSavedResultScreen(scan);
          },
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: Colors.grey[200],
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : const Icon(Icons.image),
              ),
            ),
            title: Text(
              scan.diseaseName.replaceAll('_', ' '),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Severity: ${scan.severity} • ${scan.confidence.toStringAsFixed(1)}% • ${DateFormat.yMMMd().format(scan.createdAt)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          ),
        );
      },
    );
  }

  void _openSavedResultScreen(ScanModel scan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          scan: scan,
          allProbabilities: const {},
          rawPredictions: const [],
          rawHeatmap: const [],
          isSavedRecord: true,
        ),
      ),
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, _) {
                final historyAsync = ref.watch(historyProvider);
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'All Diagnostic History',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              _confirmClearHistory(ref);
                            },
                            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: historyAsync.when(
                          data: (scans) {
                            if (scans.isEmpty) {
                              return const Center(
                                child: Text('No diagnostics recorded in database.'),
                              );
                            }
                            return ListView.builder(
                              controller: scrollController,
                              itemCount: scans.length,
                              itemBuilder: (context, index) {
                                final scan = scans[index];
                                final file = File(scan.overlayImagePath);
                                return Dismissible(
                                  key: Key('scan_${scan.id}'),
                                  background: Container(
                                    color: Colors.redAccent,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (_) {
                                    if (scan.id != null) {
                                      ref.read(historyProvider.notifier).deleteScan(scan.id!);
                                    }
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    child: ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: file.existsSync()
                                              ? Image.file(file, fit: BoxFit.cover)
                                              : const Icon(Icons.image),
                                        ),
                                      ),
                                      title: Text(scan.diseaseName.replaceAll('_', ' ')),
                                      subtitle: Text(
                                        '${scan.severity} • ${scan.confidence.toStringAsFixed(1)}% • ${DateFormat.yMd().add_jm().format(scan.createdAt)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _openSavedResultScreen(scan);
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text('Error: $err')),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _confirmClearHistory(WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear All History?'),
          content: const Text('Are you sure you want to permanently delete all scan records? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref.read(historyProvider.notifier).clearAll();
                Navigator.pop(context);
              },
              child: const Text('Delete All', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'MokoGuard AI',
      applicationVersion: '1.0.0 (Offline & Explainable)',
      applicationIcon: Icon(Icons.spa, color: Colors.green[600], size: 40),
      children: [
        const SizedBox(height: 12),
        const Text(
          'MokoGuard AI is an offline Android mobile application designed to detect banana diseases (such as Moko Disease and Panama Disease) using deep learning and Explainable AI (Grad-CAM).\n\nAll computation, database storage, and PDF report generation occur strictly on-device without any cloud or internet connection.',
          style: TextStyle(fontSize: 13),
        ),
      ],
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
