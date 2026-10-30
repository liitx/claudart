import 'package:claudart/config/environment.dart';
import 'package:test/test.dart';

void main() {
  group('homeDirectoryFrom', () {
    test('returns the home directory when it is set', () {
      expect(homeDirectoryFrom({homeEnvVar: '/home/a'}), '/home/a');
    });

    test('returns null when it is unset', () {
      expect(homeDirectoryFrom({}), isNull);
    });

    test('returns null when it is empty', () {
      expect(homeDirectoryFrom({homeEnvVar: ''}), isNull);
    });
  });
}
