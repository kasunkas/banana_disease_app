import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tflite_service.dart';
import 'grad_cam_service.dart';
import 'pdf_service.dart';
import 'image_enhancement_service.dart';
import 'feedback_service.dart';
import '../database/database_helper.dart';
import '../models/scan_model.dart';
import '../models/feedback_model.dart';


final tfliteServiceProvider = Provider<TfliteService>((ref) {
  final service = TfliteService();
  ref.onDispose(() => service.close());
  return service;
});

final gradCamServiceProvider = Provider<GradCamService>((ref) {
  return GradCamService();
});

final imageEnhancementServiceProvider = Provider<ImageEnhancementService>((ref) {
  return ImageEnhancementService();
});

final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  return FeedbackService(ref.watch(databaseHelperProvider));
});

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance;
});

class HistoryNotifier extends StateNotifier<AsyncValue<List<ScanModel>>> {
  final DatabaseHelper _dbHelper;
  
  HistoryNotifier(this._dbHelper) : super(const AsyncValue.loading()) {
    loadHistory();
  }
  
  Future<void> loadHistory() async {
    try {
      final scans = await _dbHelper.getAllScans();
      state = AsyncValue.data(scans);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<int> addScan(ScanModel scan) async {
    try {
      final id = await _dbHelper.insertScan(scan);
      await loadHistory();
      return id;
    } catch (e) {
      debugPrint("Error adding scan: $e");
      rethrow;
    }
  }
  
  Future<void> deleteScan(int id) async {
    try {
      await _dbHelper.deleteScan(id);
      await loadHistory();
    } catch (e) {
      debugPrint("Error deleting scan: $e");
    }
  }

  Future<void> clearAll() async {
    try {
      await _dbHelper.clearHistory();
      await loadHistory();
    } catch (e) {
      debugPrint("Error clearing history: $e");
    }
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, AsyncValue<List<ScanModel>>>((ref) {
  return HistoryNotifier(ref.watch(databaseHelperProvider));
});

final statsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(historyProvider); // rebuild stats when history changes
  return await ref.watch(databaseHelperProvider).getStats();
});

final distributionProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(historyProvider); // rebuild distribution when history changes
  return await ref.watch(databaseHelperProvider).getDiseaseDistribution();
});

final pdfServiceProvider = Provider<PdfService>((ref) {
  return PdfService();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _key = 'theme_mode';
  
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_key);
      if (index != null) {
        state = ThemeMode.values[index];
      }
    } catch (_) {}
  }
  
  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = newMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, newMode.index);
    } catch (_) {}
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

final researchModeProvider = StateProvider<bool>((ref) => false);
final modelVersionProvider = StateProvider<String>((ref) => 'MobileNetV2-Banana-Float32');
final imageEnhancementEnabledProvider = StateProvider<bool>((ref) => true);
final imageEnhancementStrengthProvider = StateProvider<String>((ref) => 'Medium');

class FeedbackHistoryNotifier extends StateNotifier<AsyncValue<List<FeedbackModel>>> {
  final FeedbackService _service;
  
  FeedbackHistoryNotifier(this._service) : super(const AsyncValue.loading()) {
    loadFeedback();
  }
  
  Future<void> loadFeedback() async {
    try {
      final list = await _service.getAllFeedback();
      state = AsyncValue.data(list);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<void> addFeedback(FeedbackModel feedback) async {
    try {
      await _service.submitFeedback(feedback);
      await loadFeedback();
    } catch (e) {
      debugPrint("Error saving feedback: $e");
      rethrow;
    }
  }
}

final feedbackHistoryProvider = StateNotifierProvider<FeedbackHistoryNotifier, AsyncValue<List<FeedbackModel>>>((ref) {
  return FeedbackHistoryNotifier(ref.watch(feedbackServiceProvider));
});

final feedbackStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(feedbackHistoryProvider); // rebuild stats when feedback logs change
  return await ref.watch(feedbackServiceProvider).getFeedbackStats();
});

class FavoriteDiseasesNotifier extends StateNotifier<List<String>> {
  static const _key = 'favorite_diseases';

  FavoriteDiseasesNotifier() : super([]) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favs = prefs.getStringList(_key);
      if (favs != null) {
        state = favs;
      }
    } catch (_) {}
  }

  Future<void> toggleFavorite(String diseaseId) async {
    final isFav = state.contains(diseaseId);
    final newState = isFav
        ? state.where((id) => id != diseaseId).toList()
        : [...state, diseaseId];
    state = newState;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, newState);
    } catch (_) {}
  }
}

final favoriteDiseasesProvider = StateNotifierProvider<FavoriteDiseasesNotifier, List<String>>((ref) {
  return FavoriteDiseasesNotifier();
});


