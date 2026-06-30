import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/scan_model.dart';
import '../../../core/services/providers.dart';

class AnalyticsSummary {
  final int totalScans;
  final String mostCommonDisease;
  final String averageSeverity;
  final double diseasePressureTrend; // Positive is increasing, negative is decreasing

  AnalyticsSummary({
    required this.totalScans,
    required this.mostCommonDisease,
    required this.averageSeverity,
    required this.diseasePressureTrend,
  });
}

class DiseasePressurePoint {
  final DateTime date;
  final double highRatio;
  final double mediumRatio;

  DiseasePressurePoint({
    required this.date,
    required this.highRatio,
    required this.mediumRatio,
  });
}

class DiseaseDistributionPoint {
  final String diseaseName;
  final int count;

  DiseaseDistributionPoint({
    required this.diseaseName,
    required this.count,
  });
}

class CalendarHeatmapPoint {
  final DateTime date;
  final String averageSeverity; // 'Low', 'Medium', 'High', 'Healthy'
  final List<ScanModel> scans;

  CalendarHeatmapPoint({
    required this.date,
    required this.averageSeverity,
    required this.scans,
  });
}

class AnalyticsRepository {
  final DatabaseHelper _dbHelper;

  AnalyticsRepository(this._dbHelper);

  // Core filter logic: fetches scans from database and filters them in Dart for performance and flexibility
  Future<List<ScanModel>> getFilteredScans({
    required String dateRangeFilter, // '7days', '30days', '3months', 'all'
    String? diseaseFilter, // null means all
  }) async {
    final allScans = await _dbHelper.getAllScans();
    final now = DateTime.now();

    DateTime? cutoffDate;
    if (dateRangeFilter == '7days') {
      cutoffDate = now.subtract(const Duration(days: 7));
    } else if (dateRangeFilter == '30days') {
      cutoffDate = now.subtract(const Duration(days: 30));
    } else if (dateRangeFilter == '3months') {
      cutoffDate = now.subtract(const Duration(days: 90));
    }

    return allScans.where((scan) {
      // 1. Filter by Date Range
      if (cutoffDate != null && scan.createdAt.isBefore(cutoffDate)) {
        return false;
      }
      // 2. Filter by Disease Type
      if (diseaseFilter != null && diseaseFilter != 'All' && 
          scan.diseaseName.replaceAll('_', ' ').toLowerCase() != diseaseFilter.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  // Pre-computes dashboard aggregates: Total, top disease, avg severity, and pressure trends
  Future<AnalyticsSummary> computeSummary(List<ScanModel> filteredScans) async {
    final total = filteredScans.length;
    if (total == 0) {
      return AnalyticsSummary(
        totalScans: 0,
        mostCommonDisease: 'None',
        averageSeverity: 'Healthy',
        diseasePressureTrend: 0.0,
      );
    }

    // 1. Calculate most common disease (excluding Healthy)
    final Map<String, int> diseaseCounts = {};
    for (final scan in filteredScans) {
      if (scan.diseaseName.toLowerCase() != 'healthy') {
        diseaseCounts[scan.diseaseName] = (diseaseCounts[scan.diseaseName] ?? 0) + 1;
      }
    }
    String topDisease = 'None';
    if (diseaseCounts.isNotEmpty) {
      final sorted = diseaseCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topDisease = sorted.first.key.replaceAll('_', ' ');
    }

    // 2. Calculate average severity level (High = 3, Medium = 2, Low = 1, Healthy = 0)
    double severitySum = 0;
    for (final scan in filteredScans) {
      if (scan.diseaseName.toLowerCase() == 'healthy') continue;
      if (scan.severity.toLowerCase() == 'high') {
        severitySum += 3;
      } else if (scan.severity.toLowerCase() == 'medium') {
        severitySum += 2;
      } else {
        severitySum += 1;
      }
    }
    final double avgSeverityVal = total > 0 ? (severitySum / total) : 0.0;
    String avgSeverity = 'Low';
    if (avgSeverityVal >= 2.3) {
      avgSeverity = 'High';
    } else if (avgSeverityVal >= 1.2) {
      avgSeverity = 'Medium';
    } else if (avgSeverityVal == 0.0) {
      avgSeverity = 'Healthy';
    }

    // 3. Compute disease pressure trend: compare last 7 days vs previous 7 days
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));

    final recentScans = filteredScans.where((s) => s.createdAt.isAfter(sevenDaysAgo)).toList();
    final pastScans = filteredScans.where((s) => s.createdAt.isAfter(fourteenDaysAgo) && s.createdAt.isBefore(sevenDaysAgo)).toList();

    double recentPressure = 0.0;
    if (recentScans.isNotEmpty) {
      final diseasedRecent = recentScans.where((s) => s.diseaseName.toLowerCase() != 'healthy').length;
      recentPressure = (diseasedRecent / recentScans.length) * 100;
    }

    double pastPressure = 0.0;
    if (pastScans.isNotEmpty) {
      final diseasedPast = pastScans.where((s) => s.diseaseName.toLowerCase() != 'healthy').length;
      pastPressure = (diseasedPast / pastScans.length) * 100;
    }

    return AnalyticsSummary(
      totalScans: total,
      mostCommonDisease: topDisease,
      averageSeverity: avgSeverity,
      diseasePressureTrend: recentPressure - pastPressure,
    );
  }

  // Pre-computes weekly or monthly disease pressure points for LineChart
  List<DiseasePressurePoint> getPressureTrendPoints(List<ScanModel> scans) {
    if (scans.isEmpty) return [];

    // Group scans by week (defined by start date of that week)
    final Map<DateTime, List<ScanModel>> grouped = {};
    for (final scan in scans) {
      // Find start of week (Monday)
      final date = DateTime(scan.createdAt.year, scan.createdAt.month, scan.createdAt.day);
      final int weekdayOffset = date.weekday - 1;
      final startOfWeek = date.subtract(Duration(days: weekdayOffset));
      
      grouped[startOfWeek] ??= [];
      grouped[startOfWeek]!.add(scan);
    }

    final List<DiseasePressurePoint> points = [];
    grouped.forEach((weekStart, weekScans) {
      final int total = weekScans.length;
      final int high = weekScans.where((s) => s.severity.toLowerCase() == 'high').length;
      final int medium = weekScans.where((s) => s.severity.toLowerCase() == 'medium').length;

      points.add(DiseasePressurePoint(
        date: weekStart,
        highRatio: (high / total) * 100.0,
        mediumRatio: (medium / total) * 100.0,
      ));
    });

    // Sort by date ascending
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  // Pre-computes distribution scan counts for BarChart
  List<DiseaseDistributionPoint> getDiseaseDistribution(List<ScanModel> scans) {
    final Map<String, int> counts = {};
    for (final scan in scans) {
      final String name = scan.diseaseName.replaceAll('_', ' ');
      counts[name] = (counts[name] ?? 0) + 1;
    }

    final List<DiseaseDistributionPoint> points = [];
    counts.forEach((disease, count) {
      points.add(DiseaseDistributionPoint(diseaseName: disease, count: count));
    });
    
    // Sort alphabetically to maintain layout alignment
    points.sort((a, b) => a.diseaseName.compareTo(b.diseaseName));
    return points;
  }

  // Generates monthly calendar heatmap matrix data points
  Map<DateTime, CalendarHeatmapPoint> getCalendarHeatmapPoints(List<ScanModel> scans) {
    final Map<DateTime, List<ScanModel>> groupedByDay = {};
    for (final scan in scans) {
      final dateOnly = DateTime(scan.createdAt.year, scan.createdAt.month, scan.createdAt.day);
      groupedByDay[dateOnly] ??= [];
      groupedByDay[dateOnly]!.add(scan);
    }

    final Map<DateTime, CalendarHeatmapPoint> heatmapPoints = {};
    groupedByDay.forEach((day, dayScans) {
      double severitySum = 0;
      int activeDiseased = 0;
      
      for (final s in dayScans) {
        if (s.diseaseName.toLowerCase() == 'healthy') continue;
        activeDiseased++;
        if (s.severity.toLowerCase() == 'high') {
          severitySum += 3;
        } else if (s.severity.toLowerCase() == 'medium') {
          severitySum += 2;
        } else {
          severitySum += 1;
        }
      }

      String avgSeverity = 'Healthy';
      if (activeDiseased > 0) {
        final double score = severitySum / activeDiseased;
        if (score >= 2.4) {
          avgSeverity = 'High';
        } else if (score >= 1.4) {
          avgSeverity = 'Medium';
        } else {
          avgSeverity = 'Low';
        }
      }

      heatmapPoints[day] = CalendarHeatmapPoint(
        date: day,
        averageSeverity: avgSeverity,
        scans: dayScans,
      );
    });

    return heatmapPoints;
  }
}

// Riverpod provider registration
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(databaseHelperProvider));
});
