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

    test('does not touch a real (non-symlink) .claude directory', () {
      final io = MemoryFileIO();
      io.createDir(p.join(_projectRoot, '.claude'));
      runUnlink(io: io, projectRootOverride: _projectRoot);
      expect(io.dirExists(p.join(_projectRoot, '.claude')), isTrue);
    });
  });
}
