import 'package:test/test.dart';
import 'package:claudart/sensitivity/token_map.dart';
import '../helpers/mocks.dart';

void main() {
  group('TokenMap', () {
    late TokenMap map;

    setUp(() {
      map = TokenMap();
    });

    test('tokenFor assigns new token first time', () {
      final token = map.tokenFor('AudioBloc', 'Bloc');
      expect(token, equals('Bloc:A'));
    });

    test('tokenFor returns same token on second call (stable)', () {
      final first = map.tokenFor('AudioBloc', 'Bloc');
      final second = map.tokenFor('AudioBloc', 'Bloc');
      expect(first, equals(second));
    });

    test('sequential tokens increment correctly', () {
      map.tokenFor('AudioBloc', 'Bloc');
      final second = map.tokenFor('VideoBloc', 'Bloc');
      expect(second, equals('Bloc:B'));
    });

    test('contains returns true after assignment', () {
      expect(map.contains('AudioBloc'), isFalse);
      map.tokenFor('AudioBloc', 'Bloc');
      expect(map.contains('AudioBloc'), isTrue);
    });

    test('realFor reverse lookup works', () {
      map.tokenFor('AudioRepository', 'Repository');
      expect(map.realFor('Repository:A'), equals('AudioRepository'));
    });

    test('realFor returns null for unknown token', () {
      expect(map.realFor('Bloc:Z'), isNull);
    });

    test('deprecated token never reassigned', () {
      map.tokenFor('AudioBloc', 'Bloc');
      map.deprecate('Bloc:A');
      // After deprecation, AudioBloc is removed from forward index
      expect(map.contains('AudioBloc'), isFalse);
      // Assigning a new token for same name gets a new token
      final newToken = map.tokenFor('AudioBloc', 'Bloc');
      expect(newToken, equals('Bloc:B'));
    });

    test('size increments correctly', () {
      expect(map.size, equals(0));
      map.tokenFor('AudioBloc', 'Bloc');
      expect(map.size, equals(1));
      map.tokenFor('VideoBloc', 'Bloc');
      expect(map.size, equals(2));
    });

    test('metaFor returns metadata', () {
      map.tokenFor('AudioBloc', 'Bloc');
      final meta = map.metaFor('Bloc:A');
      expect(meta, isNotNull);
      expect(meta!['r'], equals('AudioBloc'));
    });

    test('setMeta adds extra fields', () {
      map.tokenFor('AudioBloc', 'Bloc');
      map.setMeta('Bloc:A', {'kind': 'cubit'});
      expect(map.metaFor('Bloc:A')!['kind'], equals('cubit'));
    });

    test('round-trip save/load via MemoryFileIO', () {
      final io = MemoryFileIO();
      const path = '/workspace/token_map.json';

      map.tokenFor('AudioBloc', 'Bloc');
      map.tokenFor('AudioRepository', 'Repository');
      map.save(path, io: io);

      final loaded = TokenMap.load(path, io: io);
      expect(loaded.contains('AudioBloc'), isTrue);
      expect(loaded.contains('AudioRepository'), isTrue);
      expect(loaded.realFor('Bloc:A'), equals('AudioBloc'));
      expect(loaded.realFor('Repository:A'), equals('AudioRepository'));
    });

    test('load preserves counters so next token is sequential', () {
      final io = MemoryFileIO();
      const path = '/workspace/token_map.json';

      map.tokenFor('AudioBloc', 'Bloc');
      map.tokenFor('VideoBloc', 'Bloc');
      map.save(path, io: io);

      final loaded = TokenMap.load(path, io: io);
      final next = loaded.tokenFor('RadioBloc', 'Bloc');
      expect(next, equals('Bloc:C'));
    });

    test('load handles empty file gracefully', () {
      final io = MemoryFileIO();
      const path = '/workspace/token_map.json';
      final loaded = TokenMap.load(path, io: io);
      expect(loaded.size, equals(0));
    });
  });
}
