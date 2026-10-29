import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  factory AppDatabase.open(String path) => _init(sqlite3.open(path));

  factory AppDatabase.inMemory() => _init(sqlite3.openInMemory());

  /// Otwiera istniejaca baze (migracje i klucze obce jak zwykle).
  factory AppDatabase.wrap(Database db) => _init(db);

  static AppDatabase _init(Database db) {
    db.execute('PRAGMA foreign_keys = ON');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > schemaVersion) {
      db.close();
      throw StateError('Baza ma nowsza wersje schematu ($version)');
    }
    if (version == 0) {
      db.execute('BEGIN');
      try {
        db.execute(schemaSql);
        db.execute(seedSql);
        db.execute('PRAGMA user_version = $schemaVersion');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    } else {
      for (var v = version + 1; v <= schemaVersion; v++) {
        db.execute('BEGIN');
        try {
          db.execute(migrationSql[v]!);
          db.execute('PRAGMA user_version = $v');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      }
    }
    return AppDatabase._(db);
  }

  T transaction<T>(T Function() body) {
    db.execute('BEGIN');
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.close();
}
