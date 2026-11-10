// log_file_test.dart — the names of the log files, and where each one lives.
//
// The names are written out here as a spec, because they are a contract with
// whoever reads the logs: renaming one is a change to be seen.

import 'package:claudart/logging/log_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Map<LogFile, String> _fileNameByLogFile = {
  LogFile.interactions: 'interactions.jsonl',
  LogFile.errors: 'errors.jsonl',
  LogFile.transitions: 'transitions.jsonl',
  LogFile.models: 'models.jsonl',
  LogFile.steps: 'steps.jsonl',
  LogFile.gates: 'gates.jsonl',
  LogFile.proofs: 'proofs.jsonl',
  LogFile.planner: 'planner.jsonl',
};

void main() {
  test('every $LogFile has a pinned file name', () {
    expect(_fileNameByLogFile.keys.toSet(), LogFile.values.toSet());
  });

  group('$LogFile.fileName', () {
    for (final file in LogFile.values) {
      test(file.name, () {
        expect(file.fileName, _fileNameByLogFile[file]);
      });
    }

    test('no two log files share a name', () {
      expect(
        LogFile.values.map((file) => file.fileName).toSet().length,
        LogFile.values.length,
      );
    });
  });

  group('logFilePath', () {
    for (final file in LogFile.values) {
      test('${file.name} is inside the logs directory', () {
        final path = logFilePath(p.join('workspace', 'logs'), file);
        expect(p.dirname(path), p.join('workspace', 'logs'));
        expect(p.basename(path), file.fileName);
      });
    }
  });
}
