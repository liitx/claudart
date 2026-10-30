import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:claudart/project/pubspec_utils.dart';
import 'helpers/mocks.dart';

void main() {
  group('readProjectEnv (MemoryFileIO)', () {
    MemoryFileIO fs(String pubspecContent) => MemoryFileIO(
          files: {'/project/pubspec.yaml': pubspecContent},
        );

    test('reads sdk constraint with caret syntax', () {
      final env = readProjectEnv('/project', io: fs('environment:\n  sdk: ^3.8.0\n'));
      expect(env.sdk, '^3.8.0');
      expect(env.flutter, isNull);
    });

    test('reads sdk constraint with range syntax', () {
      final env = readProjectEnv('/project',
          io: fs("environment:\n  sdk: '>=3.0.0 <4.0.0'\n"));
      expect(env.sdk, '>=3.0.0 <4.0.0');
    });

    test('reads both sdk and flutter constraints', () {
      final env = readProjectEnv('/project',
          io: fs('environment:\n  sdk: ^3.8.0\n  flutter: 3.32.5\n'));
      expect(env.sdk, '^3.8.0');
      expect(env.flutter, '3.32.5');
    });

    test('returns nulls when pubspec missing', () {
      final env = readProjectEnv('/project', io: MemoryFileIO());
      expect(env.sdk, isNull);
      expect(env.flutter, isNull);
    });

    test('returns nulls when no environment block', () {
      final env = readProjectEnv('/project',
          io: fs('name: my_app\nversion: 1.0.0\n'));
      expect(env.sdk, isNull);
      expect(env.flutter, isNull);
    });

    test('handles double-quoted sdk constraint', () {
      final env = readProjectEnv('/project',
          io: fs('environment:\n  sdk: ">=2.17.0 <4.0.0"\n'));
      expect(env.sdk, '>=2.17.0 <4.0.0');
    });
  });

  group('readProjectEnv (MockFileIO)', () {
    test('calls fileExists then read on the pubspec path', () {
      final mock = MockFileIO();
      when(() => mock.fileExists('/project/pubspec.yaml')).thenReturn(true);
      when(() => mock.read('/project/pubspec.yaml'))
          .thenReturn('environment:\n  sdk: ^3.8.0\n');

      final env = readProjectEnv('/project', io: mock);
      expect(env.sdk, '^3.8.0');
    });

    test('returns nulls without calling read when file missing', () {
      final mock = MockFileIO();
      when(() => mock.fileExists(any())).thenReturn(false);

      final env = readProjectEnv('/project', io: mock);
      expect(env.sdk, isNull);
      verifyNever(() => mock.read(any()));
    });
  });
}
