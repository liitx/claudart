import 'package:test/test.dart';
import 'package:claudart/sensitivity/abstractor.dart';
import 'package:claudart/sensitivity/token_map.dart';
import 'package:claudart/sensitivity/detector.dart';
import '../helpers/mocks.dart';

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

  group('abstractTexts', () {
    const path = '/workspace/token_map.json';

    test('two names of the same kind get different tokens', () {
      final io = MemoryFileIO();
      final result = abstractTexts(
        ['VolumeBloc fails', 'ApexBloc fails'],
        tokenMapPath: path,
        io: io,
      );
      expect(result, ['Bloc:A fails', 'Bloc:B fails']);
    });

    test('a token it assigned is saved to the map', () {
      final io = MemoryFileIO();
      abstractTexts(['VolumeBloc fails'], tokenMapPath: path, io: io);
      expect(io.read(path), contains('VolumeBloc'));
    });

    test('text with nothing sensitive leaves no map behind', () {
      final io = MemoryFileIO();
      final result =
          abstractTexts(['nothing to hide here'], tokenMapPath: path, io: io);
      expect(result, ['nothing to hide here']);
      expect(io.fileExists(path), isFalse);
    });

    test('a later call reuses the tokens already saved', () {
      final io = MemoryFileIO();
      abstractTexts(['VolumeBloc fails'], tokenMapPath: path, io: io);
      final result = abstractTexts(
        ['ApexBloc fails', 'VolumeBloc again'],
        tokenMapPath: path,
        io: io,
      );
      expect(result, ['Bloc:B fails', 'Bloc:A again']);
    });

    test('an unreadable map is a typed failure, and is left as it was', () {
      final io = MemoryFileIO(files: {path: '{not valid json'});
      expect(
        () => abstractTexts(['VolumeBloc'], tokenMapPath: path, io: io),
        throwsA(isA<TokenMapUnreadableException>()),
      );
      expect(io.read(path), '{not valid json');
    });
  });
}
