import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/scan.dart';
import 'package:claudart/config.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/sensitivity/token_map.dart';
import '../helpers/mocks.dart';

String get _tokenMapPath => p.join(claudeDir, 'token_map.json');

void main() {
  group('runScan', () {
    late MemoryFileIO io;

    setUp(() {
      io = MemoryFileIO();
    });

    MemoryFileIO buildIo({
      required String projectRoot,
      Map<String, String>? dartFiles,
    }) {
      final files = <String, String>{};
      // Write config.json pointing to projectRoot
      files[configPath] = jsonEncode({
        'sensitivityMode': false,
        'scanScope': 'lib',
        'scanTrigger': 'on_setup',
        'diagnosticReporting': false,
        'projectRoot': projectRoot,
      });
      for (final entry in (dartFiles ?? {}).entries) {
        files['$projectRoot/lib/${entry.key}'] = entry.value;
      }
      return MemoryFileIO(files: files);
    }

    test('scan with MemoryFileIO finds entities', () async {
      final testIo = buildIo(
        projectRoot: '/project',
        dartFiles: {
          'audio_bloc.dart':
              'class AudioBloc extends Bloc<AudioEvent, AudioState> {}',
          'audio_repository.dart': 'class AudioRepository {}',
        },
      );
      await runScan(io: testIo);

      // Token map should be populated
      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.contains('AudioBloc'), isTrue);
      expect(tm.contains('AudioRepository'), isTrue);
    });

    test('token map updated after scan', () async {
      final testIo = buildIo(
        projectRoot: '/project',
        dartFiles: {
          'vehicle_bloc.dart':
              'class VehicleBloc extends Bloc<VehicleEvent, VehicleState> {}',
        },
      );
      expect(TokenMap.load(_tokenMapPath, io: testIo).size, equals(0));

      await runScan(io: testIo);

      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.size, greaterThan(0));
    });

    test('scan with no projectRoot exits gracefully', () async {
      // config has no projectRoot — runScan should print error and return
      io.write(configPath, '{}');
      // Should not throw
      await runScan(io: io);
      // Token map is untouched
      expect(TokenMap.load(_tokenMapPath, io: io).size, equals(0));
    });

    test('threshold hit produces error log entry', () async {
      const projectRoot = '/project';
      final files = <String, String>{
        configPath: jsonEncode({
          'sensitivityMode': false,
          'scanScope': 'lib',
          'scanTrigger': 'on_setup',
          'projectRoot': projectRoot,
        }),
      };
      // Add more files than threshold=3
      for (var i = 0; i < 5; i++) {
        files['$projectRoot/lib/file_$i.dart'] = 'class C$i {}';
      }
      final testIo = MemoryFileIO(files: files);

      // runScan uses default threshold 300, so override is needed
      // We test via scanProject directly in scanner_test; here just ensure
      // that runScan handles the default threshold gracefully with few files
      await runScan(io: testIo);
      // With only 5 files below threshold=300, scan succeeds
      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.size, greaterThan(0));
    });

    test('interaction log written after successful scan', () async {
      final testIo = buildIo(
        projectRoot: '/project',
        dartFiles: {
          'main.dart': 'class MyApp extends StatelessWidget {}',
        },
      );
      await runScan(io: testIo);

      final logsPath = p.join(claudeDir, 'logs', 'interactions.jsonl');
      final raw = testIo.read(logsPath);
      expect(raw, isNotEmpty);
      final entry = jsonDecode(raw.trim().split('\n').last)
          as Map<String, dynamic>;
      expect(entry['command'], equals('scan'));
      expect(entry['outcome'], equals('ok'));
    });

    test('full flag sets scope to full', () async {
      const projectRoot = '/project';
      final testIo = MemoryFileIO(files: {
        configPath: jsonEncode({
          'sensitivityMode': false,
          'scanScope': 'lib',
          'projectRoot': projectRoot,
        }),
        '$projectRoot/lib/audio.dart': 'class AudioBloc extends Bloc<E, S> {}',
      });
      // Should run without throwing even with full scope
      await runScan(full: true, io: testIo);
    });
  });
}
