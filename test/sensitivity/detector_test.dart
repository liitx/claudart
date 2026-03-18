import 'package:test/test.dart';
import 'package:claudart/sensitivity/detector.dart';

void main() {
  group('SensitivityDetector', () {
    const detector = defaultDetector;

    group('isSensitive', () {
      test('String is not sensitive', () {
        expect(detector.isSensitive('String'), isFalse);
      });

      test('int is not sensitive', () {
        expect(detector.isSensitive('int'), isFalse);
      });

      test('Widget is not sensitive', () {
        expect(detector.isSensitive('Widget'), isFalse);
      });

      test('Future is not sensitive', () {
        expect(detector.isSensitive('Future'), isFalse);
      });

      test('Bloc is not sensitive', () {
        expect(detector.isSensitive('Bloc'), isFalse);
      });

      test('unknown PascalCase term is sensitive', () {
        expect(detector.isSensitive('VolumeBloc'), isTrue);
      });

      test('project-specific repository is sensitive', () {
        expect(detector.isSensitive('RoverRepository'), isTrue);
      });

      test('completely unknown identifier is sensitive', () {
        expect(detector.isSensitive('Xk9TurboWidget'), isTrue);
      });
    });

    group('detectInText', () {
      test('finds sensitive PascalCase identifiers', () {
        const text = 'class VolumeBloc extends Bloc<VolumeEvent, VolumeState>';
        final found = detector.detectInText(text);
        expect(found, contains('VolumeBloc'));
        expect(found, contains('VolumeEvent'));
        expect(found, contains('VolumeState'));
      });

      test('does not flag safe terms', () {
        const text = 'String name = "test"; int count = 0;';
        final found = detector.detectInText(text);
        expect(found, isEmpty);
      });

      test('detects camelCase compound words', () {
        const text = 'final audioRepository = VolumeRepository();';
        final found = detector.detectInText(text);
        expect(found, contains('audioRepository'));
      });

      test('detects multiple sensitive identifiers in snippet', () {
        const text = '''
          class RoverBloc extends Bloc<RoverEvent, RoverState> {
            final RoverRepository repository;
          }
        ''';
        final found = detector.detectInText(text);
        expect(found, contains('RoverBloc'));
        expect(found, contains('RoverEvent'));
        expect(found, contains('RoverState'));
        expect(found, contains('RoverRepository'));
      });

      test('returns empty list for text with no sensitive tokens', () {
        const text = 'void build(BuildContext context) {}';
        final found = detector.detectInText(text);
        expect(found, isEmpty);
      });

      test('no duplicate entries in result', () {
        const text = 'VolumeBloc bloc1; VolumeBloc bloc2;';
        final found = detector.detectInText(text);
        expect(found.where((t) => t == 'VolumeBloc').length, equals(1));
      });
    });
  });
}
