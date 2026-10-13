import 'dart:io';

import 'package:claudart/session/session_state.dart';
import 'package:test/test.dart';

// Agent prompts must name a status through HandoffStatus, never by a typed
// string: a typed string can go stale (suggest_template once routed on
// `suggest-needed`, which matches no variant) and nothing ties it to the enum.
// This scans every template and flow-prompt source and fails on any
// hand-typed status.

const _scanned = ['lib/templates', 'lib/pipeline/flows'];

/// A backticked token shaped like a status: catches stale or misspelled ones
/// that match no variant (`suggest-needed`).
final _statusShaped = RegExp(
  r'`((?:suggest|ready-for|debug|needs)-[a-z]+(?:-[a-z]+)?)`',
);

/// Every status typed out by hand in [source]: a status-shaped backticked
/// token, or any real wire value written bare.
Set<String> handTypedStatuses(String source) {
  final wireValues = HandoffStatus.values
      .where((s) => s.isPersisted)
      .map((s) => RegExp.escape(s.value))
      .join('|');
  final bareWire = RegExp('\\b($wireValues)\\b');
  return {
    for (final m in _statusShaped.allMatches(source)) m.group(1)!,
    for (final m in bareWire.allMatches(source)) m.group(1)!,
  };
}

List<File> _sources() => [
      for (final dir in _scanned)
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ]..sort((a, b) => a.path.compareTo(b.path));

void main() {
  group('handTypedStatuses', () {
    test('finds a stale backticked status that matches no variant', () {
      expect(handTypedStatuses('route on `suggest-needed` here'), {
        'suggest-needed',
      });
    });

    test('finds a real wire value written bare', () {
      expect(handTypedStatuses('## Status\nready-for-suggest\n'), {
        'ready-for-suggest',
      });
    });

    test('finds a real wire value written backticked, once', () {
      expect(handTypedStatuses('is `ready-for-debug` or `ready-for-debug`'), {
        'ready-for-debug',
      });
    });

    test('ignores a status named through the enum', () {
      expect(
        handTypedStatuses('is `\${HandoffStatus.readyForDebug.value}` now'),
        isEmpty,
      );
    });

    test('ignores ordinary hyphenated words', () {
      expect(handTypedStatuses('debug-log and ready-made are not statuses'),
          isEmpty);
    });
  });

  group('no hand-typed status in an agent prompt source', () {
    for (final file in _sources()) {
      test(file.path, () {
        expect(handTypedStatuses(file.readAsStringSync()), isEmpty);
      });
    }
  });
}
