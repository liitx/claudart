import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/map_cmd.dart';
import 'package:claudart/config/paths.dart';
import '../helpers/mocks.dart';

String _capturePrinted(void Function() action) {
  final output = <String>[];
  runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => output.add(line),
    ),
  );
  return output.join('\n');
}

void main() {
  group('runMap', () {
    late MemoryFileIO io;
    late String workspace;
    late String tokenMapPath;
    late String tokenMapMdPath;

    setUp(() {
      io = MemoryFileIO();
      workspace = p.join(workspacesRoot, 'test-project');
      tokenMapPath = tokenMapPathFor(workspace);
      tokenMapMdPath = p.join(workspace, 'token_map.md');
    });

    test('generates token_map.md from token_map.json', () {
      final tokenData = {
        'Bloc:A': {'r': 'VolumeBloc', 'e': 'BlocEvent:A', 's': 'BlocState:A'},
        'Repository:A': {'r': 'VolumeRepository'},
        'Class:A': {'r': 'Helper', 'deprecated': true},
      };
      io.write(tokenMapPath, jsonEncode(tokenData));

      runMap(io: io, workspacePath: workspace);

      final output = io.read(tokenMapMdPath);
      expect(output, contains('# Token Map'));
      expect(output, contains('VolumeBloc'));
      expect(output, contains('Bloc:A'));
      expect(output, contains('~~deprecated~~'));
      expect(output, contains('2 active'));
    });

    test('handles empty token map gracefully', () {
      io.write(tokenMapPath, '');

      runMap(io: io, workspacePath: workspace);

      expect(io.fileExists(tokenMapMdPath), isFalse);
    });

    test('handles malformed JSON gracefully', () {
      io.write(tokenMapPath, '{invalid json');

      runMap(io: io, workspacePath: workspace);

      expect(io.fileExists(tokenMapMdPath), isFalse);
    });

    test('uses global claudeDir when workspacePath is null', () {
      final globalTokenMapPath = p.join(claudeDir, 'token_map.json');
      final globalTokenMapMdPath = p.join(claudeDir, 'token_map.md');
      final tokenData = {
        'Class:A': {'r': 'Helper'},
      };
      io.write(globalTokenMapPath, jsonEncode(tokenData));

      runMap(io: io, workspacePath: null);

      expect(io.fileExists(globalTokenMapMdPath), isTrue);
      final output = io.read(globalTokenMapMdPath);
      expect(output, contains('Helper'));
    });

    test('writes to per-project workspace when provided', () {
      final tokenData = {
        'Bloc:A': {'r': 'TestBloc'},
      };
      io.write(tokenMapPath, jsonEncode(tokenData));

      runMap(io: io, workspacePath: workspace);

      expect(io.fileExists(tokenMapMdPath), isTrue);
      final globalMdPath = p.join(claudeDir, 'token_map.md');
      expect(io.fileExists(globalMdPath), isFalse);
    });

    test('console-printed "active" count agrees with the markdown body — '
        'both exclude deprecated tokens', () {
      final tokenData = {
        'Bloc:A': {'r': 'VolumeBloc'},
        'Class:A': {'r': 'Helper', 'deprecated': true},
      };
      io.write(tokenMapPath, jsonEncode(tokenData));

      final printed = _capturePrinted(() => runMap(io: io, workspacePath: workspace));
      final markdown = io.read(tokenMapMdPath);

      // The markdown body's "Total" line already computes this correctly
      // (see the first test in this file, "2 active" with 1 deprecated of
      // 3). The console summary printed to the user must not disagree.
      expect(markdown, contains('2 tokens (1 active)'));
      expect(printed, contains('2 tokens (1 active)'));
    });
  });
}
