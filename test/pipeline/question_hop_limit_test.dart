// question_hop_limit_test.dart — the model can loop planner→QUESTION→lookup→
// ANSWER→planner forever if it never converges. PipelineExecutor must cap
// the number of question hops per run and stop with a clear error.

import 'package:claudart/claudart.dart';
import 'package:claudart/pipeline/route_tag.dart';
import 'package:test/test.dart';

PipelineContext _baseCtx() => const PipelineContext(
      projectRoot: '/tmp/test_project',
      bug: 'irrelevant',
      expected: 'irrelevant',
      files: [],
    );

void main() {
  test('executor stops after maxQuestionHops when the model never converges',
      () async {
    // planner always asks a question; lookup always answers, but the
    // answer never satisfies planner — an infinite QUESTION/ANSWER cycle.
    final planner = AgentStep(
      id: 'planner',
      label: 'Planning',
      model: AgentModel.sonnet,
      systemPrompt: '',
      buildPrompt: (ctx) => 'plan',
      routes: const {
        RouteTag.question: QuestionBranch('lookup'),
      },
    );
    final lookup = AgentStep(
      id: 'lookup',
      label: 'Looking up',
      model: AgentModel.haiku,
      systemPrompt: '',
      buildPrompt: (ctx) => 'lookup',
      routes: const {
        RouteTag.answer: FeedBackTo('planner'),
      },
    );

    var callCount = 0;
    final exec = PipelineExecutor(
      maxQuestionHops: 3,
      runner: ({
        required AgentModel model,
        required String systemPrompt,
        required String message,
        required String workingDir,
      }) async {
        callCount++;
        if (model == AgentModel.haiku) {
          return (
            text: '<ANSWER>still not enough</ANSWER>',
            usage:
                const Usage(input: 10, output: 5, cost: 0.0001, cacheRead: 0),
          );
        }
        return (
          text: '<QUESTION>what else do you need?</QUESTION>',
          usage: const Usage(input: 20, output: 10, cost: 0.0002, cacheRead: 0),
        );
      },
    );

    // `.take(50)` is a hang guard: if the hop limit ever regresses, the
    // events list simply comes back short (no AgentFailed) instead of
    // stalling the suite on an infinite QUESTION/ANSWER cycle.
    final events = await exec
        .run(
          steps: [planner, lookup],
          ctx: _baseCtx(),
          displayStep: 1,
          displayTotal: 1,
        )
        .take(50)
        .toList();

    final failed = events.whereType<AgentFailed>().toList();
    expect(failed, hasLength(1));
    expect(failed.first.reason, contains('3 questions without converging'));

    expect(events.last, isA<PipelineCompleted>());

    // The loop must have actually stopped — not run away.
    expect(callCount, lessThan(20));
  });
}
