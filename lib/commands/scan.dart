import '../config/config.dart' show ScanScope;
import '../io/file_io.dart';
import '../project/ignore_rules.dart';
import '../config/paths.dart';
import '../scanner/scanner.dart';
import '../scanner/scan_threshold_exception.dart';
import '../sensitivity/token_map.dart';
import '../logging/logger.dart';
import '../ui/render.dart' as render;
import '../generated/user_text.g.dart';

/// Runs an explicit on-demand scan of the project.
/// [scope] overrides the default scan scope (`ScanScope.lib`, `ScanScope.full`,
/// or any subdirectory name, e.g. 'handoff').
/// [full] is a convenience flag that sets scope to `ScanScope.full`.
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
    print(UserText.scanNoProjectLinkedRunClaudartLink.template);
    return;
  }

  final effectiveScope = full ? ScanScope.full : (scope ?? ScanScope.lib);
  final projectRoot = projectRootOverride;
  final sensitivityMode = sensitivityModeOverride ?? false;

  print(render.header('SENSITIVITY SCAN'));
  print(UserText.scanScanning.format({'projectRoot': projectRoot, 'effectiveScope': effectiveScope}));

  final tokenMapPath = workspacePath != null
      ? tokenMapPathFor(workspacePath)
      : tokenMapPathFor(claudeDir);

  final ignoreRules = loadIgnoreRules(projectRoot, io: fileIO);
  final tokenMap = TokenMap.load(tokenMapPath, io: fileIO);
  final previousSize = tokenMap.size;

  final logger = sensitivityMode
      ? SessionLogger.abstracted(
          tokenMap: tokenMap,
          io: fileIO,
          workspacePath: workspacePath,
        )
      : SessionLogger.plain(io: fileIO, workspacePath: workspacePath);

  ScanResult result;
  try {
    result = scanProject(
      projectRoot,
      scope: effectiveScope,
      ignoreRules: ignoreRules,
      io: fileIO,
    );
  } on ScanThresholdException catch (e) {
    print(UserText.scanThresholdExceeded.format({'filesFound': e.filesFound, 'threshold': e.threshold}));
    print(UserText.scanReason.format({'reason': e.reason}));
    print(UserText.scanSuggestions.template);
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
    print(UserText.scanTokenCountRange.format({
      'count': count,
      'kind': entry.key,
      'plural': count == 1 ? '' : UserText.pluralSuffix.template,
      'range': range.isNotEmpty ? UserText.scanTokenRange.format({'range': range}) : '',
    }));
  }

  if (newTokens > 0) {
    print(UserText.scanNewTokens.format({
      'newTokens': newTokens,
      'plural': newTokens == 1 ? '' : UserText.pluralSuffix.template,
    }));
  }
  print(UserText.scanTokenMapUpdated.format({'tokenMapPath': tokenMapPath}));

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
