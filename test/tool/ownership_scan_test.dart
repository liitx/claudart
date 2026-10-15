import 'package:test/test.dart';

import '../../tool/ownership/ownership_scan.dart';

void main() {
  group('declaredComponents', () {
    test('finds public enums, classes, sealed and abstract classes, mixins',
        () {
      const source = '''
enum Alpha { a }
class Beta {}
sealed class Gamma {}
abstract class Delta {}
abstract final class Epsilon {}
mixin Zeta {}
''';
      expect(
        declaredComponents(source),
        {'Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta'},
      );
    });

    test('ignores private names and indented (nested) declarations', () {
      const source = '''
enum _Hidden { a }
class _AlsoHidden {}
class Outer {
  enum Inner { a }
}
''';
      expect(declaredComponents(source), {'Outer'});
    });

    test('ignores a word in a comment or string', () {
      const source = "// enum Fake\nconst s = 'class Nope';\n";
      expect(declaredComponents(source), isEmpty);
    });
  });

  group('duplicatedComponents', () {
    test('lists names declared in two or more repos, with their owners', () {
      final result = duplicatedComponents({
        'claudart': {'FaultClass', 'HandoffStatus'},
        'zedup': {'FaultClass', 'ZedupTool'},
        'dartrix': {'Dartrix', 'FaultClass'},
      });
      expect(result, {
        'FaultClass': ['claudart', 'dartrix', 'zedup'],
      });
    });

    test('is empty when every name has one owner', () {
      expect(
        duplicatedComponents({
          'a': {'One'},
          'b': {'Two'},
        }),
        isEmpty,
      );
    });
  });

  group('foreignTestReferences', () {
    final files = {
      'test/a_test.dart': '''
expect(HandoffStatus.readyForDebug.expectsDebug, isTrue);
expect(HandoffStatus.fromString('ready-for-debug'), isNotNull);
final fixture = HandoffStatus.needsSuggest;
expect(result.status, equals(HandoffStatus.debugComplete));
''',
      'test/b_test.dart': 'expect(OtherRepoEnum.one.label, isNotEmpty);',
      'test/c_test.dart': 'final r = Registry.empty();',
    };

    test('counts every read of a foreign name per file', () {
      final refs = foreignTestReferences(files, {'HandoffStatus', 'Registry'});
      expect(refs.map((r) => (r.file, r.component, r.reads)), [
        ('test/a_test.dart', 'HandoffStatus', 4),
        ('test/c_test.dart', 'Registry', 1),
      ]);
    });

    test(
        'an assertion is an expect on a member of the foreign value, or on '
        'fromString / parse / values', () {
      final ref = foreignTestReferences(files, {'HandoffStatus'}).single;
      expect(ref.assertions, 2);
      expect(
        ref.assertionSample,
        'expect(HandoffStatus.readyForDebug.expectsDebug, isTrue);',
      );
    });

    test(
        'using a foreign value as a fixture or an expected value is a read, '
        'not an assertion', () {
      final ref = foreignTestReferences(
        {
          'test/x_test.dart':
              files['test/a_test.dart']!.split('\n').skip(2).join('\n')
        },
        {'HandoffStatus'},
      ).single;
      expect(ref.reads, 2);
      expect(ref.assertions, 0);
      expect(ref.assertionSample, isNull);
    });

    test("a repo's own names are not foreign", () {
      expect(foreignTestReferences(files, {'Unrelated'}), isEmpty);
    });
  });
}
