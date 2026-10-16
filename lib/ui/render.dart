// render.dart — the single owner of agent/subagent output formatting.
//
// Design: docs/agent_response_and_output.md.
//
// Each `AgentResponse` renders as a block with a continuous coloured gutter
// (`│`) and a coloured header; the body stays plain. The colour is the
// response's state `hue` (`StateHue`), translated to ANSI here — zedup
// renders the same enum as a nocterm Color instead, so this layer owns the
// `StateHue → ANSI` bridge, the CLI-medium counterpart to zedup's own
// rendering. Colour carries meaning on the header + gutter only,
// so the body stays readable and greppable, and ANSI strips cleanly when piped.
//
// No other module should format agent output.
//
// Update (2026-09-27): StateHue relocated from zedup into claudart's own
// pipeline/state_hue.dart — claudart owns the enum now, zedup re-exports it.

import '../pipeline/agent_response.dart';
import '../pipeline/state_hue.dart';
import '../session/session_state.dart' show HandoffStatus;
import 'ansi.dart' as ansi;

/// The `StateHue → ANSI` bridge — claudart's own mapping to its output
/// medium (ANSI escape codes), independent of zedup's nocterm mapping.
String hueCode(StateHue hue) => switch (hue) {
      StateHue.inactive => ansi.grey,
      StateHue.loading  => ansi.cyan,
      StateHue.ready    => ansi.white,
      StateHue.active   => ansi.yellow,
      StateHue.paused   => ansi.magenta,
      StateHue.error    => ansi.red,
      StateHue.success  => ansi.green,
    };

/// The ANSI colour a [HandoffStatus] is shown in on every command's status
/// line: cyan while exploring, yellow when ready to implement, green once
/// debug has begun, red when blocked, dim for the display-only variants.
String statusColour(HandoffStatus s) => switch (s) {
      HandoffStatus.suggestInvestigating ||
      HandoffStatus.readyForSuggest =>
        ansi.cyan,
      HandoffStatus.readyForDebug => ansi.yellow,
      HandoffStatus.debugInProgress ||
      HandoffStatus.debugComplete =>
        ansi.green,
      HandoffStatus.needsSuggest => ansi.red,
      HandoffStatus.unknown || HandoffStatus.noHandoff => ansi.dim,
    };

/// Wraps a block in a continuous gutter rule coloured by [hue]: the header on
/// the first line, then each body line, every line prefixed by the rule. The
/// gutter is the visible boundary that ties a block's content to its header and
/// status — and it nests (a caller can indent body lines that are themselves
/// blocks).
String block(StateHue hue, String headerLine, List<String> bodyLines) {
  final rule = ansi.c(hueCode(hue), '│');
  return [
    '$rule $headerLine',
    for (final line in bodyLines) '$rule $line',
  ].join('\n');
}

/// The block's first line: `<speaker>  <glyph> <KIND>  <subtitle>`. The kind
/// badge is coloured by the response hue; speaker and subtitle stay dim.
String _headerLine(AgentResponse r, String subtitle) {
  final lane  = ansi.c(ansi.dim, r.speaker.label);
  final badge = ansi.c(hueCode(r.hue), '${r.kind.icon} ${r.kind.label}');
  final tail  = subtitle.isEmpty ? '' : '  ${ansi.c(ansi.dim, subtitle)}';
  return '$lane  $badge$tail';
}

/// Orders subtasks so dependencies render before their dependents, breaking
/// ties by priority. A dependency cycle is tolerated (the visited guard stops
/// recursion) — render order is best-effort, not a scheduler.
List<Subtask> _dependencyOrder(List<Subtask> tasks) {
  final byId = {for (final t in tasks) t.id: t};
  final seen = <String>{};
  final out = <Subtask>[];
  void visit(Subtask t) {
    if (!seen.add(t.id)) return;
    for (final depId in [...t.dependsOn]..sort()) {
      final dep = byId[depId];
      if (dep != null) visit(dep);
    }
    out.add(t);
  }

  for (final t in [...tasks]..sort((a, b) => a.priority.compareTo(b.priority))) {
    visit(t);
  }
  return out;
}

/// Renders one response as a gutter-framed block.
String render(AgentResponse r) {
  switch (r) {
    case Plan(:final goal, :final subtasks):
      final done = subtasks.where((s) => s.state == SubtaskState.done).length;
      final body = <String>[
        ansi.c(ansi.dim, '$done/${subtasks.length} done'),
        for (final s in _dependencyOrder(subtasks))
          '${ansi.c(hueCode(s.state.hue), '◉')} ${ansi.c(hueCode(s.state.hue), s.id)}'
              '${s.dependsOn.isEmpty ? '' : ansi.c(ansi.dim, '  ⟂ ${s.dependsOn.join(', ')}')}',
      ];
      return block(r.hue, _headerLine(r, goal), body);

    case Progress(:final workspace, :final subtask, :final flow, :final blocked):
      return block(
        r.hue,
        _headerLine(r, '$workspace / $subtask'),
        ['${flow.name} · ${blocked ? 'blocked' : 'running'}'],
      );

    case Question(:final origin, :final workspace, :final blockedSubtask, :final question, :final options):
      final body = <String>[
        question,
        for (final o in options) '  - $o',
        ansi.c(ansi.dim, 'answer to unblock $blockedSubtask'),
      ];
      return block(
        r.hue,
        _headerLine(r, 'from $origin · $workspace / $blockedSubtask'),
        body,
      );

    case Action(:final workspace, :final subtask, :final verb, :final target, :final summary):
      final note = summary.isEmpty ? '' : ansi.c(ansi.dim, '  — $summary');
      return block(
        r.hue,
        _headerLine(r, '$workspace / $subtask'),
        ['${verb.glyph} ${verb.name} $target$note'],
      );

    case Result(:final workspace, :final subtask, :final filesTouched, :final summary):
      final body = <String>[
        summary,
        if (filesTouched.isNotEmpty)
          ansi.c(ansi.dim, '${filesTouched.length} file(s): ${filesTouched.join(', ')}'),
      ];
      return block(r.hue, _headerLine(r, '$workspace / $subtask'), body);

    case Blocker(:final workspace, :final step, :final errorType):
      return block(r.hue, _headerLine(r, '$workspace / $step'), [errorType]);

    case Handoff(:final from, :final to, :final resolvedInfo):
      return block(r.hue, _headerLine(r, '$from → $to'), [resolvedInfo]);

    case Replan(:final reason, :final oldOrder, :final newOrder):
      return block(
        r.hue,
        _headerLine(r, reason),
        [ansi.c(ansi.dim, oldOrder.join(' → ')), newOrder.join(' → ')],
      );
  }
}

