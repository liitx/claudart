import 'dart:io';
import 'package:path/path.dart' as p;
import '../file_io.dart';
import '../ignore_rules.dart';
import 'scan_threshold_exception.dart';

const int _defaultThreshold = 300;

/// Detected entity types.
enum EntityType {
  bloc,
  cubit,
  blocState,
  blocEvent,
  repository,
  widget,
  extension,
  callback,
  provider,
  enumType,
  mixin,
  classType,
}

/// Information about a detected entity.
class EntityInfo {
  final String realName;
  final EntityType tokenType;
  final String sourceFile;

  const EntityInfo({
    required this.realName,
    required this.tokenType,
    required this.sourceFile,
  });

  String get typePrefix {
    switch (tokenType) {
      case EntityType.bloc:
        return 'Bloc';
      case EntityType.cubit:
        return 'Cubit';
      case EntityType.blocState:
        return 'BlocState';
      case EntityType.blocEvent:
        return 'BlocEvent';
      case EntityType.repository:
        return 'Repository';
      case EntityType.widget:
        return 'Widget';
      case EntityType.extension:
        return 'Extension';
      case EntityType.callback:
        return 'Callback';
      case EntityType.provider:
        return 'Provider';
      case EntityType.enumType:
        return 'Enum';
      case EntityType.mixin:
        return 'Mixin';
      case EntityType.classType:
        return 'Class';
    }
  }
}

/// Result of a scan operation.
class ScanResult {
  final Map<String, EntityInfo> entities;
  final int filesScanned;
  final int filesSkipped;
  final Duration duration;

  const ScanResult({
    required this.entities,
    required this.filesScanned,
    required this.filesSkipped,
    required this.duration,
  });
}

// Detection patterns
final _blocPattern = RegExp(r'class\s+(\w+)\s+extends\s+Bloc<');
final _cubitPattern = RegExp(r'class\s+(\w+)\s+extends\s+Cubit<');
final _blocStatePattern = RegExp(
    r'(?:sealed\s+)?class\s+(\w+State)\b');
final _blocEventPattern = RegExp(
    r'(?:sealed\s+)?class\s+(\w+Event)\b');
final _repositoryPattern = RegExp(
    r'(?:abstract\s+)?class\s+(\w+Repository)\b');
final _widgetPattern = RegExp(
    r'class\s+(\w+)\s+extends\s+(?:Stateless|Stateful)Widget\b');
final _extensionPattern = RegExp(r'extension\s+(\w+)\s+on\s+');
final _callbackPattern = RegExp(r'typedef\s+(\w+)\s*=');
final _providerPattern = RegExp(
    r'final\s+(\w+Provider)\s*=\s*(?:Provider|StateNotifierProvider|'
    r'StreamProvider|FutureProvider|ChangeNotifierProvider)');
final _enumPattern = RegExp(r'enum\s+(\w+)\s*\{');
final _mixinPattern = RegExp(r'mixin\s+(\w+)\b');
final _classPattern = RegExp(r'class\s+(\w+)\b');

/// Scans [projectPath] for Dart entities.
ScanResult scanProject(
  String projectPath, {
  String scope = 'lib',
  IgnoreRules? ignoreRules,
  FileIO? io,
  int threshold = _defaultThreshold,
}) {
  final start = DateTime.now();
  final fileIO = io ?? const RealFileIO();
  final ignore = ignoreRules ?? loadIgnoreRules(projectPath, io: io);

  final scanRoot = scope == 'full' ? projectPath : p.join(projectPath, scope);

  final dartFiles = _collectDartFiles(scanRoot, fileIO);

  if (dartFiles.length > threshold) {
    final isGenerated = dartFiles.any((f) => f.endsWith('.g.dart'));
    throw ScanThresholdException(
      filesFound: dartFiles.length,
      threshold: threshold,
      reason: isGenerated
          ? 'Generated files detected in scan scope.'
          : 'Too many files in scope.',
      suggestions: [
        'Add **/*.g.dart to .claudartignore',
        'Add build/ to .claudartignore',
        'Switch scan scope to lib/ only',
        'Run: claudart scan --scope lib',
      ],
    );
  }

  final entities = <String, EntityInfo>{};
  var skipped = 0;

  for (final filePath in dartFiles) {
    final relative = p.relative(filePath, from: projectPath);
    if (ignore.shouldIgnore(relative)) {
      skipped++;
      continue;
    }
    final content = fileIO.read(filePath);
    _extractEntities(content, filePath, entities);
  }

  final duration = DateTime.now().difference(start);
  return ScanResult(
    entities: entities,
    filesScanned: dartFiles.length - skipped,
    filesSkipped: skipped,
    duration: duration,
  );
}

List<String> _collectDartFiles(String dir, FileIO io) {
  if (!io.dirExists(dir)) return [];
  if (io is RealFileIO) {
    return Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList();
  }
  // MemoryFileIO path: list direct files only (tests seed files directly)
  return io.listFiles(dir, extension: '.dart');
}

void _extractEntities(
  String content,
  String filePath,
  Map<String, EntityInfo> out,
) {
  void add(String name, EntityType type) {
    out.putIfAbsent(
      name,
      () => EntityInfo(realName: name, tokenType: type, sourceFile: filePath),
    );
  }

  // Order matters: more specific patterns first
  for (final m in _blocPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.bloc);
  }
  for (final m in _cubitPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.cubit);
  }
  for (final m in _widgetPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.widget);
  }
  for (final m in _extensionPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.extension);
  }
  for (final m in _callbackPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.callback);
  }
  for (final m in _providerPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.provider);
  }
  for (final m in _enumPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.enumType);
  }
  for (final m in _mixinPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.mixin);
  }
  // Repository before generic class
  for (final m in _repositoryPattern.allMatches(content)) {
    add(m.group(1)!, EntityType.repository);
  }
  // BlocState / BlocEvent before generic class
  for (final m in _blocStatePattern.allMatches(content)) {
    final name = m.group(1)!;
    if (!out.containsKey(name)) add(name, EntityType.blocState);
  }
  for (final m in _blocEventPattern.allMatches(content)) {
    final name = m.group(1)!;
    if (!out.containsKey(name)) add(name, EntityType.blocEvent);
  }
  // Generic class fallback
  for (final m in _classPattern.allMatches(content)) {
    final name = m.group(1)!;
    if (!out.containsKey(name)) add(name, EntityType.classType);
  }
}
