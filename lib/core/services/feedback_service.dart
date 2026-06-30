import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/feedback_model.dart';

class FeedbackService {
  final DatabaseHelper _dbHelper;

  FeedbackService(this._dbHelper);

  /// Saves a user feedback log to SQLite.
  Future<void> submitFeedback(FeedbackModel feedback) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseHelper.tableFeedback,
      feedback.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all feedback logs recorded on the device.
  Future<List<FeedbackModel>> getAllFeedback() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      DatabaseHelper.tableFeedback,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => FeedbackModel.fromMap(maps[i]));
  }

  /// Deletes a specific feedback entry by ID.
  Future<void> deleteFeedback(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseHelper.tableFeedback,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Calculates feedback aggregates (e.g. positive rate, error distribution) for the dashboard.
  Future<Map<String, dynamic>> getFeedbackStats() async {
    final db = await _dbHelper.database;

    final posResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM ${DatabaseHelper.tableFeedback} WHERE feedback_type = 'positive'"
    );
    final negResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM ${DatabaseHelper.tableFeedback} WHERE feedback_type = 'negative'"
    );

    final int positive = posResult.first['count'] as int? ?? 0;
    final int negative = negResult.first['count'] as int? ?? 0;
    final int total = positive + negative;
    final double positiveRate = total > 0 ? (positive / total) * 100.0 : 100.0;

    // Get correction breakdown (what user corrected from vs to)
    final List<Map<String, dynamic>> corrections = await db.rawQuery('''
      SELECT original_disease, user_disease, COUNT(*) as count 
      FROM ${DatabaseHelper.tableFeedback} 
      WHERE feedback_type = 'negative' AND user_disease IS NOT NULL 
      GROUP BY original_disease, user_disease
      ORDER BY count DESC
    ''');

    return {
      'totalFeedback': total,
      'positiveCount': positive,
      'negativeCount': negative,
      'positiveRate': positiveRate,
      'correctionsBreakdown': corrections,
    };
  }

  /// Exports local feedback data as a formatted JSON file.
  Future<String> exportFeedbackAsJson() async {
    final logs = await getAllFeedback();
    final list = logs.map((l) => l.toMap()).toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(list);

    final Directory docDir = await getApplicationDocumentsDirectory();
    final String filePath = '${docDir.path}/mokoguard_feedback_export.json';
    final File file = File(filePath);
    await file.writeAsString(jsonString);
    return filePath;
  }

  /// Exports local feedback data as a tabular CSV file.
  Future<String> exportFeedbackAsCsv() async {
    final logs = await getAllFeedback();
    final buffer = StringBuffer();
    
    // Write headers
    buffer.writeln('Feedback_ID,Scan_ID,Original_Disease,Original_Severity,User_Disease,User_Severity,Confidence,Feedback_Type,Created_At');
    
    // Write rows
    for (final log in logs) {
      final String userDisease = log.userDisease ?? '';
      final String userSeverity = log.userSeverity ?? '';
      buffer.writeln(
        '${log.id},${log.scanId},"${log.originalDisease}","${log.originalSeverity}","$userDisease","$userSeverity",${log.confidence},"${log.feedbackType}","${log.createdAt.toIso8601String()}"'
      );
    }

    final Directory docDir = await getApplicationDocumentsDirectory();
    final String filePath = '${docDir.path}/mokoguard_feedback_export.csv';
    final File file = File(filePath);
    await file.writeAsString(buffer.toString());
    return filePath;
  }
}
