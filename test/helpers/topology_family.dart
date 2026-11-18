// topology_family.dart — which family a source file belongs to.
//
// A family is a cell of two axes, each read from what the file's code does,
// not from its name or folder:
//   - StateRole: does it drive handoff state (emit an event), only observe it,
//     or never touch it;
//   - ReachLayer: the farthest outside the process it reaches, from nothing
//     to the workspace files to processes and the terminal.
// Comments are ignored. A file that matches no portal pattern falls in the
// complement (`StateRole.untouched`, `ReachLayer.pure`), so no file is
// unclassified. The patterns are call-shaped (`Registry.load(`), so a file
// that only defines a name is not counted as using it.

/// Whether a file moves, reads, or never touches the handoff state.
enum StateRole {
  /// Emits a handoff event or applies one.
  drivesState(r'HandoffEvent\.|applyHandoffEvent\('),

  /// Reads or branches on a status but emits no event.
  observesState(r'HandoffStatus\.|SessionState\.parse\(|HandoffStatus\b'),

  /// Neither; the complement of the two above.
  untouched(null);

  const StateRole(this._pattern);
  final String? _pattern;

  /// The role of [code], strongest first.
  static StateRole of(String code) {
    for (final role in [drivesState, observesState]) {
      if (RegExp(role._pattern!).hasMatch(code)) return role;
    }
    return untouched;
  }
}

/// The farthest layer a file reaches, ordered nearest to farthest.
enum ReachLayer {
  /// No portal: pure values and logic.
  pure(null),

  /// The injected file seam only.
  fileSeam(r'\bFileIO\b'),

  /// The registry, the handoff and the workspace configuration files.
  workspaceBound(
    r'Registry\.(load|empty)\(|WorkspaceConfig\.load\(|loadWorkspaceConfig\(|'
    r'(handoff|skills|config|workspaceConfig)PathFor\(|SessionState\.parse\(',
  ),

  /// Processes, git, the model, or the terminal.
  processBound(
    r'ProcessRunner\b|Process\.(run|start)|detectGitContext\(|'
    r'(read|write)GitConfig\(|resolveProjectRoot\(|PipelineExecutor\b|'
    r'ClaudeRunner\b|\bstdin\b|\bpromptFn\b|\bconfirmFn\b|\bpickFn\b',
  );

  const ReachLayer(this._pattern);
  final String? _pattern;

  /// The farthest layer [code] reaches.
  static ReachLayer of(String code) {
    for (final layer in values.reversed) {
      final pattern = layer._pattern;
      if (pattern != null && RegExp(pattern).hasMatch(code)) return layer;
    }
    return pure;
  }
}

/// A family: one cell of role x reach.
typedef TopologyFamily = ({StateRole role, ReachLayer reach});

/// The code of [source] with whole-line comments removed.
String codeOf(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// The family of one file's [source].
TopologyFamily topologyFamilyOf(String source) {
  final code = codeOf(source);
  return (role: StateRole.of(code), reach: ReachLayer.of(code));
}

/// Every file of [sources] (path -> text) grouped by family, files sorted.
Map<TopologyFamily, List<String>> groupByFamily(Map<String, String> sources) {
  final groups = <TopologyFamily, List<String>>{};
  for (final entry in sources.entries) {
    groups.putIfAbsent(topologyFamilyOf(entry.value), () => []).add(entry.key);
  }
  for (final files in groups.values) {
    files.sort();
  }
  return groups;
}
