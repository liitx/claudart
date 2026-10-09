import 'dart:io';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claudart/git_utils.dart';
import 'helpers/mocks.dart';

void main() {
  setUpAll(registerFallbacks);

  group('detectGitContext', () {
    // Found by mutation testing (#70): this function had zero direct
    // tests before -- only exercised indirectly through callers, which
    // gave it full line coverage while 10/15 real mutations to its args
    // list and guard condition went completely undetected.
    test('matches real `git rev-parse` output inside this repo', () {
      final result = Process.runSync(
        'git',
        ['rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD'],
      );
      final lines = (result.stdout as String).trim().split('\n');
      final expectedRoot = lines[0].trim();
      final expectedBranch = lines[1].trim();

      final context = detectGitContext();
      if (expectedBranch == 'HEAD') {
        // Detached HEAD — same case this function itself treats as "no
        // branch," so it must agree by also returning null.
        expect(context, isNull);
      } else {
        expect(context, isNotNull);
        expect(context!.root, expectedRoot);
        expect(context.branch, expectedBranch);
      }
    });

    test('returns null when git rev-parse exits non-zero', () {
      final runner = MockProcessRunner();
      when(() => runner.runSync(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(fakeResult('', exitCode: 128));
      expect(detectGitContext(runner: runner), isNull);
    });

    test('returns null for detached HEAD (abbrev-ref reports literal "HEAD")', () {
      final runner = MockProcessRunner();
      when(() => runner.runSync(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(fakeResult('/repo/root\nHEAD\n'));
      expect(detectGitContext(runner: runner), isNull);
    });

    test('returns null when branch is empty', () {
      // `.trim()` on the whole blob strips leading/trailing blank lines, so
      // an empty root (lines[0]) can't actually occur in practice -- it
      // would be swallowed by the earlier `lines.length < 2` guard before
      // this condition is ever reached. A third line keeps the middle
      // (branch) line from being trimmed away while staying empty.
      final runner = MockProcessRunner();
      when(() => runner.runSync(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(fakeResult('/repo/root\n\nextra\n'));
      expect(detectGitContext(runner: runner), isNull);
    });

    test('parses root and branch from a successful rev-parse', () {
      final runner = MockProcessRunner();
      when(() => runner.runSync(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(fakeResult('/repo/root\nfeature/x\n'));
      final context = detectGitContext(runner: runner);
      expect(context, isNotNull);
      expect(context!.root, '/repo/root');
      expect(context.branch, 'feature/x');
    });

    test('calls rev-parse with the exact args this function depends on', () {
      // Pinned as independent literals, not gitEnvClearExecutable/
      // gitEnvClearArgs -- reading the same constants being verified would
      // make this a tautological test: a mutation to those constants
      // mutates both sides of the assertion identically and can never be
      // caught. Confirmed real: this is exactly what happened before this
      // fix (mutation testing's own report showed this exact case
      // surviving undetected).
      final runner = MockProcessRunner();
      when(() => runner.runSync(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenReturn(fakeResult('/repo/root\nmain\n'));
      detectGitContext(runner: runner);
      final captured = verify(() => runner.runSync(
            captureAny(),
            captureAny(),
            workingDirectory: captureAny(named: 'workingDirectory'),
          )).captured;
      expect(captured[0], 'env');
      expect(captured[1], [
        '-u', 'GIT_DIR', '-u', 'GIT_WORK_TREE', '-u', 'GIT_INDEX_FILE',
        'git', 'rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD',
      ]);
    });
  });

  group('readGitAuthor', () {
    test('matches real `git config user.name`/`user.email` output', () {
      // Real subprocess, no mocking — matches detectGitContext()'s own
      // untested-in-isolation convention. `git config` falls back to
      // global scope even outside a repo, so this isn't testable against
      // a "no config at all" case without sandboxing $HOME; instead,
      // assert readGitAuthor agrees with a direct `git config` call.
      final expectedName =
          Process.runSync('git', ['config', GitConfigKey.userName.gitKey]).stdout.toString().trim();
      final expectedEmail =
          Process.runSync('git', ['config', GitConfigKey.userEmail.gitKey]).stdout.toString().trim();

      final author = readGitAuthor('.');
      expect(author.name, expectedName.isEmpty ? isNull : equals(expectedName));
      expect(author.email, expectedEmail.isEmpty ? isNull : equals(expectedEmail));
    });

    test('does not throw for a nonexistent directory', () {
      expect(() => readGitAuthor('/nonexistent/path/xyz'), returnsNormally);
    });
  });

  group('GitConfigKey', () {
    test('userName maps to user.name', () {
      expect(GitConfigKey.userName.gitKey, 'user.name');
    });

    test('userEmail maps to user.email', () {
      expect(GitConfigKey.userEmail.gitKey, 'user.email');
    });

    test('hooksPath maps to core.hooksPath', () {
      expect(GitConfigKey.hooksPath.gitKey, 'core.hooksPath');
    });
  });

  group('readGitConfig / writeGitConfig', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('git_utils_test_');
      Process.runSync('git', ['init', '-q'], workingDirectory: tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writeGitConfig then readGitConfig round-trips a value', () {
      writeGitConfig(GitConfigKey.hooksPath, '.githooks', workingDirectory: tmp.path);
      expect(
        readGitConfig(GitConfigKey.hooksPath, workingDirectory: tmp.path),
        '.githooks',
      );
    });

    test('readGitConfig returns null for an unset key', () {
      expect(readGitConfig(GitConfigKey.hooksPath, workingDirectory: tmp.path), isNull);
    });

    test('readGitConfig does not throw for a nonexistent directory', () {
      expect(
        () => readGitConfig(GitConfigKey.userName, workingDirectory: '/nonexistent/path/xyz'),
        returnsNormally,
      );
    });

    test('writeGitConfig does not throw for a nonexistent directory', () {
      expect(
        () => writeGitConfig(GitConfigKey.hooksPath, '.githooks',
            workingDirectory: '/nonexistent/path/xyz'),
        returnsNormally,
      );
    });
  });
}
