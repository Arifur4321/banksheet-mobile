/// The on-device SQLite database.
///
/// Three jobs, and deliberately no fourth:
///
///   1. **Recent files** for the reader, so opening the app shows what you were
///      last looking at instead of an empty picker.
///   2. **Guest usage counters**, so a signed-out user can be told they have
///      reached the free ceiling before the app asks them to create an account.
///   3. **Per-install counters** — the scanner's free-PDF allowance, spent once
///      per install rather than per month. See [InstallMeter] for why that one
///      lives in its own table and survives [LocalDb.wipeAll].
///
/// What this database is *not* is a mirror of the server. It holds no
/// transaction rows, no balances, no IBANs and no file bytes — only paths the
/// OS already gave us and integers we counted. That line is drawn on purpose:
/// the statement data belongs to our customers' clients, an offline phone
/// cannot honour a GDPR erasure request, and `sqflite` writes plaintext. Adding
/// a `transactions` table here is a decision with a data-protection impact
/// assessment attached, not a refactor.
///
/// The guest counters are **advisory**. Clearing app data resets them, and that
/// is accepted: the free tier's real enforcement is that every conversion,
/// e-signature and extraction requires a signed-in account, where
/// `PlanEnforcementService` counts server-side and cannot be cleared. These
/// counters exist so a guest sees "3 of 10 used" instead of hitting a wall.
///
/// Pure Dart apart from `path_provider`, so every method below is unit
/// testable against `sqflite_common_ffi` without a widget binding.
library;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';

/// Where a remembered file came from. Kept as a string column rather than an
/// int so a database opened by hand during support is readable.
enum RecentSource {
  /// The user picked it from device storage.
  picker,

  /// It came out of a conversion tool.
  conversion,

  /// It was downloaded from the workspace.
  download;

  static RecentSource parse(String? raw) => switch (raw) {
        'conversion' => RecentSource.conversion,
        'download' => RecentSource.download,
        _ => RecentSource.picker,
      };
}

/// One row of the reader's history.
class RecentFile {
  const RecentFile({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.openedAt,
    required this.source,
    this.pageCount,
  });

  factory RecentFile.fromRow(Map<String, Object?> row) => RecentFile(
        path: row['path']! as String,
        filename: row['filename']! as String,
        sizeBytes: (row['size_bytes'] as int?) ?? 0,
        pageCount: row['page_count'] as int?,
        openedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['opened_at'] as int?) ?? 0,
        ),
        source: RecentSource.parse(row['source'] as String?),
      );

  final String path;
  final String filename;
  final int sizeBytes;
  final int? pageCount;
  final DateTime openedAt;
  final RecentSource source;

  Map<String, Object?> toRow() => <String, Object?>{
        'path': path,
        'filename': filename,
        'size_bytes': sizeBytes,
        'page_count': pageCount,
        'opened_at': openedAt.millisecondsSinceEpoch,
        'source': source.name,
      };
}

/// The metered actions a guest can spend before signing in.
enum GuestMeter {
  conversion,
  esign,
  statement;

  /// The free-plan ceiling. These mirror `config/mobile_plans.php`'s `free`
  /// entry on the server; the server is authoritative once a user signs in,
  /// and these are only what a guest is shown.
  int get freeLimit => switch (this) {
        GuestMeter.conversion => 10,
        GuestMeter.esign => 10,
        GuestMeter.statement => 10,
      };
}

/// An allowance spent **once per install** rather than once per month.
///
/// Two things make this a different table from [GuestMeter] rather than a flag
/// on it, and both are worth stating because a future reader will be tempted to
/// merge them:
///
///   * **It never rolls over.** The scanner's free PDFs are a trial, not a
///     monthly quota. A counter that resets on the first of the month is not a
///     trial, it is a free tier — a different product decision, and not this
///     one.
///   * **It survives sign-out.** [LocalDb.wipeAll] clears everything that
///     belongs to a session, and if this went with it, "sign out and back in"
///     would be a one-tap reset of the trial. Whoever is holding the phone has
///     had their three PDFs.
///
/// It is still **advisory**, exactly like [GuestMeter]: clearing app data or
/// reinstalling resets it, and that is accepted. Making it tamper-proof means
/// an anonymous server-side identity for every install, which costs a privacy
/// disclosure on both stores and buys very little — the wall it guards is a
/// free registration, not a paid plan.
enum InstallMeter {
  /// PDFs produced by the on-device scanner.
  scanPdf;

