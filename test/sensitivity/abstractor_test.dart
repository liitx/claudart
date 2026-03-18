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
        'AudioBloc handles audio playback',
        map,
        detector,
      );
      expect(result, contains('Bloc:A'));
      expect(result, isNot(contains('AudioBloc')));
    });

    test('abstract leaves safe terms untouched', () {
      const text = 'String name = "hello";';
      final result = abs.abstract(text, map, detector);
      expect(result, equals(text));
    });

    test('deabstract restores original', () {
      final abstractedText = abs.abstract(
        'AudioBloc handles audio',
        map,
        detector,
      );
      final restored = abs.deabstract(abstractedText, map);
      expect(restored, contains('AudioBloc'));
    });

    test('isNotSensitive returns true when no sensitive tokens remain', () {
      const text = 'String name = "test"; int count = 0;';
      expect(abs.isNotSensitive(text, detector), isTrue);
    });

    test('isNotSensitive returns false when sensitive token present', () {
      const text = 'AudioBloc bloc = AudioBloc();';
      expect(abs.isNotSensitive(text, detector), isFalse);
    });

    test('round-trip abstract→deabstract preserves text structure', () {
      const original = 'VehicleBloc extends Bloc<VehicleEvent, VehicleState>';
      final abstracted = abs.abstract(original, map, detector);
      final restored = abs.deabstract(abstracted, map);
      expect(restored, equals(original));
    });

    test('abstract handles multiple different sensitive tokens', () {
      const text = 'VehicleBloc uses VehicleRepository to fetch VehicleModel';
      final result = abs.abstract(text, map, detector);
      expect(result, isNot(contains('VehicleBloc')));
      expect(result, isNot(contains('VehicleRepository')));
      expect(result, isNot(contains('VehicleModel')));
    });

    test('second abstract call uses same token for same real name', () {
      abs.abstract('AudioBloc is here', map, detector);
      final result2 = abs.abstract('AudioBloc again', map, detector);
      expect(result2, contains('Bloc:A'));
    });
  });
}
