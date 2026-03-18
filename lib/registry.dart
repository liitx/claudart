import 'dart:convert';
import 'file_io.dart';
import 'paths.dart';

const _warning =
    'Managed by claudart. Do not edit manually — use claudart commands.';

class RegistryEntry {
  final String name;
  final String projectRoot;
  final String workspacePath;
  final String createdAt;
  final String lastSession;
  final bool sensitivityMode;

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

  /// Loads the registry from disk. Returns empty registry if file missing or corrupt.
  static Registry load({FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final raw = fileIO.read(registryPath);
    if (raw.isEmpty) return Registry.empty();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = json['workspaces'] as List<dynamic>? ?? [];
      final map = <String, RegistryEntry>{};
      for (final item in list.cast<Map<String, dynamic>>()) {
        final entry = RegistryEntry.fromJson(item);
        map[entry.name] = entry;
      }
      return Registry._(map);
    } on Exception catch (_) {
      return Registry.empty();
    }
  }

  /// Persists the registry to disk.
  void save({FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
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
