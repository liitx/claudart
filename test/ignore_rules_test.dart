import 'package:test/test.dart';
import 'package:claudart/ignore_rules.dart';
import 'helpers/mocks.dart';

void main() {
  group('IgnoreRules', () {
    const projectRoot = '/project';

    test('default patterns applied when file missing', () {
      final io = MemoryFileIO();
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/config.g.dart'), isTrue);
      expect(rules.shouldIgnore('lib/config.freezed.dart'), isTrue);
      expect(rules.shouldIgnore('lib/config.mocks.dart'), isTrue);
      expect(rules.shouldIgnore('build/outputs/something.dart'), isTrue);
      expect(rules.shouldIgnore('.dart_tool/package_config.json'), isTrue);
    });

    test('*.g.dart ignored by default', () {
      final io = MemoryFileIO();
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/models/config_model.g.dart'), isTrue);
    });

    test('*.freezed.dart ignored by default', () {
      final io = MemoryFileIO();
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/models/state.freezed.dart'), isTrue);
    });

    test('regular .dart files not ignored', () {
      final io = MemoryFileIO();
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/blocs/counter_bloc.dart'), isFalse);
      expect(rules.shouldIgnore('lib/main.dart'), isFalse);
    });

    test('custom patterns from file respected', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/.claudartignore': '*.generated.dart\nlib/vendor/\n',
      });
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/foo.generated.dart'), isTrue);
      expect(rules.shouldIgnore('lib/vendor/some_lib.dart'), isTrue);
      expect(rules.shouldIgnore('lib/counter_bloc.dart'), isFalse);
    });

    test('comments and blank lines in ignore file are ignored', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/.claudartignore': '# this is a comment\n\n*.tmp.dart\n',
      });
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/foo.tmp.dart'), isTrue);
      expect(rules.shouldIgnore('lib/foo.dart'), isFalse);
    });

    test('empty ignore file falls back to defaults', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/.claudartignore': '',
      });
      final rules = loadIgnoreRules(projectRoot, io: io);
      expect(rules.shouldIgnore('lib/config.g.dart'), isTrue);
    });
  });
}
