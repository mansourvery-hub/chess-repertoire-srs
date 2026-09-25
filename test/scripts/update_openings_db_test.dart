// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prints the opening count of the database given as argv[1].
const _countOpenings =
    'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]) '
    '.execute("SELECT COUNT(*) FROM openings").fetchone()[0])';

/// Guards the script that builds the bundled opening database.
///
/// The failure this exists for is silent: an empty or truncated source used to delete every
/// opening, commit that, and only then insert nothing. The script exited 0, printed the
/// deletions as a normal diff, and the empty database was what got built into the app. Nothing
/// downstream could tell an empty repertoire apart from a working one.
void main() {
  final script = File('scripts/update_openings_db.py');
  final asset = File('assets/chess_openings.db');

  /// A stand-in for the lichess-org/chess-openings checkout, holding [tsv] as its built output.
  Directory fakeRepo(String tsv) {
    final dir = Directory.systemTemp.createTempSync('chess-openings-');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Makefile').writeAsStringSync('all:\n\t@true\n');
    Directory('${dir.path}/dist').createSync();
    File('${dir.path}/dist/all.tsv').writeAsStringSync(tsv);
    return dir;
  }

  /// A copy of the repository's scripts/ and assets/ layout, so the script resolves the same
  /// relative database path it does in the real tree.
  Directory sandbox() {
    final dir = Directory.systemTemp.createTempSync('openings-db-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/scripts').createSync();
    Directory('${dir.path}/assets').createSync();
    script.copySync('${dir.path}/scripts/update_openings_db.py');
    asset.copySync('${dir.path}/assets/chess_openings.db');
    return dir;
  }

  /// Openings currently in the sandbox database, or -1 if it cannot be read at all.
  int rowsIn(String sandboxPath) {
    final file = File('$sandboxPath/assets/chess_openings.db');
    if (!file.existsSync()) return -1;
    final result = Process.runSync('python3', ['-c', _countOpenings, file.path]);
    return result.exitCode == 0 ? int.parse((result.stdout as String).trim()) : -1;
  }

  ProcessResult runScript(String sandboxPath, Directory repo) => Process.runSync('python3', [
    '$sandboxPath/scripts/update_openings_db.py',
    repo.path,
  ], workingDirectory: sandboxPath);

  setUpAll(() {
    // The script shells out to `make` to build the upstream data, and this test drives it with
    // python3. Where either is missing there is nothing to exercise.
    if (Process.runSync('python3', ['--version']).exitCode != 0) {
      markTestSkipped('python3 is not available');
    }
    if (Process.runSync('make', ['--version']).exitCode != 0) {
      markTestSkipped('make is not available');
    }
  });

  test('an empty source leaves the shipped database alone', () {
    final dir = sandbox();
    final before = rowsIn(dir.path);
    expect(before, greaterThan(0), reason: 'the real asset should not be empty to begin with');

    final result = runScript(dir.path, fakeRepo(''));

    expect(
      result.exitCode,
      isNot(0),
      reason: 'a source with no openings is a failed build, not an update',
    );
    expect(
      rowsIn(dir.path),
      equals(before),
      reason: 'the database that ships with the app was emptied',
    );
  });

  test('a header with no rows leaves the shipped database alone', () {
    final dir = sandbox();
    final before = rowsIn(dir.path);

    final result = runScript(dir.path, fakeRepo('eco\tname\tpgn\tuci\tepd\n'));

    expect(result.exitCode, isNot(0));
    expect(rowsIn(dir.path), equals(before));
  });

  test('a valid source replaces the database', () {
    final dir = sandbox();
    const tsv =
        'eco\tname\tpgn\tuci\tepd\n'
        'A00\tUncommon Opening\t1. a3\ta2a3\t\n'
        'A01\tTest Line\t1. a3 a6 2. Nc3\ta2a3a7a6b1c3\t\n';

    final result = runScript(dir.path, fakeRepo(tsv));

    expect(result.exitCode, 0, reason: '$result.stdout\n$result.stderr');
    expect(rowsIn(dir.path), equals(2), reason: 'the new contents should be what is on disk');
  });

  test('a failed run leaves no temporary database behind', () {
    final dir = sandbox();
    runScript(dir.path, fakeRepo(''));

    final strays = Directory('${dir.path}/assets')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .where((name) => name != 'chess_openings.db')
        .toList();
    expect(strays, isEmpty, reason: 'a partial build was left in the assets directory');
  });
}
