import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE dtcs (
        code TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        cause TEXT NOT NULL
      );
    ''');

    await _populateFromJson(db);
  }

  Future<void> _populateFromJson(Database db) async {
    final jsonStr = await rootBundle.loadString('assets/dtcs.json');
    final Map<String, dynamic> dtcs = json.decode(jsonStr);

    final batch = db.batch();
    dtcs.forEach((code, details) {
      batch.insert('dtcs', {
        'code': code,
        'description': details['description'],
        'cause': details['cause'],
      });
    });
    await batch.commit(noResult: true);
  }

  Future<Map<String, String>?> getDtc(String code) async {
    final db = await database;
    final result = await db.query(
      'dtcs',
      where: 'code = ?',
      whereArgs: [code],
    );
    if (result.isEmpty) return null;
    return {
      'description': result[0]['description'] as String,
      'cause': result[0]['cause'] as String,
    };
  }
}
