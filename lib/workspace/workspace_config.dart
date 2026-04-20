import 'dart:convert';
import '../file_io.dart';
import '../commands/setup_template.dart';
import '../commands/suggest_template.dart';
import '../commands/debug_template.dart';
import '../commands/save_template.dart';
import '../commands/teardown_template.dart';

// ---------------------------------------------------------------------------
// Enums — every variant concept in workspace.json is typed here.
// workspace.json string values are the canonical serialised form; the CLI
// parses them into these enums so no command ever compares raw strings.
// ---------------------------------------------------------------------------

/// Tech stack declared by the workspace.
///
/// ∀ s ∈ StackType: s.value == the string used in workspace.json.
enum StackType {
  dart,
  flutter,
  bloc,
  riverpod,
  typescript,
  react,
  swift,
  kotlin;

  static StackType? fromString(String s) =>
      StackType.values.where((v) => v.name == s).firstOrNull;

  String get value => name;
}

/// Workflow agents available to the workspace session.
///
/// ∀ a ∈ AgentType: a.value == the string used in workspace.json.
enum AgentType {
  setup,
  suggest,
  debug,
  save,
  teardown;

  static AgentType? fromString(String s) =>
      AgentType.values.where((v) => v.name == s).firstOrNull;

  String get value => name;

  /// Slash-command file installed into `.claude/commands/`.
  String get fileName => '$name.md';

  /// Generates the command template for this agent type.
  ///
  /// ∀ v ∈ AgentType.values → v.commandTemplate(w).isNotEmpty
  /// enforced by the exhaustive switch — adding a new variant without a
  /// template arm is a compile error.
  String commandTemplate(String workspacePath) => switch (this) {
        AgentType.setup => setupCommandTemplate(workspacePath),
        AgentType.suggest => suggestCommandTemplate(workspacePath),
        AgentType.debug => debugCommandTemplate(workspacePath),
        AgentType.save => saveCommandTemplate(workspacePath),
        AgentType.teardown => teardownCommandTemplate(workspacePath),
      };
}

/// Ownership role of the workspace owner relative to the project.
///
/// (workspaceOwner == projectMaintainer) ↔ (role == WorkspaceRole.maintainer)
/// — enforced at teardown: only maintainer workspaces may update README.md.
enum WorkspaceRole {
  maintainer,
  contributor;

  static WorkspaceRole fromString(String s) => switch (s) {
        'maintainer' => maintainer,
        'contributor' => contributor,
        _ => contributor,
      };

  /// Returns `true` when this role permits updating the project README.md.
  bool get canUpdateReadme => this == maintainer;

  String get value => name;
}

/// Proof notation standard declared for this workspace.
///
/// Governs how agents write invariants and proofs in comments and docs.
enum ProofNotation {
  dartGrounded,
  tsGrounded,
  generic;

  static ProofNotation fromString(String s) => switch (s) {
        'dart-grounded' => dartGrounded,
        'ts-grounded' => tsGrounded,
        _ => generic,
      };

  String get value => switch (this) {
        dartGrounded => 'dart-grounded',
        tsGrounded => 'ts-grounded',
        generic => 'generic',
      };

  /// Human-readable description loaded into scaffold.md.
  String get description => switch (this) {
        dartGrounded =>
          'Use ∀/∃/∧/∨/↔ with Dart expressions. '
              'Never use iff — express bidirectional logic as ↔ with Dart on both sides.',
        tsGrounded =>
          'Use ∀/∃/∧/∨/↔ with TypeScript expressions.',
        generic => 'Use plain English for invariants.',
      };
}

// ---------------------------------------------------------------------------
// WorkspaceConfig — parsed from workspace.json at session entry (Step 0).
// Agents read this; they never read workspace.json directly.
// ---------------------------------------------------------------------------

class WorkspaceOwner {
  final String name;
  final String email;
  final String handle;

  const WorkspaceOwner({
    required this.name,
    required this.email,
    required this.handle,
  });

  factory WorkspaceOwner.fromJson(Map<String, dynamic> json) => WorkspaceOwner(
        name: json['name'] as String,
        email: json['email'] as String,
        handle: json['handle'] as String,
      );
}

class WorkspaceProject {
  final String name;
  final List<StackType> stack;
  final WorkspaceRole role;
  final String? repo;
  final String? org;

  const WorkspaceProject({
    required this.name,
    required this.stack,
    required this.role,
    this.repo,
    this.org,
  });

  factory WorkspaceProject.fromJson(Map<String, dynamic> json) {
    final rawStack = (json['stack'] as List<dynamic>? ?? []).cast<String>();
    return WorkspaceProject(
      name: json['name'] as String,
      stack: rawStack
          .map(StackType.fromString)
          .whereType<StackType>()
          .toList(),
      role: WorkspaceRole.fromString(json['role'] as String? ?? 'contributor'),
      repo: json['repo'] as String?,
      org: json['org'] as String?,
    );
  }
}

class WorkspaceSession {
  final List<AgentType> agents;
  final List<String> knowledge;
  final ProofNotation proofNotation;
  final bool sensitivityMode;

  const WorkspaceSession({
    required this.agents,
    required this.knowledge,
    required this.proofNotation,
    required this.sensitivityMode,
  });

  factory WorkspaceSession.fromJson(Map<String, dynamic> json) {
    final rawAgents = (json['agents'] as List<dynamic>? ?? []).cast<String>();
    return WorkspaceSession(
      agents: rawAgents
          .map(AgentType.fromString)
          .whereType<AgentType>()
          .toList(),
      knowledge:
          (json['knowledge'] as List<dynamic>? ?? []).cast<String>(),
      proofNotation: ProofNotation.fromString(
          json['proofNotation'] as String? ?? 'generic'),
      sensitivityMode: json['sensitivityMode'] as bool? ?? false,
    );
  }
}

class WorkspaceConfig {
  final WorkspaceOwner owner;
  final WorkspaceProject project;
  final WorkspaceSession session;

  const WorkspaceConfig({
    required this.owner,
    required this.project,
    required this.session,
  });

  factory WorkspaceConfig.fromJson(Map<String, dynamic> json) =>
      WorkspaceConfig(
        owner: WorkspaceOwner.fromJson(
            json['owner'] as Map<String, dynamic>),
        project: WorkspaceProject.fromJson(
            json['project'] as Map<String, dynamic>),
        session: WorkspaceSession.fromJson(
            json['session'] as Map<String, dynamic>),
      );

  /// Loads and parses workspace.json for the given workspace directory.
  ///
  /// Returns `null` when the file is missing or unparseable — callers should
  /// stop and tell the user to run `/setup`.
  static WorkspaceConfig? load(String workspaceDir, {FileIO? io}) {
    final fileIO = io ?? const RealFileIO();
    final path = '$workspaceDir/workspace.json';
    final raw = fileIO.read(path);
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return WorkspaceConfig.fromJson(json);
    } on Exception catch (_) {
      return null;
    }
  }
}
