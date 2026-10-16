// render_test.dart — the render layer: fixed header position, optional-slot
// omission, distinct speaker lanes, questions-float, and no ANSI in non-TTY.
//
// Tests run without a TTY, so `ansi.c` strips colour codes — assertions match
// plain text and verify no escape sequences leak. Forced deterministic via
// colorEnabledOverride, since a `FORCE_COLOR`/`CLAUDART_FORCE_COLOR` env var
// in the ambient shell would otherwise make `ansi.c` emit escape codes here
// regardless of the real (non-TTY) terminal state.

import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/pipeline/agent_response.dart';
import 'package:claudart/session/session_state.dart' show HandoffStatus;
import 'package:claudart/ui/ansi.dart' as ansi;
import 'package:claudart/ui/render.dart' as render;
import 'package:test/test.dart';

AgentResponse _sample(ResponseKind kind) => switch (kind) {
      ResponseKind.plan => const Plan(
          speaker:  Speaker.agent,
          goal:     'ship it',
          subtasks: [Subtask(id: 'a', workspace: 'w', priority: 1)],
        ),
      ResponseKind.progress => const Progress(
          speaker:   Speaker.agent,
          workspace: 'w',
          subtask:   't',
          flow:      AgentFlow.flow,
          blocked:   false,
        ),
      ResponseKind.question => const Question(
          speaker:        Speaker.subagent,
          origin:         'b',
          workspace:      'w',
          blockedSubtask: 't',
          question:       'q?',
        ),
      ResponseKind.result => const Result(
          speaker:      Speaker.subagent,
          workspace:    'w',
          subtask:      't',
          filesTouched: [],
          summary:      'done',
        ),
      ResponseKind.blocker => const Blocker(
          speaker:   Speaker.subagent,
          workspace: 'w',
          step:      'compile',
          errorType: 'boom',
        ),
      ResponseKind.handoff => const Handoff(
          speaker:      Speaker.agent,
          from:         'a',
          to:           'b',
          resolvedInfo: 'use X',
        ),
      ResponseKind.replan => const Replan(
          speaker:  Speaker.agent,
          reason:   'answer changed priority',
          oldOrder: ['a', 'b'],
          newOrder: ['b', 'a'],
        ),
      ResponseKind.action => const Action(
          speaker:   Speaker.subagent,
          workspace: 'w',
          subtask:   't',
          verb:      ActionVerb.created,
          target:    'lib/x.dart',
          summary:   'new file',
        ),
    };

void main() {
  setUpAll(() => ansi.colorEnabledOverride = false);
  tearDownAll(() => ansi.colorEnabledOverride = null);

  group('statusColour — one colour per HandoffStatus', () {
    // Independent literal table: the colour each status has always shown.
    const expected = {
      HandoffStatus.suggestInvestigating: ansi.cyan,
      HandoffStatus.readyForSuggest: ansi.cyan,
      HandoffStatus.readyForDebug: ansi.yellow,
      HandoffStatus.debugInProgress: ansi.green,
      HandoffStatus.debugComplete: ansi.green,
      HandoffStatus.needsSuggest: ansi.red,
      HandoffStatus.noHandoff: ansi.dim,
      HandoffStatus.unknown: ansi.dim,
    };

    test('the table covers every variant', () {
      expect(expected.keys.toSet(), HandoffStatus.values.toSet());
    });

    for (final entry in expected.entries) {
      test(entry.key.name, () {
        expect(render.statusColour(entry.key), entry.value);
      });
    }
  });

  group('render — header first, no ANSI in non-TTY', () {
    for (final kind in ResponseKind.values) {
      test(kind.name, () {
        final response  = _sample(kind);
        final out       = render.render(response);
        final firstLine = out.split('\n').first;
        expect(firstLine, contains(kind.label));
        expect(firstLine, contains(response.speaker.label));
        expect(out, isNot(contains('\x1b')));
      });
    }
  });

  group('render — optional slots omit when empty', () {
    test('Question without options has no option bullet', () {
      final out = render.render(_sample(ResponseKind.question));
      expect(out, isNot(contains('\n  - ')));
    });

    test('Question with options lists them', () {
      final out = render.render(const Question(
        speaker:        Speaker.subagent,
        origin:         'b',
        workspace:      'w',
        blockedSubtask: 't',
        question:       'q?',
        options:        ['yes', 'no'],
      ));
      expect(out, contains('  - yes'));
      expect(out, contains('  - no'));
    });

    test('Result without files omits the files line', () {
      final out = render.render(_sample(ResponseKind.result));
      expect(out, isNot(contains('file(s)')));
    });
  });

  group('render — speaker lanes distinct', () {
    test('same kind, different speaker → different header label', () {
      final claudart = render.render(const Progress(
        speaker:   Speaker.claudart,
        workspace: 'w',
        subtask:   't',
        flow:      AgentFlow.flow,
        blocked:   false,
      ));
      final agent = render.render(const Progress(
        speaker:   Speaker.agent,
        workspace: 'w',
        subtask:   't',
        flow:      AgentFlow.flow,
        blocked:   false,
      ));
      expect(claudart.split('\n').first, contains('claudart'));
      expect(agent.split('\n').first, contains('agent'));
    });
  });

  group('renderAll — questions float to the top', () {
    test('a question renders before an earlier progress block', () {
      final out = render.renderAll([
        _sample(ResponseKind.progress),
        _sample(ResponseKind.question),
      ]);
      expect(out.indexOf('Question'), lessThan(out.indexOf('Progress')));
    });
  });

  group('render — Action and Plan specifics', () {
    test('Action shows the verb name and target', () {
      final out = render.render(_sample(ResponseKind.action));
      expect(out, contains('created'));
      expect(out, contains('lib/x.dart'));
    });

    test('Plan renders dependencies before dependents with a done count', () {
      final out = render.render(const Plan(
        speaker: Speaker.agent,
        goal:    'ship',
        subtasks: [
          Subtask(id: 'b', workspace: 'w', priority: 1, dependsOn: ['a']),
          Subtask(id: 'a', workspace: 'w', priority: 2, state: SubtaskState.done),
        ],
      ));
      expect(out, contains('1/2 done'));
      expect(out.indexOf('◉ a'), lessThan(out.indexOf('◉ b')));
    });
  });
}
