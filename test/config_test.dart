import 'package:test/test.dart';
import 'dart:convert';
import 'package:claudart/config.dart';
import 'package:claudart/paths.dart';
import 'helpers/mocks.dart';

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

  group('ProjectConfig — stepTimeoutMinutes (absent and 0 are different states)', () {
    ProjectConfig parse(Map<String, dynamic> json) => ProjectConfig.fromJson(json);

    test('absent means "use the default": 15 minutes', () {
      final cfg = parse({});
      expect(cfg.stepTimeoutMinutes, isNull);
      expect(cfg.stepTimeout, const Duration(minutes: 15));
      expect(cfg.stepTimeout, defaultStepTimeout);
    });

    test('an explicit 0 means "no timeout", NOT the default', () {
      final cfg = parse({'stepTimeoutMinutes': 0});
      expect(cfg.stepTimeoutMinutes, 0);
      expect(cfg.stepTimeout, isNull);
    });

    test('a positive number is that many minutes', () {
      expect(parse({'stepTimeoutMinutes': 5}).stepTimeout, const Duration(minutes: 5));
      expect(parse({'stepTimeoutMinutes': 1}).stepTimeout, const Duration(minutes: 1));
    });

    test('a value that is not a non-negative integer is treated as unset, not guessed at', () {
      for (final bad in <Object?>[-3, 2.5, '10', true, null, <int>[]]) {
        final cfg = parse({'stepTimeoutMinutes': bad});
        expect(cfg.stepTimeoutMinutes, isNull, reason: '$bad');
        expect(cfg.stepTimeout, defaultStepTimeout, reason: '$bad');
      }
    });

    test('toJson writes the key only when it was set, and keeps an explicit 0', () {
      expect(const ProjectConfig().toJson().containsKey('stepTimeoutMinutes'), isFalse);
      expect(const ProjectConfig(stepTimeoutMinutes: 0).toJson()['stepTimeoutMinutes'], 0);
      expect(const ProjectConfig(stepTimeoutMinutes: 7).toJson()['stepTimeoutMinutes'], 7);
    });

    test('round-trips through json, including the zero state', () {
      for (final minutes in [null, 0, 1, 30]) {
        final back = ProjectConfig.fromJson(ProjectConfig(stepTimeoutMinutes: minutes).toJson());
        expect(back.stepTimeoutMinutes, minutes);
      }
    });

    test('copyWith keeps or replaces it', () {
      const base = ProjectConfig(stepTimeoutMinutes: 9);
      expect(base.copyWith(scanScope: 'full').stepTimeoutMinutes, 9);
      expect(base.copyWith(stepTimeoutMinutes: 2).stepTimeoutMinutes, 2);
    });

    test('loadWorkspaceConfig reads it from the workspace config.json', () {
      const ws = '/ws/proj';
      final io = MemoryFileIO(files: {configPathFor(ws): jsonEncode({'stepTimeoutMinutes': 0})});
      expect(loadWorkspaceConfig(ws, io: io).stepTimeout, isNull);
      expect(loadWorkspaceConfig('/ws/none', io: MemoryFileIO()).stepTimeout, defaultStepTimeout);
      expect(loadWorkspaceConfig(ws, io: MemoryFileIO(files: {configPathFor(ws): '{ not json'})).stepTimeout,
          defaultStepTimeout);
    });
  });
}
