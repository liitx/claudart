import 'dart:io';
import 'package:path/path.dart' as p;
import 'pipeline/pipeline_context.dart' show ScopeFile;
import 'ui/line_editor.dart' as editor;

/// Reads a section from a markdown file between `## Header` and the next `## `.
/// Returns the trimmed content, or `_Not yet determined._` if not found.
String readSection(String content, String header) {
  final pattern = RegExp(
    r'## ' + RegExp.escape(header) + r'\n+([\s\S]*?)(?=\n## |\s*$)',
  );
  final match = pattern.firstMatch(content);
  final raw = match?.group(1) ?? '_Not yet determined._';
  return raw.replaceAll(RegExp(r'\n*-{3,}\n*$'), '').trim();
}

/// Replaces the content of a section in markdown, preserving surrounding sections.
String updateSection(String content, String header, String newContent) {
  final pattern = RegExp(
    r'(## ' + RegExp.escape(header) + r'\n+)([\s\S]*?)(?=\n## |\s*$)',
  );
  if (pattern.hasMatch(content)) {
    return content.replaceFirstMapped(pattern, (m) => '${m.group(1)}$newContent\n');
  }
  // Section not found — append it
  return '$content\n## $header\n\n$newContent\n';
}

/// Reads the Status line value from the handoff.
String readStatus(String content) {
  final match = RegExp(r'## Status\n+(\S[^\n]*)').firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

/// Updates the Status line in the handoff.
String updateStatus(String content, String status) {
  return content.replaceFirstMapped(
    RegExp(r'(## Status\n+)(\S[^\n]*)'),
    (m) => '${m.group(1)}$status',
  );
}

String readFile(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// Parses `### Files in play` bullet lines from a scope section.
///
/// The suggest prompt asks for ``- `relative/path` — what to change``, but
/// model output varies, so all of these are accepted (`-` or `*` bullets):
///
///     - `rel/path.dart` — description          (the pinned format)
///     - `rel/path.dart`: description
///     - rel/path.dart: description             (also — – - separators)
///     - rel/path.dart
///     - /abs/path/inside/project.dart: description
///
/// Unbackticked paths must end in a file extension, so prose bullets such as
/// "No changes needed" or "N/A" are not mistaken for files (extensionless
/// files need backticks).
///
/// **Containment.** The handoff is model-written and the files it lists are
/// read by the model, so an entry may only point inside [projectRoot] or
/// inside one of [allowedRoots] (relative entries resolve against the project
/// root). Both the written path and, when the file exists, its symlink-resolved
/// path must be inside — a symlink inside the project cannot be used to leave
/// it. Anything else is dropped; use [parseScopeFilesChecked] to also learn
/// which paths were dropped. The project root is also matched in its
/// symlink-resolved form, since a subprocess reports `/private/tmp/x` where the
/// user typed `/tmp/x`.
///
/// Returns a list of [ScopeFile] with absolute paths resolved via [projectRoot].
List<ScopeFile> parseScopeFiles(
  String scopeSection,
  String projectRoot, {
  List<String> allowedRoots = const [],
}) =>
    parseScopeFilesChecked(scopeSection, projectRoot, allowedRoots: allowedRoots).accepted;

/// Result of [parseScopeFilesChecked]: the usable entries, and the raw paths
/// that were dropped because they resolve outside the project and every
/// allowed root.
typedef ScopeParse = ({List<ScopeFile> accepted, List<String> rejected});

/// Like [parseScopeFiles], but also reports the paths it dropped so the caller
/// can tell the user instead of ignoring them silently.
ScopeParse parseScopeFilesChecked(
  String scopeSection,
  String projectRoot, {
  List<String> allowedRoots = const [],
}) {
  final accepted = <ScopeFile>[];
  final rejected = <String>[];
  var inFiles = false;
  for (final line in scopeSection.split('\n')) {
    if (line.startsWith('### Files in play')) { inFiles = true; continue; }
    if (inFiles && line.startsWith('###')) break;
    if (!inFiles) continue;
    final raw = _scopeCandidate(line.trim());
    if (raw == null) continue;
    final file = _contained(raw, projectRoot, allowedRoots);
    if (file == null) {
      rejected.add(raw);
    } else {
      accepted.add(file);
    }
  }
  return (accepted: accepted, rejected: rejected);
}

final _backtickedBullet = RegExp(r'^[-*]\s+`([^`]+)`');
final _plainBullet      = RegExp(r'^[-*]\s+(\S+?)(?::(?=\s|$)|\s|$)');
final _hasFileExtension = RegExp(r'\.[A-Za-z0-9]{1,8}$');

/// The path a bullet names, or null when the line is not a file bullet.
String? _scopeCandidate(String line) {
  final backticked = _backtickedBullet.firstMatch(line);
  if (backticked != null) return backticked.group(1)!;

  final plain = _plainBullet.firstMatch(line);
  if (plain == null) return null;
  final token = plain.group(1)!.replaceAll(RegExp(r'[,;]+$'), '');
  return _hasFileExtension.hasMatch(token) ? token : null;
}

ScopeFile? _contained(String raw, String projectRoot, List<String> allowedRoots) {
  final root = p.normalize(projectRoot);
  final candidate = p.normalize(p.isAbsolute(raw) ? raw : p.join(root, raw));

  final roots = <String>{root, _resolved(root)};
  for (final extra in allowedRoots) {
    final abs = p.normalize(p.isAbsolute(extra) ? extra : p.join(root, extra));
    roots..add(abs)..add(_resolved(abs));
  }
  bool inside(String path) => roots.any((r) => p.isWithin(r, path));
  if (!inside(candidate) || !inside(_resolved(candidate))) return null;

  final within = [root, _resolved(root)].where((r) => p.isWithin(r, candidate));
  final relative = within.isNotEmpty
      ? p.relative(candidate, from: within.first)
      : p.relative(candidate, from: root);
  final absolute = relative.startsWith('..') ? candidate : p.join(projectRoot, relative);
  return (relative: relative, absolute: absolute);
}

String _resolved(String path) {
  try {
    return FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound
        ? path
        : (Directory(path).existsSync()
            ? Directory(path).resolveSymbolicLinksSync()
            : File(path).resolveSymbolicLinksSync());
  } on FileSystemException {
    return path;
  }
}

void writeFile(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Prompts the user with a question and returns trimmed input.
/// If [optional] is true, empty input returns null.
String? prompt(String question, {bool optional = false}) {
  while (true) {
    stdout.write('\n$question');
    if (optional) stdout.write(' (press enter to skip)');
    stdout.write('\n');
    final input = editor.readLine(optional: optional);
    if (input == null && !optional) return null;  // EOF/non-TTY — can't prompt
    if (optional) return input?.isEmpty == true ? null : input;
    if (input != null && input.isNotEmpty) return input;
    // Non-optional and empty — re-prompt once with hint, don't recurse.
    stdout.write('  (required — please enter a value)\n');
  }
}

/// Prompts yes/no. Returns true for yes.
bool confirm(String question) {
  stdout.write('\n$question [y/n]\n');
  final input = editor.readLine(optional: true);
  return input?.toLowerCase() == 'y' || input?.toLowerCase() == 'yes';
}

/// Prompts yes/no like [confirm], but returns null when input has ended
/// (closed stdin) instead of silently answering "no". For questions where "no
/// answer" must never become a default, such as a protective setting.
/// An empty line (just Enter) is still "no".
bool? confirmOrEof(String question) {
  stdout.write('\n$question [y/n]\n');
  final input = editor.readLine(distinguishEof: true);
  if (input == null) return null;
  final answer = input.toLowerCase();
  return answer == 'y' || answer == 'yes';
}
