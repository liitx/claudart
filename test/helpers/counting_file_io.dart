// counting_file_io.dart — an in-memory filesystem that remembers every call.
//
// The call census (test/topology/call_census_test.dart) runs real commands
// against it to measure which files each command reads and writes, so a claim
// such as "the registry is read twice per command" is counted, not argued. It
// only observes: every call still behaves exactly as MemoryFileIO does.

import 'mocks.dart';

/// The ways a command can touch a file through the FileIO seam.
enum FileOperation { read, write, append, delete }

/// One call through the seam: what was done, to which path.
typedef FileCall = ({FileOperation operation, String path});

/// A [MemoryFileIO] that records each read, write, append and delete.
class CountingFileIO extends MemoryFileIO {
  /// Starts from a copy of [base]'s files, directories and links.
  CountingFileIO.from(MemoryFileIO base)
      : super(files: base.files, dirs: base.dirs, links: base.links);

  final List<FileCall> _calls = [];

  /// The calls since construction or the last [takeCalls].
  List<FileCall> get calls => List.unmodifiable(_calls);

  /// Returns the calls recorded so far and starts a fresh record.
  List<FileCall> takeCalls() {
    final taken = List<FileCall>.of(_calls);
    _calls.clear();
    return taken;
  }

  void _record(FileOperation operation, String path) =>
      _calls.add((operation: operation, path: path));

  @override
  String read(String path) {
    _record(FileOperation.read, path);
    return super.read(path);
  }

  @override
  void write(String path, String content) {
    _record(FileOperation.write, path);
    super.write(path, content);
  }

  @override
  void append(String path, String content) {
    _record(FileOperation.append, path);
    super.append(path, content);
  }

  @override
  void delete(String path) {
    _record(FileOperation.delete, path);
    super.delete(path);
  }
}
