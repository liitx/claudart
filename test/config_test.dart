import 'package:test/test.dart';
import 'package:claudart/config.dart';
import 'helpers/mocks.dart';

void main() {
  group('WorkspaceConfig', () {
    test('load returns defaults when file missing', () {
      final io = MemoryFileIO();
      final cfg = loadConfig(io: io);
      expect(cfg.sensitivityMode, isFalse);
      expect(cfg.scanScope, equals('lib'));
      expect(cfg.scanTrigger, equals('on_setup'));
      expect(cfg.diagnosticReporting, isFalse);
      expect(cfg.lastScan, isNull);
      expect(cfg.projectRoot, isNull);
    });

    test('load parses all fields correctly', () {
      final io = MemoryFileIO(files: {
        configPath: '{"sensitivityMode":true,"scanScope":"full",'
            '"scanTrigger":"on_demand","diagnosticReporting":true,'
            '"lastScan":"2026-03-16T10:00:00Z",'
            '"projectRoot":"/home/user/project"}',
      });
      final cfg = loadConfig(io: io);
      expect(cfg.sensitivityMode, isTrue);
      expect(cfg.scanScope, equals('full'));
      expect(cfg.scanTrigger, equals('on_demand'));
      expect(cfg.diagnosticReporting, isTrue);
      expect(cfg.lastScan, equals('2026-03-16T10:00:00Z'));
      expect(cfg.projectRoot, equals('/home/user/project'));
    });

    test('save writes valid json', () {
      final io = MemoryFileIO();
      const cfg = WorkspaceConfig(
        sensitivityMode: true,
        scanScope: 'full',
        scanTrigger: 'on_demand',
        diagnosticReporting: true,
        lastScan: '2026-03-16T10:00:00Z',
        projectRoot: '/tmp/proj',
      );
      saveConfig(cfg, io: io);
      final raw = io.read(configPath);
      expect(raw, contains('"sensitivityMode": true'));
      expect(raw, contains('"scanScope": "full"'));
      expect(raw, contains('"projectRoot": "/tmp/proj"'));
    });

    test('round-trip load/save preserves values', () {
      final io = MemoryFileIO();
      const original = WorkspaceConfig(
        sensitivityMode: true,
        scanScope: 'full',
        scanTrigger: 'on_demand',
        diagnosticReporting: false,
        lastScan: '2026-01-01T00:00:00Z',
        projectRoot: '/projects/myapp',
      );
      saveConfig(original, io: io);
      final loaded = loadConfig(io: io);
      expect(loaded.sensitivityMode, equals(original.sensitivityMode));
      expect(loaded.scanScope, equals(original.scanScope));
      expect(loaded.scanTrigger, equals(original.scanTrigger));
      expect(loaded.diagnosticReporting, equals(original.diagnosticReporting));
      expect(loaded.lastScan, equals(original.lastScan));
      expect(loaded.projectRoot, equals(original.projectRoot));
    });

    test('load returns defaults on malformed json', () {
      final io = MemoryFileIO(files: {configPath: 'not-json'});
      final cfg = loadConfig(io: io);
      expect(cfg.sensitivityMode, isFalse);
    });

    test('copyWith produces updated config', () {
      const cfg = WorkspaceConfig();
      final updated = cfg.copyWith(sensitivityMode: true, scanScope: 'full');
      expect(updated.sensitivityMode, isTrue);
      expect(updated.scanScope, equals('full'));
      expect(updated.scanTrigger, equals('on_setup'));
    });
  });
}
