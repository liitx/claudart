// project_fixture.dart — the linked project the command tests run against.
//
// These paths exist only inside MemoryFileIO and never on disk. They are
// spelled once, here, so no test carries its own copy and a change to the
// fixture is one edit.

/// The project a command test links and runs in.
abstract final class ProjectFixture {
  /// The project's name in the registry.
  static const String name = 'my-app';

  /// Where the project's code lives.
  static const String root = '/projects/$name';

  /// Where claudart keeps the project's workspace.
  static const String workspace = '/workspaces/$name';
}
