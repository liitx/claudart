import 'package:test/test.dart';
import 'package:claudart/config.dart';

void main() {
  group('ProjectConfig', () {
    test('fromJson returns defaults for an empty map', () {
      final cfg = ProjectConfig.fromJson(const {});
      expect(cfg.sensitivityMode, isFalse);
      expect(cfg.scanScope, equals(ScanScope.lib));
      expect(cfg.scanTrigger, equals('on_setup'));
      expect(cfg.diagnosticReporting, isFalse);
      expect(cfg.lastScan, isNull);
      expect(cfg.projectRoot, isNull);
      expect(cfg.afterFixCommand, equals('make rebuild'));
    });

    test('fromJson parses all fields correctly', () {
      final cfg = ProjectConfig.fromJson(const {
        'sensitivityMode': true,
        'scanScope': 'full',
        'scanTrigger': 'on_demand',
        'diagnosticReporting': true,
        'lastScan': '2026-03-16T10:00:00Z',
        'projectRoot': '/home/user/project',
        'afterFixCommand': 'dart test',
      });
      expect(cfg.sensitivityMode, isTrue);
      expect(cfg.scanScope, equals('full'));
      expect(cfg.scanTrigger, equals('on_demand'));
      expect(cfg.diagnosticReporting, isTrue);
      expect(cfg.lastScan, equals('2026-03-16T10:00:00Z'));
      expect(cfg.projectRoot, equals('/home/user/project'));
      expect(cfg.afterFixCommand, equals('dart test'));
    });

    test('round-trip toJson/fromJson preserves values', () {
      const original = ProjectConfig(
        sensitivityMode: true,
        scanScope: 'full',
        scanTrigger: 'on_demand',
        diagnosticReporting: false,
        lastScan: '2026-01-01T00:00:00Z',
        projectRoot: '/projects/myapp',
        afterFixCommand: 'dart test',
      );
      final loaded = ProjectConfig.fromJson(original.toJson());
      expect(loaded.sensitivityMode, equals(original.sensitivityMode));
      expect(loaded.scanScope, equals(original.scanScope));
      expect(loaded.scanTrigger, equals(original.scanTrigger));
      expect(loaded.diagnosticReporting, equals(original.diagnosticReporting));
      expect(loaded.lastScan, equals(original.lastScan));
      expect(loaded.projectRoot, equals(original.projectRoot));
      expect(loaded.afterFixCommand, equals(original.afterFixCommand));
    });

    test('copyWith produces updated config', () {
      const cfg = ProjectConfig();
      final updated = cfg.copyWith(sensitivityMode: true, scanScope: 'full');
      expect(updated.sensitivityMode, isTrue);
      expect(updated.scanScope, equals('full'));
      expect(updated.scanTrigger, equals('on_setup'));
    });
  });
}
