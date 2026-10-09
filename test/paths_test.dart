// paths_test.dart — one test() per IdeIntegration variant, per dartrix's
// testing paradigm: a loop here would collapse every variant's pass/fail
// into one result and hide failures after the first.

import 'package:claudart/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IdeIntegration', () {
    test('claudeCode uses .claude', () {
      expect(IdeIntegration.claudeCode.dirName, '.claude');
    });

    test('cursor uses .cursor', () {
      expect(IdeIntegration.cursor.dirName, '.cursor');
    });
  });

  group('claudeCommandsDirFor', () {
    test('joins the workspace with IdeIntegration.claudeCode and commands', () {
      expect(
        claudeCommandsDirFor('/ws/proj'),
        p.join('/ws/proj', IdeIntegration.claudeCode.dirName, 'commands'),
      );
    });
  });

  group('registryPath', () {
    test('joins workspacesRoot with registryFileName', () {
      expect(registryPath, p.join(workspacesRoot, registryFileName));
    });
  });

  group('configPathFor', () {
    test('joins the workspace with configFileName', () {
      expect(configPathFor('/ws/proj'), p.join('/ws/proj', configFileName));
    });
  });

  group('claudeMdPathFor', () {
    test('joins the project root with claudeMdFileName', () {
      expect(claudeMdPathFor('/proj'), p.join('/proj', claudeMdFileName));
    });
  });
}
