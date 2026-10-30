// paths_test.dart — one test() per IdeIntegration variant, per dartrix's
// testing paradigm: a loop here would collapse every variant's pass/fail
// into one result and hide failures after the first.

import 'package:claudart/errors/claudart_exception.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/config/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('workspacesRootFor', () {
    const home = '/home/owner';

    test('an explicit CLAUDART_WORKSPACE is used as it is', () {
      expect(
        workspacesRootFor({claudartWorkspaceEnvVar: '/work/space'}),
        '/work/space',
      );
    });

    test('a leading ~/ is expanded with HOME', () {
      expect(
        workspacesRootFor({
          claudartWorkspaceEnvVar: '~/claude',
          homeEnvVar: home,
        }),
        '$home/claude',
      );
    });

    test('with no override the root is .claudart under HOME', () {
      expect(workspacesRootFor({homeEnvVar: home}), '$home/.claudart');
    });

    test('an empty CLAUDART_WORKSPACE counts as unset', () {
      expect(
        workspacesRootFor({claudartWorkspaceEnvVar: '', homeEnvVar: home}),
        '$home/.claudart',
      );
    });

    test('an explicit absolute root needs no HOME at all', () {
      expect(
        () => workspacesRootFor({claudartWorkspaceEnvVar: '/work/space'}),
        returnsNormally,
      );
    });

    test('no override and no HOME is a typed failure, not a null error', () {
      expect(
        () => workspacesRootFor({}),
        throwsA(
          isA<ClaudartException>().having(
            (e) => e.failureType,
            'failureType',
            FailureType.homeDirectoryUnset,
          ),
        ),
      );
    });

    test('a ~/ override with no HOME is the same typed failure', () {
      expect(
        () => workspacesRootFor({claudartWorkspaceEnvVar: '~/claude'}),
        throwsA(isA<ClaudartException>()),
      );
    });
  });

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