/// Renders many responses with Questions floated to the top. Blocks separated
/// by a blank line.
String renderAll(Iterable<AgentResponse> responses) =>
    floatQuestions(responses).map(render).join('\n\n');

// ── Shared helpers for surfaces that don't yet emit structured responses ──────

/// The flow classification verdict, spoken by claudart, in the house style.
/// Pass enum `.name`s; `degraded` is true when categorize output was
/// unparseable and the plan step will fall back to sonnet.
String classification({
  String? category,
  String? intent,
  String? complexity,
  String? model,
  bool degraded = false,
}) {
  final label = ansi.c(ansi.dim, 'Classified:');
  if (degraded) {
    return '  $label  '
        '${ansi.c(ansi.dim, '(categorize output unparseable — plan will fall back to sonnet)')}';
  }
  final arrow = ansi.c(ansi.dim, '→');
  return '  $label  $category × $intent × $complexity  $arrow  $model';
}

/// A draft plan emitted by the agent at the approval gate, framed as a block.
String planDraft(String plan) {
  final headerLine =
      '${ansi.c(ansi.dim, Speaker.agent.label)}  '
      '${ansi.c(hueCode(StateHue.ready), '◆ Plan')}  '
      '${ansi.c(ansi.dim, 'draft — awaiting approval')}';
  return block(StateHue.ready, headerLine, plan.split('\n'));
}

/// The "not in scope files" context shown when a lookup step is exhausted.
String notInFiles(String context) =>
    '  ${ansi.c(ansi.dim, 'Not in files: $context')}';

// ── Shared formatting primitives ──────────────────────────────────────────────
//
// The building blocks commands used to hand-roll (bar headers, ✓/✗ status
// lines, aligned key/value rows). Centralizing them here makes claudart output
// consistent everywhere and is the dependency root for migrating scattered
// `print()` sites in lib/commands/.

/// Terminal status glyphs, enum-owned so call sites never hardcode ✓/✗/⚠/·.
enum StatusBadge {
  ok('✓', ansi.green),
  fail('✗', ansi.red),
  warn('⚠️', ansi.yellow),
  info('·', ansi.cyan);

  const StatusBadge(this.icon, this.colorCode);

  final String icon;
  final String colorCode;
}

/// A boxed section header: a bold rule, the indented title, a bold rule, framed
/// by blank lines. The single source for the `═══` headers commands hand-rolled.
String header(String title) {
  final bar = '═' * (title.length + 4);
  return '\n${ansi.c(ansi.bold, bar)}\n'
      '${ansi.c(ansi.bold, '  $title')}\n'
      '${ansi.c(ansi.bold, bar)}\n';
}

/// A status line: `  ✓  label   detail`. The detail is dimmed and omitted when
/// blank.
String status(StatusBadge badge, String label, {String? detail}) {
  final glyph = ansi.c(badge.colorCode, badge.icon);
  final tail = (detail == null || detail.isEmpty)
      ? ''
      : '  ${ansi.c(ansi.dim, detail)}';
  return '  $glyph  $label$tail';
}

/// An aligned key/value line: `  Key       : value`. [pad] sets the key column
/// width so consecutive fields line up.
String field(String key, String value, {int pad = 10}) =>
    '  ${key.padRight(pad)}: $value';

/// A thin horizontal rule used to separate sections within a command's
/// output (distinct from [header]'s boxed `═══` rule, which frames a whole
/// command's title). The single source for the `───` dividers commands
/// hand-rolled.
String divider() => '───────────────────────────────────────';

/// A compact single-line status indicator: `● [name|status]`, coloured by
/// [statusColorCode] — the format `status.dart`'s `--prompt` mode hand-rolled
/// for shell RPROMPT/PS1 use. [active] dims the dot and uses a hollow glyph
/// when the status isn't meaningfully "on" (e.g. `HandoffStatus.unknown`).
String statusBar({
  required String name,
  required String statusLabel,
  required String statusColorCode,
  bool active = true,
}) {
  final dot = active ? ansi.c(statusColorCode, '●') : ansi.c(ansi.dim, '○');
  return '$dot ${ansi.c(ansi.dim, '[')}${ansi.c(ansi.bold, name)}'
      '${ansi.c(ansi.dim, '|')}${ansi.c(statusColorCode, statusLabel)}${ansi.c(ansi.dim, ']')}';
}
