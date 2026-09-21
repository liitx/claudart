import '../file_io.dart';
import '../ignore_rules.dart';
import '../paths.dart';
import '../scanner/scanner.dart';
import '../scanner/scan_threshold_exception.dart';
import '../sensitivity/token_map.dart';
import '../logging/logger.dart';
import '../ui/render.dart' as render;

/// Runs an explicit on-demand scan of the project.
/// [scope] overrides the default scan scope ('lib', 'full', or 'handoff').
/// [full] is a convenience flag that sets scope to 'full'.
/// [projectRootOverride] and [sensitivityModeOverride] come from the caller's
/// registry lookup (bin/claudart.dart for `scan`, setup.dart for its own
/// pre-handoff scan) — there is no config.json fallback.
/// [workspacePath] routes token_map.json and logs to the per-project workspace.
Future<void> runScan({
  String? scope,
  bool full = false,
  FileIO? io,
  String? projectRootOverride,
  bool? sensitivityModeOverride,
  String? workspacePath,
}) async {
  final fileIO = io ?? const RealFileIO();

  if (projectRootOverride == null) {
    print('\n✗ No project linked. Run `claudart link` first.\n');
    return;
  }

  final effectiveScope = full ? 'full' : (scope ?? 'lib');
  final projectRoot = projectRootOverride;
  final sensitivityMode = sensitivityModeOverride ?? false;

  print(render.header('SENSITIVITY SCAN'));
  print('Scanning $projectRoot/$effectiveScope...');

  final tokenMapPath = workspacePath != null
      ? tokenMapPathFor(workspacePath)
      : tokenMapPathFor(claudeDir);

  final ignoreRules = loadIgnoreRules(projectRoot, io: fileIO);
  final tokenMap = TokenMap.load(tokenMapPath, io: fileIO);
  final previousSize = tokenMap.size;

  final logger = SessionLogger(
    io: fileIO,
    sensitivityMode: sensitivityMode,
    tokenMap: tokenMap,
    workspacePath: workspacePath,
  );

  ScanResult result;
  try {
    result = scanProject(
      projectRoot,
      scope: effectiveScope,
      ignoreRules: ignoreRules,
      io: fileIO,
    );
  } on ScanThresholdException catch (e) {
    print('\n⚠  Threshold exceeded: ${e.filesFound} files found '
        '(threshold: ${e.threshold})');
    print('   Reason: ${e.reason}');
    print('\nSuggestions:');
    for (final s in e.suggestions) {
      print('  • $s');
    }
    logger.logError(
      command: 'scan',
      errorType: 'threshold_hit',
      fingerprint: 'scan.threshold_hit.${e.reason.toLowerCase().replaceAll(' ', '_')}',
      reason: e.reason,
      suggestion: e.suggestions.firstOrNull,
      extra: {'filesFound': e.filesFound, 'threshold': e.threshold},
    );
    return;
  }

  // Assign tokens for all detected entities
  final byType = <String, List<String>>{};
  for (final entity in result.entities.values) {
    tokenMap.tokenFor(entity.realName, entity.typePrefix);
    byType.putIfAbsent(entity.typePrefix, () => []).add(entity.realName);
  }

  tokenMap.save(tokenMapPath, io: fileIO);
  final newTokens = tokenMap.size - previousSize;

  // Print grouped summary
  for (final entry in byType.entries) {
    final count = entry.value.length;
    final tokens = entry.value
        .map((n) => tokenMap.tokenFor(n, entry.key))
        .toList()
      ..sort();
    final range = tokens.isNotEmpty
        ? '${tokens.first}–${tokens.last}'
        : '';
    print('  ✓ $count ${entry.key}${count == 1 ? '' : 's'}'
        '${range.isNotEmpty ? '       → $range' : ''}');
  }

  if (newTokens > 0) {
    print('  + $newTokens new token${newTokens == 1 ? '' : 's'} since last scan');
  }
  print('Token map updated: $tokenMapPath');

  logger.logInteraction(
    command: 'scan',
    outcome: 'ok',
    scanScope: effectiveScope,
    filesScanned: result.filesScanned,
    tokensTotal: tokenMap.size,
    tokensNew: newTokens,
    scanDuration: result.duration.inMilliseconds / 1000,
  );
}
