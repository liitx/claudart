import 'package:claudart/paths.dart';
import 'package:claudart/workspace/workspace_link_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';

void main() {
  final claude = p.join(_projectRoot, IdeIntegration.claudeCode.dirName);

  group('linkStateOf', () {
    // One case per variant: the filesystem shape that produces it.
    final shapes = <WorkspaceLinkState, MemoryFileIO Function()>{
      WorkspaceLinkState.unlinked: () => MemoryFileIO(),
      WorkspaceLinkState.symlinked: () => MemoryFileIO(links: {claude}),
      WorkspaceLinkState.realDirectory: () => MemoryFileIO(dirs: {claude}),
    };

    test('the table covers every variant', () {
      expect(shapes.keys.toSet(), WorkspaceLinkState.values.toSet());
    });

    for (final entry in shapes.entries) {
      test('${entry.key.name}: read back from its filesystem shape', () {
        expect(linkStateOf(entry.value(), _projectRoot), entry.key);
      });
    }

    test('a path that is both a link and a directory counts as symlinked', () {
      final io = MemoryFileIO(links: {claude}, dirs: {claude});
      expect(linkStateOf(io, _projectRoot), WorkspaceLinkState.symlinked);
    });

    test('only the .claude entry counts, not .cursor', () {
      final cursor = p.join(_projectRoot, IdeIntegration.cursor.dirName);
      final io = MemoryFileIO(links: {cursor});
      expect(linkStateOf(io, _projectRoot), WorkspaceLinkState.unlinked);
    });
  });

  group('WorkspaceLinkState.isLinked', () {
    const linked = {
      WorkspaceLinkState.symlinked,
      WorkspaceLinkState.realDirectory,
    };

    for (final state in WorkspaceLinkState.values) {
      test('${state.name}: isLinked is ${linked.contains(state)}', () {
        expect(state.isLinked, linked.contains(state));
      });
    }
  });
}
