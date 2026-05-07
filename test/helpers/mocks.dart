import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:claudart/file_io.dart';
import 'package:claudart/process_runner.dart';

/// Mock file system — use [files] to pre-seed content,
/// inspect it after the call under test.
class MockFileIO extends Mock implements FileIO {}

/// Mock process runner — stub with [when] to control stdout/stderr/exitCode.
class MockProcessRunner extends Mock implements ProcessRunner {}

/// In-memory [FileIO] backed by a plain Map.
/// Simpler than [MockFileIO] when you just want realistic read/write behaviour.
class MemoryFileIO implements FileIO {
  final Map<String, String> files;
  final Set<String> dirs;
  final Set<String> links;

  MemoryFileIO({
    Map<String, String>? files,
    Set<String>? dirs,
    Set<String>? links,
  })  : files = Map.from(files ?? {}),
        dirs = Set.from(dirs ?? {}),
        links = Set.from(links ?? {});

  @override
  String read(String path) => files[path] ?? '';

  @override
  void write(String path, String content) => files[path] = content;

  @override
  void writeAtomic(String path, String content) => files[path] = content;

  @override
  void delete(String path) => files.remove(path);

  @override
  bool fileExists(String path) => files.containsKey(path);

  @override
  bool dirExists(String path) => dirs.contains(path) || files.keys.any((k) => k.startsWith('$path/'));

  @override
  void createDir(String path) => dirs.add(path);

  @override
  List<String> listFiles(String dirPath, {String? extension}) {
    return files.keys
        .where((k) {
          final inDir = k.startsWith('$dirPath/') &&
              !k.substring(dirPath.length + 1).contains('/');
          return inDir && (extension == null || k.endsWith(extension));
        })
        .toList();
  }

  @override
  bool linkExists(String path) => links.contains(path);

  @override
  void deleteLink(String path) => links.remove(path);

  @override
  void createLink(String linkPath, String targetPath) => links.add(linkPath);
}

/// Returns a [ProcessResult] with the given stdout and exit code 0.
ProcessResult fakeResult(String stdout, {int exitCode = 0}) =>
    ProcessResult(0, exitCode, stdout, '');

/// Sets up mocktail fallback values (call once in setUpAll).
void registerFallbacks() {
  registerFallbackValue(fakeResult(''));
}
