import 'dart:convert';
import 'errors/claudart_exception.dart';
import 'errors/failure_type.dart';
import 'file_io.dart';
import 'paths.dart';

const _warning =
    'Managed by claudart. Do not edit manually — use claudart commands.';

/// Thrown when registry.json exists but can't be read as a registry. Reading
/// still treats that as "nothing linked" (so a command can show an empty
/// list), but saving over it would wipe every registered project, so `save`
/// refuses.
class CorruptRegistryException extends ClaudartException {
  final String cause;
  CorruptRegistryException(this.cause) : super(FailureType.registryCorrupt);

  @override
  String toString() => 'Registry is corrupt: $cause';
}

class RegistryEntry {
  final String name;
  final String projectRoot;
  final String workspacePath;
  final String createdAt;
  final String lastSession;
  /// The one record of whether this project is sensitive, set when it is
  /// linked (`claudart link` reconciles it with the owner's workspace.json
  /// once, never weakening it). Everything that depends on sensitivity asks
  /// this entry, not the files.
  final bool sensitivityMode;

  /// Whether the ambient `CLAUDART_DEBUG` trace, which writes full prompts to
  /// disk, may run for this project.
  bool get permitsDebugTrace => !sensitivityMode;

  const RegistryEntry({
    required this.name,
    required this.projectRoot,
    required this.workspacePath,
    required this.createdAt,
    required this.lastSession,
    this.sensitivityMode = false,
  });

  factory RegistryEntry.fromJson(Map<String, dynamic> json) => RegistryEntry(
        name: json['name'] as String,
        projectRoot: json['projectRoot'] as String,
        workspacePath: json['workspacePath'] as String,
        createdAt: json['createdAt'] as String,
        lastSession: json['lastSession'] as String,
        sensitivityMode: json['sensitivityMode'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'projectRoot': projectRoot,
        'workspacePath': workspacePath,
        'createdAt': createdAt,
        'lastSession': lastSession,
        'sensitivityMode': sensitivityMode,
      };

  RegistryEntry copyWith({
    String? lastSession,
    bool? sensitivityMode,
  }) =>
      RegistryEntry(
        name: name,
        projectRoot: projectRoot,
        workspacePath: workspacePath,
        createdAt: createdAt,
        lastSession: lastSession ?? this.lastSession,
        sensitivityMode: sensitivityMode ?? this.sensitivityMode,
      );
}

class Registry {
  // Map-backed internally for O(1) name lookup, add, remove, and update.
  // findByProjectRoot is the only operation that requires a scan — it matches
  // on a non-key value so iteration is unavoidable regardless of structure.
  final Map<String, RegistryEntry> _byName;

  Registry._(this._byName);

  factory Registry.empty() => Registry._({});

  /// All entries in insertion order.
  List<RegistryEntry> get entries => _byName.values.toList();

  bool get isEmpty => _byName.isEmpty;

  /// Loads the registry from disk. Returns an empty registry if the file is
  /// missing or unreadable (corrupt JSON, or valid JSON of the wrong shape);
  /// [save] will not overwrite an unreadable file.
  static Registry load({FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final raw = fileIO.read(registryPath);
    if (raw.isEmpty) return Registry.empty();
    try {
      return _parse(raw);
    } on FormatException catch (_) {
      return Registry.empty();
    } on TypeError catch (_) {
      return Registry.empty();
    }
  }

  /// Parses registry.json's text. Throws [FormatException] for text that is
  /// not JSON and [TypeError] for JSON of the wrong shape.
  static Registry _parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['workspaces'] as List<dynamic>? ?? [];
    final map = <String, RegistryEntry>{};
    for (final item in list.cast<Map<String, dynamic>>()) {
      final entry = RegistryEntry.fromJson(item);
      map[entry.name] = entry;
    }
    return Registry._(map);
  }

  /// Persists the registry to disk. Throws [CorruptRegistryException] when the
  /// file there exists but is unreadable: loading it gave an empty registry,
  /// and writing that back would erase every registered project.
  void save({FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final existing = fileIO.read(registryPath);
    if (existing.isNotEmpty) {
      try {
        _parse(existing);
      } on FormatException catch (e) {
        throw CorruptRegistryException(e.message);
      } on TypeError catch (e) {
        throw CorruptRegistryException(e.toString());
      }
    }
    const encoder = JsonEncoder.withIndent('  ');
    fileIO.write(
      registryPath,
      encoder.convert({
        '_warning': _warning,
        'workspaces': entries.map((e) => e.toJson()).toList(),
      }),
    );
  }

  /// O(1) lookup by project name.
  RegistryEntry? findByName(String name) => _byName[name];

  /// O(n) scan — unavoidable since projectRoot is a non-key value.
  RegistryEntry? findByProjectRoot(String path) {
    for (final e in _byName.values) {
      if (e.projectRoot == path) return e;
    }
    return null;
  }

  /// Returns a new Registry with [entry] added or replaced by name. O(1).
  Registry add(RegistryEntry entry) =>
      Registry._(Map.of(_byName)..[entry.name] = entry);

  /// Returns a new Registry with the entry for [name] removed. O(1).
  Registry remove(String name) =>
      Registry._(Map.of(_byName)..remove(name));

  /// Returns a new Registry with [name]'s lastSession updated to today. O(1).
  Registry touchSession(String name) {
    final existing = _byName[name];
    if (existing == null) return this;
    final today = DateTime.now().toIso8601String().split('T').first;
    return Registry._(Map.of(_byName)..[name] = existing.copyWith(lastSession: today));
  }
}
