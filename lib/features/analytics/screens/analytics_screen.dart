import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/services/providers.dart';
import '../../../core/models/scan_model.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/widgets/glass_card.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final historyAsync = ref.watch(historyProvider);
    final researchMode = ref.watch(researchModeProvider);
    final feedbackStatsAsync = ref.watch(feedbackStatsProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: historyAsync.when(
        data: (scans) => _buildContent(context, ref, scans, isDark, colorScheme, theme, researchMode, feedbackStatsAsync, locale),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading analytics: $err')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<ScanModel> scans,
    bool isDark,
    ColorScheme colorScheme,
    ThemeData theme,
    bool researchMode,
    AsyncValue<Map<String, dynamic>> feedbackStatsAsync,
    String locale,
  ) {
    // 1. Calculate stats metrics
    final total = scans.length;
    final healthyCount = scans.where((s) => s.diseaseName == 'Healthy').length;
    final diseasedCount = total - healthyCount;
    final double healthyRate = total > 0 ? (healthyCount / total) * 100 : 0.0;
    
    // Average confidence calculation
    double avgConfidence = 0.0;
    if (total > 0) {
      double sum = scans.fold(0.0, (acc, scan) => acc + scan.confidence);
      avgConfidence = sum / total;
    }

    // Determine the most common disease
    String topDiseaseKey = "none";
    final Map<String, int> counts = {};
    if (total > 0 && diseasedCount > 0) {
      for (final scan in scans) {
        if (scan.diseaseName != 'Healthy') {
          counts[scan.diseaseName] = (counts[scan.diseaseName] ?? 0) + 1;
        }
      }
      if (counts.isNotEmpty) {
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        topDiseaseKey = 'disease_${sorted.first.key}';
      }
    }

    // Severity alert distribution
    int highSeverityCount = scans.where((s) => s.severity.toLowerCase() == 'high').length;
    String alertStatus = "LOW";
    Color alertColor = Colors.green;
    if (highSeverityCount > 0) {
      final double ratio = highSeverityCount / total;
      if (ratio > 0.3) {
        alertStatus = "CRITICAL";
        alertColor = Colors.redAccent;
      } else {
        alertStatus = "WARNING";
        alertColor = Colors.orangeAccent;
      }
    }

    final topDiseaseTranslated = getTranslation(topDiseaseKey, locale);
    final alertStatusTranslated = getTranslation('alert_status_${alertStatus.toLowerCase()}', locale);

    return Column(
      children: [
        // Top Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.38),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                getTranslation('analytics_title', locale),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                getTranslation('analytics_subtitle', locale),
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
              ),
            ],
          ),
        ),

        // Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 120.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Line Chart Card
                _buildLineChartCard(scans, isDark, colorScheme, theme, locale),
                const SizedBox(height: 20),

                // 2. Statistics Grid Title
                Text(
                  getTranslation('key_indicators', locale),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // 3. Grid of Stats Cards
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    _buildStatCard(
                      getTranslation('healthy_rate_card', locale),
                      '${healthyRate.toStringAsFixed(1)}%',
                      Icons.check_circle_rounded,
                      Colors.green,
                      isDark,
                      colorScheme,
                    ),
                    _buildStatCard(
                      getTranslation('primary_threat_card', locale),
                      topDiseaseTranslated,
                      Icons.warning_amber_rounded,
                      Colors.redAccent,
                      isDark,
                      colorScheme,
                    ),
                    _buildStatCard(
                      getTranslation('avg_confidence_card', locale),
                      '${avgConfidence.toStringAsFixed(1)}%',
                      Icons.psychology_rounded,
                      Colors.blueAccent,
                      isDark,
                      colorScheme,
                    ),
                    _buildStatCard(
                      getTranslation('alert_status_card', locale),
                      alertStatusTranslated,
                      Icons.notifications_active_rounded,
                      alertColor,
                      isDark,
                      colorScheme,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Insights Section
                _buildInsightsCard(scans, healthyRate, topDiseaseKey, alertStatus, isDark, colorScheme, theme, locale),
                
                // 5. Active Learning Insights (Only if Academic Research Mode is enabled)
                if (researchMode) ...[
                  const SizedBox(height: 20),
                  feedbackStatsAsync.when(
                    data: (stats) => _buildActiveLearningCard(stats, isDark, colorScheme, theme, locale),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineChartCard(
    List<ScanModel> scans,
    bool isDark,
    ColorScheme colorScheme,
    ThemeData theme,
    String locale,
  ) {
    // Group scans by date for the last 7 days
    final List<DateTime> last7Days = List.generate(7, (i) {
      final date = DateTime.now().subtract(Duration(days: 6 - i));
      return DateTime(date.year, date.month, date.day);
    });

    final Map<DateTime, int> dailyCounts = {for (var d in last7Days) d: 0};
    for (final scan in scans) {
      final scanDate = DateTime(scan.createdAt.year, scan.createdAt.month, scan.createdAt.day);
      if (dailyCounts.containsKey(scanDate)) {
        dailyCounts[scanDate] = dailyCounts[scanDate]! + 1;
      }
    }

    final List<FlSpot> spots = [];
    int maxCount = 4; // minimum upper bound for Y-axis
    for (int i = 0; i < last7Days.length; i++) {
      final count = dailyCounts[last7Days[i]] ?? 0;
      spots.add(FlSpot(i.toDouble(), count.toDouble()));
      if (count > maxCount) {
        maxCount = count;
      }
    }

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              getTranslation('weekly_volume', locale),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              getTranslation('weekly_volume_desc', locale),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: isDark ? const Color(0xFF333333) : const Color(0xFFEAEAEA),
                      strokeWidth: 1.0,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (val, meta) {
                          if (val % 1 != 0) return const SizedBox.shrink();
                          return Text(
                            val.toInt().toString(),
                            style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < last7Days.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                DateFormat('E').format(last7Days[idx]),
                                style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: maxCount.toDouble() + 1.0,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: colorScheme.primary,
                      barWidth: 3.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 4,
                          color: colorScheme.primary,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return GlassCard(
      borderRadius: 16.0,
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      );
  }

  Widget _buildInsightsCard(
    List<ScanModel> scans,
    double healthyRate,
    String topDiseaseKey,
    String alertStatus,
    bool isDark,
    ColorScheme colorScheme,
    ThemeData theme,
    String locale,
  ) {
    String insightText = getTranslation('insight_empty', locale);
    IconData insightIcon = Icons.lightbulb_outline_rounded;
    Color iconColor = Colors.orangeAccent;

    if (scans.isNotEmpty) {
      if (healthyRate >= 75.0) {
        insightText = getTranslation('insight_healthy', locale);
        insightIcon = Icons.health_and_safety_rounded;
        iconColor = Colors.green;
      } else if (alertStatus == "CRITICAL" || topDiseaseKey != "none") {
        final diseaseName = getTranslation(topDiseaseKey, locale);
        final template = getTranslation('insight_critical_desc', locale);
        insightText = template.replaceAll('{disease}', diseaseName);
        insightIcon = Icons.warning_rounded;
        iconColor = Colors.redAccent;
      } else {
        insightText = getTranslation('insight_warning_desc', locale);
        insightIcon = Icons.info_outline;
        iconColor = Colors.orange;
      }
    }

    return GlassCard(
      borderRadius: 16.0,
      color: isDark ? const Color(0xFF1E2822).withValues(alpha: 0.45) : const Color(0xFFE8F5E9).withValues(alpha: 0.55),
      borderColor: isDark ? const Color(0xFF81C784).withValues(alpha: 0.15) : const Color(0xFF81C784).withValues(alpha: 0.35),
      padding: const EdgeInsets.all(16.0),
      child: Row(
          children: [
            Icon(insightIcon, color: iconColor, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    getTranslation('plantation_insight_title', locale),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insightText,
                    style: const TextStyle(fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildActiveLearningCard(
    Map<String, dynamic> stats,
    bool isDark,
    ColorScheme colorScheme,
    ThemeData theme,
    String locale,
  ) {
    final int total = stats['totalFeedback'] as int? ?? 0;
    final int negative = stats['negativeCount'] as int? ?? 0;
    final double positiveRate = stats['positiveRate'] as double? ?? 100.0;
    final List<dynamic> corrections = stats['correctionsBreakdown'] as List<dynamic>? ?? [];

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  getTranslation('active_learning_card', locale),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              getTranslation('active_learning_desc', locale),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),
            
            // Stats Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInsightMetric(getTranslation('feedback_rate_label', locale), '${positiveRate.toStringAsFixed(1)}%', Colors.green),
                _buildInsightMetric(getTranslation('logs_count_label', locale), '$total', Colors.blue),
                _buildInsightMetric(getTranslation('thumbs_down_label', locale), '$negative', Colors.redAccent),
              ],
            ),
            
            if (corrections.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                getTranslation('top_corrections_label', locale),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: corrections.length > 3 ? 3 : corrections.length,
                itemBuilder: (context, idx) {
                  final item = corrections[idx];
                  final String rawFrom = item['original_disease'] as String;
                  final String rawTo = item['user_disease'] as String;
                  final String from = getTranslation('disease_$rawFrom', locale);
                  final String to = getTranslation('disease_$rawTo', locale);
                  final int count = item['count'] as int? ?? 0;
                  final correctionsLabel = getTranslation('corrections_count', locale).replaceAll('{count}', count.toString());
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$from ➔ $to',
                            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            correctionsLabel,
                            style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],

            const Divider(height: 24),
            Text(
              getTranslation('active_learning_context', locale),
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey[600], height: 1.4),
            ),
          ],
        ),
      );
  }

  Widget _buildInsightMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
