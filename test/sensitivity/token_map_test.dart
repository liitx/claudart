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
      final token = map.tokenFor('VolumeBloc', 'Bloc');
      expect(token, equals('Bloc:A'));
    });

    test('tokenFor returns same token on second call (stable)', () {
      final first = map.tokenFor('VolumeBloc', 'Bloc');
      final second = map.tokenFor('VolumeBloc', 'Bloc');
      expect(first, equals(second));
    });

    test('sequential tokens increment correctly', () {
      map.tokenFor('VolumeBloc', 'Bloc');
      final second = map.tokenFor('PilotBloc', 'Bloc');
      expect(second, equals('Bloc:B'));
    });

    test('contains returns true after assignment', () {
      expect(map.contains('VolumeBloc'), isFalse);
      map.tokenFor('VolumeBloc', 'Bloc');
      expect(map.contains('VolumeBloc'), isTrue);
    });

    test('realFor reverse lookup works', () {
      map.tokenFor('VolumeRepository', 'Repository');
      expect(map.realFor('Repository:A'), equals('VolumeRepository'));
    });

    test('realFor returns null for unknown token', () {
      expect(map.realFor('Bloc:Z'), isNull);
    });

    test('deprecated token never reassigned', () {
      map.tokenFor('VolumeBloc', 'Bloc');
      map.deprecate('Bloc:A');
      // After deprecation, VolumeBloc is removed from forward index
      expect(map.contains('VolumeBloc'), isFalse);
      // Assigning a new token for same name gets a new token
      final newToken = map.tokenFor('VolumeBloc', 'Bloc');
      expect(newToken, equals('Bloc:B'));
    });

    test('size increments correctly', () {
      expect(map.size, equals(0));
      map.tokenFor('VolumeBloc', 'Bloc');
      expect(map.size, equals(1));
      map.tokenFor('PilotBloc', 'Bloc');
      expect(map.size, equals(2));
    });

    test('metaFor returns metadata', () {
      map.tokenFor('VolumeBloc', 'Bloc');
      final meta = map.metaFor('Bloc:A');
      expect(meta, isNotNull);
      expect(meta!['r'], equals('VolumeBloc'));
    });

    test('setMeta adds extra fields', () {
      map.tokenFor('VolumeBloc', 'Bloc');
      map.setMeta('Bloc:A', {'kind': 'cubit'});
      expect(map.metaFor('Bloc:A')!['kind'], equals('cubit'));
    });

    test('round-trip save/load via MemoryFileIO', () {
      final io = MemoryFileIO();
      const path = '/workspace/token_map.json';

      map.tokenFor('VolumeBloc', 'Bloc');
      map.tokenFor('VolumeRepository', 'Repository');
      map.save(path, io: io);

      final loaded = TokenMap.load(path, io: io);
      expect(loaded.contains('VolumeBloc'), isTrue);
      expect(loaded.contains('VolumeRepository'), isTrue);
      expect(loaded.realFor('Bloc:A'), equals('VolumeBloc'));
      expect(loaded.realFor('Repository:A'), equals('VolumeRepository'));
    });

    test('load preserves counters so next token is sequential', () {
      final io = MemoryFileIO();
      const path = '/workspace/token_map.json';

      map.tokenFor('VolumeBloc', 'Bloc');
      map.tokenFor('PilotBloc', 'Bloc');
      map.save(path, io: io);

      final loaded = TokenMap.load(path, io: io);
      final next = loaded.tokenFor('ApexBloc', 'Bloc');
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
