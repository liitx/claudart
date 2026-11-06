
// edit_files.dart — parse and safely apply the implementer's file blocks.
//
// A file body may itself contain wire tag text (this parser's own source
// would). A block therefore ends only at a closing delimiter that is followed
// by nothing but whitespace and then either another file block or the end of
// the output. A closing delimiter anywhere else is file content.
//
// Applying is write-all, then verify-all, with rollback: the caller changes
// handoff state only when [applyEditFiles] returns.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/failure_type.dart';
import 'xml_tags.dart';
import '../io/process_runner.dart';

typedef EditFile = ({String path, String content});

/// Says whether the Dart file at [absolutePath] analyzes without errors, run
/// from [projectRoot]. The production one runs `dart analyze`; a test passes a
/// stand-in that answers at once.
typedef DartFileAnalyzer = bool Function(
  String absolutePath,
  String projectRoot,
);

/// A malformed edit plan or a failed verification, carrying its [FailureType].
class EditPlanException implements Exception {
  const EditPlanException(this.failure, this.detail);

  final FailureType failure;
  final String detail;

  @override
  String toString() => '${failure.label}: $detail';
}

final RegExp _openPattern =
    RegExp('${WireTag.editFile.openPrefix}\\s+path="([^"]+)">');

const String _kDartExtension = '.dart';

List<EditFile> parseEditFiles(String text) {
  final close = WireTag.editFile.close;
  final result = <EditFile>[];
  var cursor = 0;
  while (true) {
    final matches = _openPattern.allMatches(text, cursor).iterator;
    if (!matches.moveNext()) break;
    final open = matches.current;
    final start = open.end;
    var end = -1;
    var from = start;
    while (true) {
      final candidate = text.indexOf(close, from);
      if (candidate < 0) break;
      if (_endsBlock(text, candidate + close.length)) {
        end = candidate;
        break;
      }
      from = candidate + close.length;
    }
    if (end < 0) {
      throw EditPlanException(
        FailureType.editPlanMalformed,
        'no valid end for the block of ${open.group(1)}',
      );
    }
    result.add((
      path: open.group(1)!.trim(),
      content: _body(text.substring(start, end)),
    ));
    cursor = end + close.length;
  }
  if (result.isEmpty && text.contains(WireTag.editFile.openPrefix)) {
    throw const EditPlanException(
      FailureType.editPlanMalformed,
      'file blocks present but none could be parsed',
    );
  }
  return result;
}

bool _endsBlock(String text, int index) {
  final rest = text.substring(index).trimLeft();
  return rest.isEmpty || rest.startsWith(WireTag.editFile.openPrefix);
}

String _body(String raw) {
  var s = raw;
  if (s.startsWith('\r\n')) {
    s = s.substring(2);
  } else if (s.startsWith('\n')) {
    s = s.substring(1);
  }
  final trimmed = s.trimRight();
  return trimmed.isEmpty ? '' : '$trimmed\n';
}

bool dartAnalyzeClean(String absolutePath, String projectRoot) =>
    const RealProcessRunner().runSync(
      'dart',
      ['analyze', '--no-fatal-warnings', absolutePath],
      workingDirectory: projectRoot,
    ).exitCode ==
    0;

/// Whether the fix works, decided by running the workspace's verification
/// command in [projectRoot] with the fix written.
typedef FixVerifier = bool Function(String projectRoot);

/// Writes every file in [planned] with [write], then verifies each one exists,
/// equals the parsed content, and (for Dart files) analyzes; then, when
/// [verifyFix] is given, runs it once. On any failure the touched files are
/// restored and an [EditPlanException] is thrown.
void applyEditFiles({
  required String projectRoot,
  required List<EditFile> planned,
  required void Function(String path, String content) write,
  DartFileAnalyzer dartFileAnalyzer = dartAnalyzeClean,
  FixVerifier? verifyFix,
}) {
  final originals = <String, String?>{};
  for (final f in planned) {
    final abs = p.join(projectRoot, f.path);
    final file = File(abs);
    originals[abs] = file.existsSync() ? file.readAsStringSync() : null;
  }
  try {
    for (final f in planned) {
      write(p.join(projectRoot, f.path), f.content);
    }
    for (final f in planned) {
      final abs = p.join(projectRoot, f.path);
      final file = File(abs);
      if (!file.existsSync()) throw _verifyFailure(f.path, 'file is missing');
      if (file.readAsStringSync() != f.content) {
        throw _verifyFailure(f.path, 'content differs from the plan');
      }
      final isDartFile = f.path.endsWith(_kDartExtension);
      if (isDartFile && !dartFileAnalyzer(abs, projectRoot)) {
        throw _verifyFailure(f.path, 'dart analyze reported errors');
      }
    }
    if (verifyFix != null && !verifyFix(projectRoot)) {
      throw const EditPlanException(
        FailureType.fixVerificationFailed,
        'the verification command failed',
      );
    }
  } catch (_) {
    _restore(originals);
    rethrow;
  }
}

EditPlanException _verifyFailure(String path, String reason) =>
    EditPlanException(FailureType.editVerificationFailed, '$path: $reason');

void _restore(Map<String, String?> originals) {
  originals.forEach((abs, original) {
    final file = File(abs);
    if (original == null) {
      if (file.existsSync()) file.deleteSync();
    } else {
      file.writeAsStringSync(original);
    }
  });
}