import 'package:test/test.dart';
import 'package:claudart/sensitivity/abstractor.dart';
import 'package:claudart/sensitivity/token_map.dart';
import 'package:claudart/sensitivity/detector.dart';

void main() {
  group('Abstractor', () {
    late Abstractor abs;
    late TokenMap map;
    const detector = defaultDetector;

    setUp(() {
      abs = Abstractor();
      map = TokenMap();
    });

    test('abstract replaces known sensitive token with mapped token', () {
      final result = abs.abstract(
        'VolumeBloc handles search results',
        map,
        detector,
      );
      expect(result, contains('Bloc:A'));
      expect(result, isNot(contains('VolumeBloc')));
    });

    test('abstract leaves safe terms untouched', () {
      const text = 'String name = "hello";';
      final result = abs.abstract(text, map, detector);
      expect(result, equals(text));
    });

    test('deabstract restores original', () {
      final abstractedText = abs.abstract(
        'VolumeBloc handles search',
        map,
        detector,
      );
      final restored = abs.deabstract(abstractedText, map);
      expect(restored, contains('VolumeBloc'));
    });

    test('isNotSensitive returns true when no sensitive tokens remain', () {
      const text = 'String name = "test"; int count = 0;';
      expect(abs.isNotSensitive(text, detector), isTrue);
    });

    test('isNotSensitive returns false when sensitive token present', () {
      const text = 'VolumeBloc bloc = VolumeBloc();';
      expect(abs.isNotSensitive(text, detector), isFalse);
    });

    test('round-trip abstract→deabstract preserves text structure', () {
      const original = 'RoverBloc extends Bloc<RoverEvent, RoverState>';
      final abstracted = abs.abstract(original, map, detector);
      final restored = abs.deabstract(abstracted, map);
      expect(restored, equals(original));
    });

    test('abstract handles multiple different sensitive tokens', () {
      const text = 'RoverBloc uses RoverRepository to fetch RoverModel';
      final result = abs.abstract(text, map, detector);
      expect(result, isNot(contains('RoverBloc')));
      expect(result, isNot(contains('RoverRepository')));
      expect(result, isNot(contains('RoverModel')));
    });

    test('second abstract call uses same token for same real name', () {
      abs.abstract('VolumeBloc is here', map, detector);
      final result2 = abs.abstract('VolumeBloc again', map, detector);
      expect(result2, contains('Bloc:A'));
    });
  });
}
