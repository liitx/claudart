import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/link.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _projectName = 'my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

MemoryFileIO _emptyIO() => MemoryFileIO();

void main() {
  group('link — new project registration', () {
    test('adds entry to registry', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false, // no sensitivity
        exitFn: _throwExit,
      );
      final registry = Registry.load(io: io);
      expect(registry.findByName(_projectName), isNotNull);
    });

    test('entry has correct projectRoot', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.projectRoot, equals(_projectRoot));
    });

    test('entry workspacePath resolves to workspaceFor(name)', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.workspacePath, equals(workspaceFor(_projectName)));
    });

    test('creates workspace directory', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.dirExists(workspaceFor(_projectName)), isTrue);
    });

    test('creates .claude symlink in project root', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isTrue);
    });

    test('adds .claude to .gitignore when not present', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, contains('.claude'));
    });

    test('does not duplicate .claude in .gitignore', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '.claude\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });
  });

  group('link — sensitivity mode', () {
    test('sensitivityMode false when user declines', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.sensitivityMode, isFalse);
    });

    test('sensitivityMode true when user accepts', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.sensitivityMode, isTrue);
    });
  });

  group('link — re-linking existing project', () {
    test('does not create duplicate registry entry', () async {
      final io = _emptyIO();
      // Register once.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      // Re-link.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false, // decline change, decline enable
        exitFn: _throwExit,
      );
      final entries = Registry.load(io: io).entries;
      expect(entries.where((e) => e.name == _projectName), hasLength(1));
    });

    test('preserves createdAt on re-link', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final original = Registry.load(io: io).findByName(_projectName)!.createdAt;

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final updated = Registry.load(io: io).findByName(_projectName)!.createdAt;
      expect(updated, equals(original));
    });

    test('replaces existing symlink', () async {
      final io = _emptyIO();
      // Plant a stale symlink.
      io.links.add(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      // Symlink should still exist (recreated).
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isTrue);
    });

    test('can update sensitivityMode on re-link', () async {
      final io = _emptyIO();
      // First link — sensitivity off.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(
        Registry.load(io: io).findByName(_projectName)!.sensitivityMode,
        isFalse,
      );

      // Re-link — accept change, enable sensitivity.
      var confirmCall = 0;
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) {
          confirmCall++;
          // Q1: "Change sensitivity mode?" → yes
          // Q2: "Enable sensitivity mode?" → yes
          return true;
        },
        exitFn: _throwExit,
      );
      expect(
        Registry.load(io: io).findByName(_projectName)!.sensitivityMode,
        isTrue,
      );
      // confirmFn was called at least twice: once to change, once to enable.
      expect(confirmCall, greaterThanOrEqualTo(2));
    });

    test('skips symlink when .claude is a real directory', () async {
      final io = _emptyIO();
      // Pre-create .claude as a real directory in project root.
      io.createDir(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      // Registration should succeed.
      final entry = Registry.load(io: io).findByName(_projectName);
      expect(entry, isNotNull);
      expect(entry!.projectRoot, equals(_projectRoot));

      // .claude directory should still exist (not replaced).
      expect(io.dirExists(p.join(_projectRoot, '.claude')), isTrue);

      // No symlink should be created.
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isFalse);

      // Workspace directory should still be created.
      expect(io.dirExists(workspaceFor(_projectName)), isTrue);
    });

    test('does not add .claude to .gitignore when it is a real directory', () async {
      final io = _emptyIO();
      io.createDir(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, isNot(contains('.claude')));
    });

    test('syncs command templates into a real .claude/commands/ directory', () async {
      final io = _emptyIO();
      final realCmdsDir = p.join(_projectRoot, '.claude', 'commands');
      // Pre-create .claude as a real directory with a stale legacy command
      // file — carries the marker, so it's a stale claudart template, not
      // user content, and should still be synced.
      io.createDir(realCmdsDir);
      io.write(p.join(realCmdsDir, 'debug.md'), 'stale content\nclaudart: generated\n');

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      // The legacy filename is kept (not deleted) but its content is synced —
      // not left stale.
      expect(io.fileExists(p.join(realCmdsDir, 'debug.md')), isTrue);
      expect(io.read(p.join(realCmdsDir, 'debug.md')), isNot(equals('stale content\nclaudart: generated\n')));

      // The suffixed filename should now exist with identical content — 1:1.
      final suffixed = io.read(p.join(realCmdsDir, 'debug-$_projectName.md'));
      expect(suffixed, equals(io.read(p.join(realCmdsDir, 'debug.md'))));
    });

    test('does not clobber a user command with the same name', () async {
      final io = _emptyIO();
      final realCmdsDir = p.join(_projectRoot, '.claude', 'commands');
      io.createDir(realCmdsDir);
      // The user's own suggest.md — no claudart marker, must survive.
      io.write(p.join(realCmdsDir, 'suggest.md'), '# My own suggest command\n');

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      expect(
        io.read(p.join(realCmdsDir, 'suggest.md')),
        equals('# My own suggest command\n'),
      );
    });
  });

  group('link — .gitignore edge cases', () {
    test('creates .gitignore when missing', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.fileExists(p.join(_projectRoot, '.gitignore')), isTrue);
    });

    test('appends to existing .gitignore without clobbering', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '*.log\nbuild/\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, contains('*.log'));
      expect(gitignore, contains('.claude'));
    });

    test('recognises .claude/ (trailing slash) as already present', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '.claude/\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });

    test('recognises /.claude (leading slash) as already present', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '/.claude\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });
  });
}