  int get freeLimit => switch (this) {
        InstallMeter.scanPdf => AppConfig.freeScanPdfs,
      };
}

class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  /// Bumped on every schema change. [_migrate] must gain a matching step.
  static const int _schemaVersion = 2;

  static const String _fileName = 'banksheet.db';

  /// How many recent files to keep. Beyond this the oldest are dropped, so the
  /// database cannot grow without bound on a phone that opens PDFs all day.
  static const int _recentLimit = 50;

  static Future<LocalDb> open() async {
    // Application *support*, not documents. On iOS the documents directory is
    // backed up to iCloud by default, which would ship a list of our customers'
    // client filenames into Apple's servers under the end user's own account.
    // Support is excluded from backup on both platforms.
    final String dir = (await getApplicationSupportDirectory()).path;
    final String path = p.join(dir, _fileName);

    final Database db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (Database db) async {
        // Off by default in SQLite, and the recents table has no foreign keys
        // today — but turning it on now means the first table that does have
        // one behaves correctly instead of silently not enforcing anything.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) => _migrate(db, 0, version),
      onUpgrade: _migrate,
    );

    Log.info('Local database ready at $path (v$_schemaVersion)');
    return LocalDb._(db);
  }

  /// An in-memory database on the same schema, for tests.
  ///
  /// It runs the real [_migrate] ladder rather than a hand-written CREATE, so a
  /// test that passes here is testing the schema that ships. Lives in this file
  /// rather than in a test helper for exactly that reason: the moment the two
  /// can drift, they will.
  ///
  /// Requires a `databaseFactory` that works off-device — see
  /// `sqflite_common_ffi` in `dev_dependencies`.
  static Future<LocalDb> openInMemory() async {
    final Database db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (Database db) =>
            db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database db, int version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    return LocalDb._(db);
  }

  /// The migration ladder. Each step moves exactly one version forward, so a
  /// device three versions behind arrives at the same schema as a fresh
  /// install rather than a subtly different one.
  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      await db.execute('''
        CREATE TABLE recent_files (
          path       TEXT    PRIMARY KEY,
          filename   TEXT    NOT NULL,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          page_count INTEGER,
          opened_at  INTEGER NOT NULL,
          source     TEXT    NOT NULL DEFAULT 'picker'
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_recent_opened ON recent_files (opened_at DESC)',
      );
      await db.execute('''
        CREATE TABLE guest_usage (
          meter        TEXT    PRIMARY KEY,
          used         INTEGER NOT NULL DEFAULT 0,
          period_start INTEGER NOT NULL
        )
      ''');
    }

    if (from < 2) {
      // Per-install counters. No `period_start`: that absence is the whole
      // point of the table — see [InstallMeter].
      await db.execute('''
        CREATE TABLE install_usage (
          meter      TEXT    PRIMARY KEY,
          used       INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )
      ''');
    }

    // Next schema change adds `if (from < 3) { ... }` here. Never edit a step
    // that has shipped — a device that already ran it will not run it again.
  }

  // --------------------------------------------------------------- recents

  Future<List<RecentFile>> recentFiles({int limit = 20}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'recent_files',
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows.map(RecentFile.fromRow).toList(growable: false);
  }

  /// Records an open, or moves an existing entry back to the top.
  ///
  /// Trimming happens on write rather than on read so the table cannot sit at
  /// ten thousand rows between app launches.
  Future<void> rememberFile(RecentFile file) async {
    await _db.insert(
      'recent_files',
      file.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.rawDelete(
      '''
      DELETE FROM recent_files
       WHERE path NOT IN (
         SELECT path FROM recent_files ORDER BY opened_at DESC LIMIT ?
       )
      ''',
      <Object?>[_recentLimit],
    );
  }

  /// Drops one entry — used when the underlying file has gone, which happens
  /// routinely on Android because `file_picker` hands back a cache copy the OS
  /// is free to reclaim.
  Future<void> forgetFile(String path) =>
      _db.delete('recent_files', where: 'path = ?', whereArgs: <Object?>[path]);

  Future<void> clearRecents() => _db.delete('recent_files');

  // ----------------------------------------------------------- guest usage

  /// How many of [meter] a guest has spent in the current month.
  ///
  /// Rolls the counter over when the calendar month changes, so the reset does
  /// not depend on a background task ever having run.
  Future<int> guestUsed(GuestMeter meter) async {
    final int periodStart = _currentPeriodStart();
    final List<Map<String, Object?>> rows = await _db.query(
      'guest_usage',
      where: 'meter = ?',
      whereArgs: <Object?>[meter.name],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 0;
    }
    if ((rows.first['period_start'] as int? ?? 0) < periodStart) {
      await _db.delete(
        'guest_usage',
        where: 'meter = ?',
        whereArgs: <Object?>[meter.name],
      );
      return 0;
    }
    return (rows.first['used'] as int?) ?? 0;
  }

  /// Spends one unit and returns the new total.
  Future<int> bumpGuestUsage(GuestMeter meter) async {
    final int used = await guestUsed(meter) + 1;
    await _db.insert(
      'guest_usage',
      <String, Object?>{
        'meter': meter.name,
        'used': used,
        'period_start': _currentPeriodStart(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return used;
  }

  Future<bool> guestHasQuota(GuestMeter meter) async =>
      await guestUsed(meter) < meter.freeLimit;

  // --------------------------------------------------------- install usage

  /// How many of [meter] this install has ever spent.
  Future<int> installUsed(InstallMeter meter) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'install_usage',
      where: 'meter = ?',
      whereArgs: <Object?>[meter.name],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['used'] as int?) ?? 0;
  }

  /// Spends one unit and returns the new total.
  ///
  /// Written as a single SQL upsert rather than read-then-write: the scanner
  /// can finish two PDFs at once if the user taps twice on a fast device, and
  /// two interleaved read-modify-writes would both read 2 and both write 3.
  Future<int> bumpInstallUsage(InstallMeter meter) async {
    await _db.rawInsert(
      '''
      INSERT INTO install_usage (meter, used, updated_at)
           VALUES (?, 1, ?)
      ON CONFLICT(meter) DO UPDATE SET
           used = used + 1,
           updated_at = excluded.updated_at
      ''',
      <Object?>[meter.name, DateTime.now().millisecondsSinceEpoch],
    );
    return installUsed(meter);
  }

  /// How many are left, floored at zero.
  Future<int> installRemaining(InstallMeter meter) async {
    final int left = meter.freeLimit - await installUsed(meter);
    return left < 0 ? 0 : left;
  }

  Future<bool> installHasQuota(InstallMeter meter) async =>
      await installUsed(meter) < meter.freeLimit;

  // ------------------------------------------------------------------ admin

  /// Called when the session ends or the signed-in user changes.
  ///
  /// `providers.dart` promises that "the next account never sees the previous
  /// one's documents" — this is the half of that promise which lives on disk.
  /// Guest counters go too: they belong to whoever was holding the phone, and
  /// carrying them across a sign-in would meter a paying user against the free
  /// tier.
  ///
  /// `install_usage` is deliberately NOT cleared. It records what this install
  /// has spent, not what this session has, and wiping it here would make "sign
  /// out and back in" a one-tap reset of the scanner's free trial.
  Future<void> wipeAll() async {
    await _db.delete('recent_files');
    await _db.delete('guest_usage');
    Log.info('Local database wiped (install counters preserved)');
  }

  Future<void> close() => _db.close();

  /// Midnight UTC on the first of the current month, in epoch ms.
  static int _currentPeriodStart() {
    final DateTime now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month).millisecondsSinceEpoch;
  }
}
