// dependency_config.dart — what a project's own pubspec.yaml declares
//
// Pure string detection, no IO — callers read pubspec.yaml themselves
// (already the convention in add.dart/doctor.dart) and pass the content
// in. Previously duplicated: add.dart had its own private
// `_detectsDartrixDependency`, used only to pre-fill its wizard's "Uses
// dartrix?" question — the same fact the dependency-config codegen below
// needs, so it's shared here instead of re-typed a second time.

/// True when [pubspecContent] declares a direct `dartrix` dependency
/// (two-space-indented top-level `dependencies:`/`dev_dependencies:` entry,
/// not a transitive mention elsewhere in the file).
bool detectsDartrixDependency(String pubspecContent) =>
    RegExp(r'^\s{2}dartrix:', multiLine: true).hasMatch(pubspecContent);
