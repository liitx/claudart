import 'dart:io';

import 'package:claudart/file_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _writerScript = 'test/helpers/append_lines.dart';

void main() {
  const io = RealFileIO();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('claudart_file_io_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('RealFileIO.write', () {
    test('creates the parent directories and the file', () {
      final path = p.join(dir.path, 'a', 'b', 'f.txt');
      io.write(path, 'one');
      expect(File(path).readAsStringSync(), 'one');
    });

    test('replaces existing content completely', () {
      final path = p.join(dir.path, 'f.txt');
      io.write(path, 'a long first version');
      io.write(path, 'short');
      expect(File(path).readAsStringSync(), 'short');
    });

    test('leaves no staging file behind', () {
      final path = p.join(dir.path, 'f.txt');
      io.write(path, 'one');
      io.write(path, 'two');
      expect(
        dir.listSync().map((e) => p.basename(e.path)),
        ['f.txt'],
      );
    });
  });

  group('RealFileIO.append', () {
    test('creates the file and the parent directories', () {
      final path = p.join(dir.path, 'a', 'f.log');
      io.append(path, 'one\n');
      expect(File(path).readAsStringSync(), 'one\n');
    });

    test('adds to the end without touching what is there', () {
      final path = p.join(dir.path, 'f.log');
      io.write(path, 'first\n');
      io.append(path, 'second\n');
      io.append(path, 'third\n');
      expect(File(path).readAsStringSync(), 'first\nsecond\nthird\n');
    });

    test('leaves no staging file behind', () {
      final path = p.join(dir.path, 'f.log');
      io.append(path, 'one\n');
      expect(
        dir.listSync().map((e) => p.basename(e.path)),
        ['f.log'],
      );
    });

    // Separate processes, not isolates: the file lock is per process.
    test('several processes appending at once lose no line', () async {
      final path = p.join(dir.path, 'shared.log');
      const writers = 4;
      const linesPerWriter = 200;
      final results = await Future.wait([
        for (var writer = 0; writer < writers; writer++)
          Process.run(Platform.resolvedExecutable, [
            _writerScript,
            path,
            '$writer',
            '$linesPerWriter',
          ]),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      final lines =
          File(path).readAsLinesSync().where((l) => l.isNotEmpty).toList();
      expect(lines.length, writers * linesPerWriter);
      expect(lines.toSet().length, lines.length, reason: 'a line was doubled');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('RealFileIO.withExclusiveLock', () {
    const counterScript = 'test/helpers/increment_counter.dart';

    test('returns what the body returns', () {
      expect(io.withExclusiveLock(p.join(dir.path, 'f'), () => 42), 42);
    });

    test('runs the body once, with its effects visible after', () {
      final path = p.join(dir.path, 'f.txt');
      io.withExclusiveLock(path, () => io.write(path, 'inside'));
      expect(File(path).readAsStringSync(), 'inside');
    });

    test('creates the parent directory', () {
      final path = p.join(dir.path, 'a', 'b', 'f');
      io.withExclusiveLock(path, () {});
      expect(Directory(p.join(dir.path, 'a', 'b')).existsSync(), isTrue);
    });

    test('a throwing body propagates and the lock is released', () {
      final path = p.join(dir.path, 'f');
      expect(
        () => io.withExclusiveLock(path, () => throw StateError('boom')),
        throwsStateError,
      );
      // A held lock would block this forever; it returns.
      expect(io.withExclusiveLock(path, () => 'again'), 'again');
    });

    Future<int> countWith(String mode) async {
      final path = p.join(dir.path, 'counter.txt');
      const writers = 4;
      const times = 100;
      final results = await Future.wait([
        for (var i = 0; i < writers; i++)
          Process.run(Platform.resolvedExecutable, [
            counterScript,
            path,
            '$times',
            mode,
          ]),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      return int.parse(File(path).readAsStringSync().trim());
    }

    // Separate processes: the lock is per process.
    test('read-modify-writes from several processes lose no update', () async {
      expect(await countWith('lock'), 4 * 100);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('the same read-modify-writes without the lock do lose updates',
        () async {
      expect(await countWith('nolock'), lessThan(4 * 100));
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
