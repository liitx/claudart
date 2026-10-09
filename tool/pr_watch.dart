// pr_watch.dart — stateful "has this PR changed since I last checked" tool
//
// Not real-time push: GitHub doesn't deliver webhooks to a bare local
// process, so this polls `gh pr view` under the hood. Two modes:
//   - one-shot (default): compare current PR state to the last-seen state
//     cached in a dotfile, report the diff, update the cache. Good at the
//     start of a session, since neither side runs as a persistent process
//     between sessions anyway.
//   - `--watch`: wraps the same check in a Stream.periodic for someone who
//     actually leaves a terminal open — prints each time something changes,
//     never on a tick where nothing did.
//
// Usage:
//   dart run tool/pr_watch.dart <pr-number> [--repo owner/name] [--watch] [--interval=30]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultRepo = 'liitx/claudart';
const _defaultIntervalSeconds = 30;
const _ghExecutable = 'gh';
const _stateDirName = '.claudart_pr_watch';

class PrSnapshot {
  final String headSha;
  final String updatedAt;
  final int commentCount;
  final String latestCommitMessage;

  const PrSnapshot({
    required this.headSha,
    required this.updatedAt,
    required this.commentCount,
    required this.latestCommitMessage,
  });

  /// Parses `gh pr view --json ...`'s raw response shape — field names and
  /// shapes GitHub's API defines, not this tool's own.
  factory PrSnapshot.fromGhJson(Map<String, dynamic> json) {
    final commits = json['commits'] as List<dynamic>? ?? const [];
    final latest = commits.isEmpty ? null : commits.last as Map<String, dynamic>;
    return PrSnapshot(
      headSha: json['headRefOid'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      commentCount: (json['comments'] as List<dynamic>? ?? const []).length,
      latestCommitMessage: (latest?['messageHeadline'] as String?) ?? '',
    );
  }

  /// Parses this tool's own cache file — [toJson]'s shape, a different set
  /// of key names than [fromGhJson]'s GitHub-defined ones. Conflating the
  /// two was a real bug: reading the cache through [fromGhJson] always
  /// defaulted `headSha` to `''` (looked for `headRefOid`, which the cache
  /// file never has), so every cached comparison reported "changed" even
  /// when nothing had.
  factory PrSnapshot.fromCacheJson(Map<String, dynamic> json) => PrSnapshot(
        headSha: json['headSha'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
        commentCount: json['commentCount'] as int? ?? 0,
        latestCommitMessage: json['latestCommitMessage'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'headSha': headSha,
        'updatedAt': updatedAt,
        'commentCount': commentCount,
        'latestCommitMessage': latestCommitMessage,
      };

  bool differsFrom(PrSnapshot? other) =>
      other == null || other.headSha != headSha || other.commentCount != commentCount;

  @override
  String toString() =>
      'sha=${headSha.substring(0, headSha.length < 8 ? headSha.length : 8)} '
      'comments=$commentCount latest="$latestCommitMessage"';
}

Future<PrSnapshot> fetchSnapshot(String repo, int prNumber) async {
  final result = await Process.run(_ghExecutable, [
    'pr',
    'view',
    '$prNumber',
    '--repo',
    repo,
    '--json',
    'headRefOid,updatedAt,comments,commits',
  ]);
  if (result.exitCode != 0) {
    throw Exception('gh pr view failed: ${result.stderr}');
  }
  return PrSnapshot.fromGhJson(jsonDecode(result.stdout as String) as Map<String, dynamic>);
}

File _stateFile(String repo, int prNumber) {
  final safeName = repo.replaceAll('/', '_');
  final dir = Directory('${Platform.environment['HOME']}/$_stateDirName');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/${safeName}_$prNumber.json');
}

PrSnapshot? readCachedSnapshot(String repo, int prNumber) {
  final file = _stateFile(repo, prNumber);
  if (!file.existsSync()) return null;
  try {
    return PrSnapshot.fromCacheJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  } on FormatException {
    return null;
  }
}

void writeCachedSnapshot(String repo, int prNumber, PrSnapshot snapshot) {
  _stateFile(repo, prNumber).writeAsStringSync(jsonEncode(snapshot.toJson()));
}

/// Emits a snapshot only on ticks where it actually differs from the last
/// emitted one — a silent poll produces no output, matching this tool's
/// one job: say something only when there's something to say.
Stream<PrSnapshot> watchForChanges(
  String repo,
  int prNumber,
  Duration interval, {
  PrSnapshot? initial,
}) async* {
  var last = initial;
  while (true) {
    await Future<void>.delayed(interval);
    final current = await fetchSnapshot(repo, prNumber);
    if (current.differsFrom(last)) {
      yield current;
      last = current;
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/pr_watch.dart <pr-number> [--repo owner/name] [--watch] [--interval=seconds]',
    );
    exit(2);
  }

  final prNumber = int.parse(args.first);
  final repo = _argValue(args, '--repo') ?? _defaultRepo;
  final watch = args.contains('--watch');
  final interval = Duration(
    seconds: int.tryParse(_argValue(args, '--interval') ?? '') ?? _defaultIntervalSeconds,
  );

  final cached = readCachedSnapshot(repo, prNumber);
  final current = await fetchSnapshot(repo, prNumber);

  if (current.differsFrom(cached)) {
    print('PR #$prNumber ($repo) changed since last check: $current');
  } else {
    print('PR #$prNumber ($repo): no change since last check.');
  }
  writeCachedSnapshot(repo, prNumber, current);

  if (!watch) return;

  print('Watching PR #$prNumber every ${interval.inSeconds}s (Ctrl-C to stop)...');
  await for (final snapshot in watchForChanges(repo, prNumber, interval, initial: current)) {
    print('[${DateTime.now().toIso8601String()}] PR #$prNumber changed: $snapshot');
    writeCachedSnapshot(repo, prNumber, snapshot);
  }
}

String? _argValue(List<String> args, String flag) {
  for (final arg in args) {
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
  }
  final index = args.indexOf(flag);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
