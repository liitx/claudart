import 'package:claudart/dependency_config.dart';
import 'package:test/test.dart';

void main() {
  group('detectsDartrixDependency', () {
    test('true when pubspec.yaml declares a top-level dartrix dependency', () {
      const pubspec = '''
name: my_app
dependencies:
  dartrix:
    git:
      url: https://github.com/liitx/dartrix.git
''';
      expect(detectsDartrixDependency(pubspec), isTrue);
    });

    test('false when pubspec.yaml has no dartrix dependency', () {
      const pubspec = '''
name: my_app
dependencies:
  path: ^1.0.0
''';
      expect(detectsDartrixDependency(pubspec), isFalse);
    });

    test('false when dartrix is only mentioned in prose, not as a dependency key', () {
      const pubspec = '''
name: my_app
description: a project that might one day use dartrix
dependencies:
  path: ^1.0.0
''';
      expect(detectsDartrixDependency(pubspec), isFalse);
    });
  });
}
