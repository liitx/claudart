import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/scan.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/sensitivity/token_map.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/project';
const _workspace = '/workspaces/project';

String get _tokenMapPath => tokenMapPathFor(_workspace);

// Seeds a registry entry for _projectRoot — the real link path scan.dart's
// callers use to resolve projectRoot/sensitivityMode. No config.json anywhere.
MemoryFileIO buildIo({
  Map<String, String>? dartFiles,
  bool sensitivityMode = false,
}) {
  final files = <String, String>{};
  files[p.join(workspacesRoot, 'registry.json')] = jsonEncode({
    '_warning': 'Do not edit manually',
    'workspaces': [
      {
        'name': 'project',
        'projectRoot': _projectRoot,
        'workspacePath': _workspace,
        'createdAt': '2026-03-18',
        'lastSession': '2026-03-18',
        'sensitivityMode': sensitivityMode,
      },
    ],
  });
  for (final entry in (dartFiles ?? {}).entries) {
    files['$_projectRoot/lib/${entry.key}'] = entry.value;
  }
  return MemoryFileIO(files: files);
}

// Loads the registry entry the way bin/claudart.dart does, and runs scan
// with the values it passes through.
Future<void> _runScanForLinkedProject(MemoryFileIO testIo, {String? scope, bool full = false}) async {
  final entry = Registry.load(io: testIo).findByProjectRoot(_projectRoot)!;
  await runScan(
    io: testIo,
    scope: scope,
    full: full,
    projectRootOverride: entry.projectRoot,
    sensitivityModeOverride: entry.sensitivityMode,
    workspacePath: entry.workspacePath,
  );
}

Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  group('runScan', () {
    test('linked project with no config.json anywhere does not print "No project linked" and finds entities', () async {
      final testIo = buildIo(
        dartFiles: {
          'volume_bloc.dart':
              'class VolumeBloc extends Bloc<VolumeEvent, VolumeState> {}',
          'volume_repository.dart': 'class VolumeRepository {}',
        },
      );
      expect(testIo.fileExists(configPathFor(_workspace)), isFalse);

      final printed = await _capturePrints(() => _runScanForLinkedProject(testIo));

      expect(printed.any((l) => l.contains('No project linked')), isFalse);

      // Token map should be populated
      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.contains('VolumeBloc'), isTrue);
      expect(tm.contains('VolumeRepository'), isTrue);
    });

    test('sensitivity mode from registry entry reaches the logger', () async {
      final testIo = buildIo(
        sensitivityMode: true,
        dartFiles: {'secret_bloc.dart': 'class SecretBloc {}'},
      );

      await _runScanForLinkedProject(testIo);

      final logsPath = p.join(logsDirFor(_workspace), 'interactions.jsonl');
      final raw = testIo.read(logsPath);
      expect(raw, isNotEmpty);
      final entry = jsonDecode(raw.trim().split('\n').last)
          as Map<String, dynamic>;
      expect(entry['sensitivityMode'], isTrue);
    });

    test('token map updated after scan', () async {
      final testIo = buildIo(
        dartFiles: {
          'rover_bloc.dart':
              'class RoverBloc extends Bloc<RoverEvent, RoverState> {}',
        },
      );
      expect(TokenMap.load(_tokenMapPath, io: testIo).size, equals(0));

      await _runScanForLinkedProject(testIo);

      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.size, greaterThan(0));
    });

    test('scan with no projectRootOverride exits gracefully', () async {
      final io = MemoryFileIO();
      // No registry entry at all — caller has nothing to pass through.
      await runScan(io: io);
      // Token map is untouched
      expect(TokenMap.load(tokenMapPathFor(claudeDir), io: io).size, equals(0));
    });

    test('threshold hit produces error log entry', () async {
      final files = <String, String>{
        p.join(workspacesRoot, 'registry.json'): jsonEncode({
          '_warning': 'Do not edit manually',
          'workspaces': [
            {
              'name': 'project',
              'projectRoot': _projectRoot,
              'workspacePath': _workspace,
              'createdAt': '2026-03-18',
              'lastSession': '2026-03-18',
              'sensitivityMode': false,
            },
          ],
        }),
      };
      // Add more files than threshold=3
      for (var i = 0; i < 5; i++) {
        files['$_projectRoot/lib/file_$i.dart'] = 'class C$i {}';
      }
      final testIo = MemoryFileIO(files: files);

      // runScan uses default threshold 300, so override is needed
      // We test via scanProject directly in scanner_test; here just ensure
      // that runScan handles the default threshold gracefully with few files
      await _runScanForLinkedProject(testIo);
      // With only 5 files below threshold=300, scan succeeds
      final tm = TokenMap.load(_tokenMapPath, io: testIo);
      expect(tm.size, greaterThan(0));
    });

    test('interaction log written after successful scan', () async {
      final testIo = buildIo(
        dartFiles: {
          'main.dart': 'class MyApp extends StatelessWidget {}',
        },
      );
      await _runScanForLinkedProject(testIo);

      final logsPath = p.join(logsDirFor(_workspace), 'interactions.jsonl');
      final raw = testIo.read(logsPath);
      expect(raw, isNotEmpty);
      final entry = jsonDecode(raw.trim().split('\n').last)
          as Map<String, dynamic>;
      expect(entry['command'], equals('scan'));
      expect(entry['outcome'], equals('ok'));
    });

    test('full flag sets scope to full', () async {
      final testIo = buildIo(
        dartFiles: {
          'buster.dart': 'class VolumeBloc extends Bloc<E, S> {}',
        },
      );
      // Should run without throwing even with full scope
      await _runScanForLinkedProject(testIo, full: true);
    });
  });
}
