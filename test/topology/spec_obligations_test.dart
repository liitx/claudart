// The stage 3 obligations, each tied to the code that consults it and the
// tests that check it (gap T2, T4). A proof of a table nothing reads proves
// nothing, so an obligation that is built must have: a symbol that runtime code
// reads, a named check, and a named test of its weakened variant. One that is
// not built yet is listed as pending, and the list may only shrink.

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/spec_obligations.dart';

Map<String, String> _readSources() => {
      for (final root in ['lib', 'bin', 'test'])
        if (Directory(root).existsSync())
          for (final file in Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
            file.path: file.readAsStringSync(),
    };

void main() {
  final sources = _readSources();

  group('the checks on an obligation', () {
    const obligation = SpecObligation.totality;

    test('a symbol only tests read is not consulted', () {
      expect(
        isConsulted(obligation, {
          obligation.definedIn: 'List listenersFor() => [];',
          'test/a_test.dart': 'void main() { listenersFor(); }',
        }),
        isFalse,
      );
    });

    test('a symbol read only inside its own file is not consulted', () {
      expect(
        isConsulted(obligation, {
          obligation.definedIn:
              'List listenersFor() => [];\nvar x = listenersFor();',
        }),
        isFalse,
      );
    });

    test('a symbol read by other code under the required folder is consulted',
        () {
      expect(
        isConsulted(obligation, {
          obligation.definedIn: 'List listenersFor() => [];',
          'lib/session/other.dart': 'var x = listenersFor();',
        }),
        isTrue,
      );
    });

    test('a symbol read from the wrong folder is not consulted', () {
      expect(
        isConsulted(SpecObligation.commandAwaitsDrain, {
          'lib/session/handoff_store.dart': 'Future<void> x() => bus.drain();',
        }),
        isFalse,
      );
    });

    test('a test title is found only as a test or group call', () {
      const ref = (file: 'test/a_test.dart', title: 'the title');
      expect(namesTest({'test/a_test.dart': "test('the title', () {});"}, ref),
          isTrue);
      expect(namesTest({'test/a_test.dart': "group('the title', () {});"}, ref),
          isTrue);
      expect(namesTest({'test/a_test.dart': "// 'the title' in a comment"}, ref),
          isFalse);
      expect(namesTest({}, ref), isFalse);
    });
  });

  group('every obligation', () {
    for (final obligation in SpecObligation.values) {
      if (obligation.isBuilt) {
        test('${obligation.name} is consulted by code outside its definition',
            () {
          expect(isConsulted(obligation, sources), isTrue,
              reason: obligation.statement);
        });

        test('${obligation.name} has a check that exists', () {
          expect(obligation.check, isNotNull);
          expect(namesTest(sources, obligation.check!), isTrue,
              reason: '${obligation.check}');
        });

        test('${obligation.name} has a test of its weakened variant', () {
          expect(obligation.weakened, isNotNull);
          expect(namesTest(sources, obligation.weakened!), isTrue,
              reason: '${obligation.weakened}');
        });
      } else {
        test('${obligation.name} is pending and still not consulted', () {
          expect(
            isConsulted(obligation, sources),
            isFalse,
            reason: 'it is consulted now: mark it built and name its checks',
          );
        });
      }
    }
  });
}
