import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/check_coverage.dart';

const _tracefile = '''
SF:/repo/lib/session/a.dart
LF:10
LH:9
end_of_record
SF:/repo/lib/session/b.dart
LF:10
LH:10
end_of_record
SF:/repo/lib/ui/menu.dart
LF:20
LH:2
end_of_record
SF:/repo/lib/ui_extra/x.dart
LF:5
LH:5
end_of_record
''';

void main() {
  final byFile = countsByFile(_tracefile);

  group('countsByFile', () {
    test('keys each file by its SF path with its found and hit counts', () {
      expect(byFile['/repo/lib/session/a.dart'], (found: 10, hit: 9));
      expect(byFile['/repo/lib/ui/menu.dart'], (found: 20, hit: 2));
      expect(byFile.length, 4);
    });

    test('empty text gives nothing', () {
      expect(countsByFile(''), isEmpty);
    });
  });

  group('sum and percentOf', () {
    test('sum adds found and hit', () {
      expect(sum(byFile.values), (found: 45, hit: 26));
    });

    test('percentOf is hit over found as a percentage', () {
      expect(percentOf((found: 4, hit: 3)), 75);
    });

    test('a count with no lines is 100%, not a division by zero', () {
      expect(percentOf((found: 0, hit: 0)), 100);
    });
  });

  group('countUnder', () {
    test('sums the files in a directory', () {
      expect(countUnder('lib/session', byFile), (found: 20, hit: 19));
    });

    test('a directory name does not match a longer sibling', () {
      expect(countUnder('lib/ui', byFile), (found: 20, hit: 2));
    });

    test('tolerates leading and trailing slashes', () {
      expect(countUnder('/lib/session/', byFile), (found: 20, hit: 19));
    });

    test('a directory that is not traced counts nothing', () {
      expect(countUnder('lib/nope', byFile), (found: 0, hit: 0));
    });
  });

  group('parseDirectoryFloors', () {
    test('reads dir=percent pairs', () {
      expect(
        parseDirectoryFloors(['lib/session=93.5', 'lib/errors=98']),
        {'lib/session': 93.5, 'lib/errors': 98.0},
      );
    });

    test('no arguments gives no floors', () {
      expect(parseDirectoryFloors(const []), isEmpty);
    });
  });

  group('failures', () {
    test('nothing when every floor holds', () {
      expect(
        failures(
          byFile: byFile,
          repoFloor: 55.0,
          directoryFloors: {'lib/session': 90.0},
        ),
        isEmpty,
      );
    });

    test('a repo floor above the total is reported with the counts', () {
      final problems = failures(
        byFile: byFile,
        repoFloor: 60.0,
        directoryFloors: const {},
      );
      expect(problems, [
        'Line coverage 57.8% is below the 60.0% floor (26/45 lines).',
      ]);
    });

    test('a directory floor above its coverage is reported', () {
      final problems = failures(
        byFile: byFile,
        repoFloor: 0,
        directoryFloors: {'lib/session': 96.0},
      );
      expect(problems, [
        'lib/session: 95.0% is below its 96.0% floor (19/20 lines).',
      ]);
    });

    test('a floor exactly met passes', () {
      expect(
        failures(
          byFile: byFile,
          repoFloor: 0,
          directoryFloors: {'lib/session': 95.0},
        ),
        isEmpty,
      );
    });

    test('a directory with no traced lines fails instead of passing quietly',
        () {
      final problems = failures(
        byFile: byFile,
        repoFloor: 0,
        directoryFloors: {'lib/typo': 50.0},
      );
      expect(problems, [
        'lib/typo has no traced lines: check the directory name.',
      ]);
    });

    test('every unmet floor is reported, not only the first', () {
      final problems = failures(
        byFile: byFile,
        repoFloor: 99.0,
        directoryFloors: {'lib/session': 99.0, 'lib/ui': 99.0},
      );
      expect(problems.length, 3);
    });
  });

  test('a repo floor exactly met passes', () {
    final exact = countsByFile('SF:/a.dart\nLF:4\nLH:3\nend_of_record\n');
    expect(
      failures(byFile: exact, repoFloor: 75.0, directoryFloors: const {}),
      isEmpty,
    );
  });

  // The command line, run for real: exit codes and messages are the contract
  // `make check-coverage` and CI rely on.
  group('the script', () {
    final script = p.absolute('tool/check_coverage.dart');
    late Directory work;

    setUp(() => work = Directory.systemTemp.createTempSync('claudart_cov_'));
    tearDown(() => work.deleteSync(recursive: true));

    void writeTrace(String text) {
      Directory(p.join(work.path, 'coverage')).createSync();
      File(p.join(work.path, 'coverage', 'lcov.info')).writeAsStringSync(text);
    }

    ProcessResult run(List<String> args) => Process.runSync(
          Platform.resolvedExecutable,
          [script, ...args],
          workingDirectory: work.path,
        );

    const trace = 'SF:/r/lib/session/a.dart\nLF:10\nLH:9\nend_of_record\n';

    test('no arguments: usage and exit 2', () {
      final result = run(const []);
      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('Usage: dart run tool/check_coverage.dart'),
      );
      expect(result.stderr, contains('[<dir>=<min_percent> ...]'));
    });

    test('no tracefile: exit 2 and it says to run make test-coverage', () {
      final result = run(['80']);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('coverage/lcov.info not found'));
      expect(result.stderr, contains('make test-coverage'));
    });

    test('an empty tracefile: exit 2', () {
      writeTrace('');
      final result = run(['80']);
      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('No coverage data found in coverage/lcov.info.'),
      );
    });

    test('floors met: exit 0 and each floor is printed', () {
      writeTrace(trace);
      final result = run(['80', 'lib/session=85']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        contains('Line coverage 90.0% meets the 80.0% floor (9/10 lines).'),
      );
      expect(
        result.stdout,
        contains('lib/session 90.0% meets its 85.0% floor (9/10 lines).'),
      );
    });

    test('the repo floor missed: exit 1 and the reason on stderr', () {
      writeTrace(trace);
      final result = run(['95']);
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('Line coverage 90.0% is below the 95.0% floor (9/10 lines).'),
      );
    });

    test('a directory floor missed: exit 1 even when the repo floor holds', () {
      writeTrace(trace);
      final result = run(['80', 'lib/session=95']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('lib/session: 90.0% is below its 95.0%'));
      expect(result.stdout, isEmpty);
    });
  });
}
