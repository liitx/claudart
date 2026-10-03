import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/unlink.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';

void main() {
  group('unlink — resolves project root like link does', () {
    test('finds the symlink via projectRootOverride, ignoring cwd', () {
      final io = MemoryFileIO(links: {p.join(_projectRoot, '.claude')});
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isFalse);
    });
  });

  group('unlink — removes what link created', () {
    test('removes the .claude symlink', () {
      final io = MemoryFileIO(links: {p.join(_projectRoot, '.claude')});
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isFalse);
    });

    test('removes the .cursor/commands symlink', () {
      final io = MemoryFileIO(
        links: {p.join(_projectRoot, '.cursor', 'commands')},
      );
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(
        io.linkExists(p.join(_projectRoot, '.cursor', 'commands')),
        isFalse,
      );
    });

    test('removes a legacy CLAUDE.md symlink', () {
      final io = MemoryFileIO(links: {p.join(_projectRoot, 'CLAUDE.md')});
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.linkExists(p.join(_projectRoot, 'CLAUDE.md')), isFalse);
    });

    test('removes all of them when all are symlinks', () {
      final io = MemoryFileIO(
        links: {
          p.join(_projectRoot, '.claude'),
          p.join(_projectRoot, 'CLAUDE.md'),
          p.join(_projectRoot, '.cursor', 'commands'),
        },
      );
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isFalse);
      expect(io.linkExists(p.join(_projectRoot, 'CLAUDE.md')), isFalse);
      expect(
        io.linkExists(p.join(_projectRoot, '.cursor', 'commands')),
        isFalse,
      );
    });
  });

  group('unlink — real directories/files are never deleted', () {
    test('a real .claude/ directory is left alone', () {
      final io = MemoryFileIO(dirs: {p.join(_projectRoot, '.claude')});
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.dirExists(p.join(_projectRoot, '.claude')), isTrue);
    });

    test('a real CLAUDE.md file is left alone', () {
      final io =
          MemoryFileIO(files: {p.join(_projectRoot, 'CLAUDE.md'): '# hi'});
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.fileExists(p.join(_projectRoot, 'CLAUDE.md')), isTrue);
    });
  });

  group('unlink — nothing to remove', () {
    test('does not throw when nothing exists', () {
      final io = MemoryFileIO();
      expect(
        () => runUnlink(io: io, projectRootOverride: _projectRoot),
        returnsNormally,
      );
    });
  });
}
