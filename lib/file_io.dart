import 'dart:io';
import 'package:path/path.dart' as p;

/// Abstraction over file system operations.
/// Swap in [MemoryFileIO] in tests to avoid touching disk.
abstract class FileIO {
  String read(String path);
  void write(String path, String content);
  void writeAtomic(String path, String content);
  void delete(String path);
  bool fileExists(String path);
  bool dirExists(String path);
  void createDir(String path);
  List<String> listFiles(String dirPath, {String? extension});
  bool linkExists(String path);
  void deleteLink(String path);
  void createLink(String linkPath, String targetPath);
}

/// Production implementation backed by dart:io.
class RealFileIO implements FileIO {
  const RealFileIO();

  @override
  String read(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  @override
  void write(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  @override
  void writeAtomic(String path, String content) {
    final file = File(path);
    final dir = file.parent;
    final tempPath = p.join(dir.path, '.${p.basename(path)}.tmp');

    // Write to temp file
    final tempFile = File(tempPath);
    tempFile.writeAsStringSync(content);

    // Atomic rename
    try {
      tempFile.renameSync(path);
    } on Exception catch (e) {
      // Clean up temp file on failure
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } on Exception {
          // Ignore cleanup errors
        }
      }
      rethrow;
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
