import 'dart:io';
import 'package:test/test.dart';
import 'package:claudart/git_utils.dart';

void main() {
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
