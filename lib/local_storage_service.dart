// local_storage_service.dart - UPDATED WITH HRV & RHR
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

class HealthDataPoint {
  final int? id;
  final int heartRate;
  final int steps;
  final int spo2;
  final int calories;
  final double sleep;
  final int recovery;
  final int stress;
  final int rhr; // NEW
  final int hrv; // NEW
  final double bodyTemperature; // NEW
  final int breathingRate;
  final int? activityIntensity; // NEW: Store activity intensity
  final DateTime timestamp;

  HealthDataPoint({
    this.id,
    required this.heartRate,
    required this.steps,
    required this.spo2,
    required this.calories,
    required this.sleep,
    required this.recovery,
    required this.stress,
    required this.rhr, // NEW
    required this.hrv, // NEW
    required this.timestamp,
    this.bodyTemperature = 36.5,
    this.breathingRate = 16,
    this.activityIntensity, // NEW
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'heartRate': heartRate,
      'steps': steps,
      'spo2': spo2,
      'calories': calories,
      'sleep': sleep,
      'recovery': recovery,
      'stress': stress,
      'rhr': rhr, // NEW
      'hrv': hrv, // NEW
      'bodyTemperature': bodyTemperature,
      'breathingRate': breathingRate,
      'activityIntensity': activityIntensity, // NEW
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory HealthDataPoint.fromMap(Map<String, dynamic> map) {
    return HealthDataPoint(
      id: map['id'],
      heartRate: map['heartRate'],
      steps: map['steps'],
      spo2: map['spo2'],
      calories: map['calories'],
      sleep: map['sleep'].toDouble(),
      recovery: map['recovery'],
      stress: map['stress'] ?? 30,
      rhr: map['rhr'] ?? 65, // NEW
      hrv: map['hrv'] ?? 45, // NEW
      breathingRate: map['breathingRate'] ?? 16,
      activityIntensity: map['activityIntensity'], // NEW
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}

class LocalStorageService {
  static Database? _database;
  static final LocalStorageService _instance = LocalStorageService._internal();

  factory LocalStorageService() => _instance;

  LocalStorageService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'health_data.db');
    return await openDatabase(
      path,
      version: 4, // UPDATED VERSION for activity intensity field
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE health_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        heartRate INTEGER,
        steps INTEGER,
        spo2 INTEGER,
        calories INTEGER,
        sleep REAL,
        recovery INTEGER,
        stress INTEGER DEFAULT 30,
        rhr INTEGER DEFAULT 65,
        hrv INTEGER DEFAULT 45,
        bodyTemperature REAL DEFAULT 36.5,
        breathingRate INTEGER DEFAULT 16,
        activityIntensity INTEGER, -- NEW
        timestamp INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_timestamp ON health_data(timestamp)
    ''');
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE health_data ADD COLUMN rhr INTEGER DEFAULT 65',
      );
      await db.execute(
        'ALTER TABLE health_data ADD COLUMN hrv INTEGER DEFAULT 45',
      );
      await db.execute(
        'ALTER TABLE health_data ADD COLUMN bodyTemperature REAL DEFAULT 36.5',
      );
      await db.execute(
        'ALTER TABLE health_data ADD COLUMN breathingRate INTEGER DEFAULT 16',
      );
    }
    if (oldVersion < 4) {
      // For existing databases, add activityIntensity column
      await db.execute(
        'ALTER TABLE health_data ADD COLUMN activityIntensity INTEGER',
      );
    }
  }

  Future<void> saveHealthData(HealthDataPoint data) async {
    final db = await database;
    await db.insert('health_data', data.toMap());
  }

  Future<List<HealthDataPoint>> getAllHealthData() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'health_data',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => HealthDataPoint.fromMap(maps[i]));
  }

  Future<HealthDataPoint?> getLatestHealthData() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'health_data',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return HealthDataPoint.fromMap(maps.first);
  }

  Future<List<HealthDataPoint>> getHourlyAverages(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT 
        strftime('%Y-%m-%d %H:00:00', timestamp/1000, 'unixepoch') as hour,
        AVG(heartRate) as avg_heartRate,
        AVG(steps) as avg_steps,
        AVG(spo2) as avg_spo2,
        AVG(calories) as avg_calories,
        AVG(sleep) as avg_sleep,
        AVG(recovery) as avg_recovery,
        AVG(stress) as avg_stress,
        AVG(rhr) as avg_rhr,
        AVG(hrv) as avg_hrv,
        AVG(bodyTemperature) as avg_bodyTemperature,
        AVG(breathingRate) as avg_breathingRate,
        AVG(activityIntensity) as avg_activityIntensity
      FROM health_data
      WHERE timestamp BETWEEN ? AND ?
      GROUP BY hour
      ORDER BY hour
    ''',
      [startDate.millisecondsSinceEpoch, endDate.millisecondsSinceEpoch],
    );

    return maps.map((map) {
      return HealthDataPoint(
        heartRate: (map['avg_heartRate'] as num).round(),
        steps: (map['avg_steps'] as num).round(),
        spo2: (map['avg_spo2'] as num).round(),
        calories: (map['avg_calories'] as num).round(),
        sleep: (map['avg_sleep'] as num).toDouble(),
        recovery: (map['avg_recovery'] as num).round(),
        stress: (map['avg_stress'] as num?)?.round() ?? 30,
        rhr: (map['avg_rhr'] as num?)?.round() ?? 65,
        hrv: (map['avg_hrv'] as num?)?.round() ?? 45,
        bodyTemperature:
            (map['avg_bodyTemperature'] as num?)?.toDouble() ?? 36.5,
        breathingRate: (map['avg_breathingRate'] as num?)?.round() ?? 16,
        activityIntensity: (map['avg_activityIntensity'] as num?)
            ?.round(), // NEW
        timestamp: DateTime.parse(map['hour']),
      );
    }).toList();
  }

  Future<void> clearOldData() async {
    final db = await database;
    final oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
    await db.delete(
      'health_data',
      where: 'timestamp < ?',
      whereArgs: [oneMonthAgo.millisecondsSinceEpoch],
    );
  }

  // NEW: Get latest activity intensity
  Future<int?> getLatestActivityIntensity() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'health_data',
      columns: ['activityIntensity'],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty || maps.first['activityIntensity'] == null) {
      return null;
    }
    return maps.first['activityIntensity'] as int?;
  }

  // NEW: Get activity intensity for a specific date
  Future<int?> getActivityIntensityForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT activityIntensity 
      FROM health_data 
      WHERE timestamp >= ? AND timestamp < ?
      ORDER BY timestamp DESC
      LIMIT 1
    ''',
      [startOfDay.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch],
    );

    if (maps.isEmpty || maps.first['activityIntensity'] == null) {
      return null;
    }
    return maps.first['activityIntensity'] as int?;
  }

  // NEW: Get HR data for a specific time range
  Future<List<int>> getHRDataForRange(DateTime start, DateTime end) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'health_data',
      columns: ['heartRate'],
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) => (m['heartRate'] as num).toInt()).toList();
  }

  // NEW: Update RHR, HRV, Recovery, and Health Score for all points on a specific day
  Future<void> updateDailyCalculatedMetrics(
    DateTime date,
    int rhr,
    int hrv,
    int recovery,
  ) async {
    final db = await database;
    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;

    await db.update(
      'health_data',
      {'rhr': rhr, 'hrv': hrv, 'recovery': recovery},
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startOfDay, endOfDay],
    );
    print(
      '✅ Updated RHR($rhr), HRV($hrv), Recovery($recovery) for $date in database',
    );
  }
}
