// flow_test.dart — the saved-checkpoint "approve" path must not lose the
// checkpoint if construct fails. Also: a checkpoint whose top-level JSON is
// not a map must be treated as unreadable, not crash uncaught.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:claudart/commands/flow.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/pipeline/pipeline_executor.dart';
import 'package:claudart/registry.dart';
import '../helpers/mocks.dart';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _exitThrows(int code) => throw _ExitException(code);

MemoryFileIO _ioWithRegistry(String projectRoot, String workspace) {
  final registry = Registry.empty().add(RegistryEntry(
    name: 'my-app',
    projectRoot: projectRoot,
    workspacePath: workspace,
    createdAt: '2026-01-01',
    lastSession: '2026-01-01',
  ));
  final io = MemoryFileIO();
  registry.save(io: io);
  return io;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('claudart_flow_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('runFlow — resume from checkpoint, approve, construct fails', () {
    test('checkpoint file survives a failed construct step', () async {
      final workspace = tempDir.path;
      const projectRoot = '/projects/my-app';
      final io = _ioWithRegistry(projectRoot, workspace);

      final checkpointFile = File('$workspace/$flowCheckpointFileName');
      checkpointFile.writeAsStringSync(jsonEncode({
        'createdAt': '2026-01-01T00:00:00',
        'slots': {'plan': 'Do the thing'},
        'bug': 'Something broke',
        'expected': '',
        'projectRoot': projectRoot,
      }));

      // Simulate the construct agent failing (returns null, as a real
      // dead/unauthenticated `claude` CLI would).
      final executor = PipelineExecutor(runner: ({
        required model,
        required systemPrompt,
        required message,
        required workingDir,
      }) async =>
          null);

      _ExitException? caught;
      try {
        await runFlow(
          io: io,
          projectRootOverride: projectRoot,
          exitFn: _exitThrows,
          executor: executor,
          pickFn: (_) => 0, // "approve saved plan"
        );
      } on _ExitException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull, reason: 'construct failure should exit(1)');
      expect(
        checkpointFile.existsSync(),
        isTrue,
        reason: 'the only copy of the plan must not be deleted before '
            'construct has actually succeeded',
      );
    });
  });

  group('runFlow — checkpoint whose top level is not a map', () {
    test('is treated as unreadable rather than crashing', () async {
      final workspace = tempDir.path;
      const projectRoot = '/projects/my-app';
      final io = _ioWithRegistry(projectRoot, workspace);

      final checkpointFile = File('$workspace/$flowCheckpointFileName');
      // Top level is a JSON array, not an object — `as Map<String, dynamic>`
      // throws a TypeError, not a FormatException.
      checkpointFile.writeAsStringSync(jsonEncode([1, 2, 3]));

      _ExitException? caught;
      try {
        await runFlow(
          io: io,
          projectRootOverride: projectRoot,
          exitFn: _exitThrows,
          // No prompt entered → aborts cleanly once past the corrupt
          // checkpoint, instead of throwing an uncaught TypeError.
        );
      } on _ExitException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.code, equals(0));
    });
  });
}
