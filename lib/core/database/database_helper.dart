import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/scan_model.dart';

class DatabaseHelper {
  static const _databaseName = "mokoguard.db";
  static const _databaseVersion = 3;
  static const tableScans = "scans";
  static const tableFeedback = "feedback_logs";

  // Singleton instance
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getDatabasesPath();
    final path = join(documentsDirectory, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableScans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_image_path TEXT NOT NULL,
        overlay_image_path TEXT NOT NULL,
        disease_name TEXT NOT NULL,
        confidence REAL NOT NULL,
        severity TEXT NOT NULL,
        inference_time_ms INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        original_unenhanced_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableFeedback (
        id TEXT PRIMARY KEY,
        scan_id INTEGER,
        original_disease TEXT NOT NULL,
        original_severity TEXT NOT NULL,
        user_disease TEXT,
        user_severity TEXT,
        confidence REAL NOT NULL,
        feedback_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (scan_id) REFERENCES $tableScans (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableScans ADD COLUMN original_unenhanced_path TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE $tableFeedback (
          id TEXT PRIMARY KEY,
          scan_id INTEGER,
          original_disease TEXT NOT NULL,
          original_severity TEXT NOT NULL,
          user_disease TEXT,
          user_severity TEXT,
          confidence REAL NOT NULL,
          feedback_type TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (scan_id) REFERENCES $tableScans (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // Insert a scan
  Future<int> insertScan(ScanModel scan) async {
    final db = await database;
    return await db.insert(tableScans, scan.toMap());
  }

  // Query all scans (newest first)
  Future<List<ScanModel>> getAllScans() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableScans,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => ScanModel.fromMap(maps[i]));
  }

  // Delete a scan
  Future<int> deleteScan(int id) async {
    final db = await database;
    return await db.delete(
      tableScans,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Clear all scans
  Future<int> clearHistory() async {
    final db = await database;
    return await db.delete(tableScans);
  }

  // Get statistics for the dashboard
  Future<Map<String, int>> getStats() async {
    final db = await database;
    
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM $tableScans');
    final healthyResult = await db.rawQuery("SELECT COUNT(*) as count FROM $tableScans WHERE LOWER(disease_name) = 'healthy'");
    final mokoResult = await db.rawQuery("SELECT COUNT(*) as count FROM $tableScans WHERE LOWER(disease_name) LIKE '%moko%'");

    final int total = totalResult.first['count'] as int? ?? 0;
    final int healthy = healthyResult.first['count'] as int? ?? 0;
    final int moko = mokoResult.first['count'] as int? ?? 0;
    final int diseased = total - healthy;

    return {
      'total': total,
      'healthy': healthy,
      'diseased': diseased,
      'moko': moko,
    };
  }

  // Get distribution of each disease class for the chart
  Future<Map<String, int>> getDiseaseDistribution() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT disease_name, COUNT(*) as count FROM $tableScans GROUP BY disease_name'
    );

    final Map<String, int> distribution = {};
    for (var row in result) {
      final name = row['disease_name'] as String;
      final count = row['count'] as int;
      distribution[name] = count;
    }
    return distribution;
  }
}
