import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:automotiq_app/utils/logger.dart';

class DtcDatabaseService {
  static final DtcDatabaseService _instance = DtcDatabaseService._internal();
  factory DtcDatabaseService() => _instance;

  DtcDatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'dtcs.db');
    AppLogger.logInfo('Initializing database at: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onOpen: (db) async {
        final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM dtcs'),
        );
        AppLogger.logInfo('DTC database contains $count records');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    AppLogger.logInfo('Creating dtcs table');
    await db.execute('''
      CREATE TABLE dtcs (
        code TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        cause TEXT NOT NULL
      )
    ''');
    await _populateFromJson(db);
  }

  Future<void> _populateFromJson(Database db) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/dtcs.json');
      final Map<String, dynamic> dtcs = json.decode(jsonStr);
      AppLogger.logInfo('Loaded ${dtcs.length} DTCs from assets/dtcs.json');

      final batch = db.batch();
      final seenCodes = <String>{}; // Track unique codes

      dtcs.forEach((code, details) {
        final normalizedCode = code.toUpperCase();
        if (seenCodes.contains(normalizedCode)) {
          AppLogger.logWarning(
            'Duplicate DTC code found in JSON: $normalizedCode, skipping',
          );
          return; // Skip duplicates
        }
        seenCodes.add(normalizedCode);
        batch.insert(
          'dtcs',
          {
            'code': normalizedCode,
            'description':
                details['description']?.toString() ?? 'No description',
            'cause': details['cause']?.toString() ?? 'No cause',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore, // Ignore duplicates
        );
      });

      await batch.commit(noResult: true);
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM dtcs'),
      );
      AppLogger.logInfo('DTC database populated with $count records');
    } catch (e) {
      AppLogger.logError('Failed to populate DTC database: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> getDtc(String code) async {
    AppLogger.logInfo("REQUESTED CODE: $code");
    try {
      final db = await database;
      final result = await db.query(
        'dtcs',
        where: 'code = ?',
        whereArgs: [code.toUpperCase()],
      );
      if (result.isEmpty) {
        AppLogger.logWarning('No DTC found for code: $code');
        return {'description': '', 'cause': ''};
      }
      AppLogger.logInfo('Retrieved DTC $code: ${result[0]}');
      return {
        'description': result[0]['description'] as String,
        'cause': result[0]['cause'] as String,
      };
    } catch (e) {
      AppLogger.logError('Error querying DTC $code: $e');
      return {'description': '', 'cause': ''};
    }
  }

  Future<String?> getRandomDtcCode() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT code FROM dtcs ORDER BY RANDOM() LIMIT 1',
      );
      if (result.isEmpty) {
        AppLogger.logWarning('No DTC codes available in database');
        return null;
      }
      final code = result.first['code'] as String;
      AppLogger.logInfo('Selected random DTC code: $code');
      return code;
    } catch (e) {
      AppLogger.logError('Error fetching random DTC code: $e');
      return null;
    }
  }
}
