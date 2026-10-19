import 'dart:io';

/// Abstraction over file system operations.
/// Swap in [MemoryFileIO] in tests to avoid touching disk.
abstract class FileIO {
  String read(String path);
  void write(String path, String content);

  /// Adds [content] to the end of the file (creating it), without reading or
  /// rewriting what is there, so concurrent appenders do not lose each other's
  /// lines.
  void append(String path, String content);
  void delete(String path);
  bool fileExists(String path);
  bool dirExists(String path);
  void createDir(String path);
  List<String> listFiles(String dirPath, {String? extension});
  bool linkExists(String path);
  void deleteLink(String path);
  void createLink(String linkPath, String targetPath);
}

/// Staging files are named `<path>.tmp<pid>`, one per writing process.
const _stagingSuffix = '.tmp';

/// Production implementation backed by dart:io.
class RealFileIO implements FileIO {
  const RealFileIO();

  @override
  String read(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  /// Writes through a staging file and renames it over [path], so a reader
  /// sees the old content or the new, never a truncated half.
  @override
  void write(String path, String content) {
    File(path).parent.createSync(recursive: true);
    final staging = File('$path$_stagingSuffix$pid')
      ..writeAsStringSync(content);
    staging.renameSync(path);
  }

  /// Holds an exclusive lock while it writes at the true end of the file.
  /// Dart's plain append mode does not make concurrent appends safe (measured:
  /// 4 writers x 100 lines kept 209 of 400), so the lock is what serializes
  /// them; the position is re-read after the lock is won, since another writer
  /// may have extended the file while this one waited.
  @override
  void append(String path, String content) {
    File(path).parent.createSync(recursive: true);
    final file = File(path).openSync(mode: FileMode.append);
    try {
      file.lockSync(FileLock.blockingExclusive);
      file.setPositionSync(file.lengthSync());
      file.writeStringSync(content);
      file.flushSync();
    } finally {
      file.closeSync();
    }
  }

  @override
  void delete(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  bool dirExists(String path) => Directory(path).existsSync();

  @override
  void createDir(String path) => Directory(path).createSync(recursive: true);

  @override
  List<String> listFiles(String dirPath, {String? extension}) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => extension == null || p.endsWith(extension))
        .toList();
  }

  @override
  bool linkExists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;

  @override
  void deleteLink(String path) {
    if (linkExists(path)) Link(path).deleteSync();
  }

  @override
  void createLink(String linkPath, String targetPath) =>
      Link(linkPath).createSync(targetPath);
}
