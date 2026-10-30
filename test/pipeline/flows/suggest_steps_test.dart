// suggest_steps_test.dart — SuggestSteps.applier's target-section fallback.
//
// _applierPrompt sends only the sections a change plan targets, to avoid
// round-tripping the full six-section analysis every refinement pass. If a
// targeted tag is missing from the analysis (model forgot to emit it), the
// naive version silently dropped it from what the applier sees — this locks
// in the fallback: any missing target sends the full analysis instead.

import 'package:claudart/pipeline/flows/suggest_steps.dart';
import 'package:claudart/pipeline/pipeline_context.dart';
import 'package:test/test.dart';

const _projectRoot = '/tmp/test-project';

PipelineContext _ctx({required String reasonerOut, required String plannerOut}) =>
    const PipelineContext(
      projectRoot: _projectRoot,
      bug: '',
      expected: '',
      files: const [],
    ).withSlot('reasoner', reasonerOut).withSlot('planner', plannerOut);

void main() {
  group('SuggestSteps.applier — target-section fallback', () {
    test('all targeted sections present → prompt contains only those sections', () {
      const analysis = '<ROOT_CAUSE>rc</ROOT_CAUSE>'
          '<SCOPE_FILES>sf</SCOPE_FILES>'
          '<CONSTRAINTS>c</CONSTRAINTS>';
      const changePlan = '<CHANGES>Update CONSTRAINTS only</CHANGES>';

      final prompt = SuggestSteps.applier(1).buildPrompt(
        _ctx(reasonerOut: analysis, plannerOut: changePlan),
      );

      expect(prompt, contains('<CONSTRAINTS>c</CONSTRAINTS>'));
      expect(prompt, isNot(contains('<ROOT_CAUSE>')));
    });

    test('a targeted section missing from the analysis → falls back to the '
        'full analysis, not a partial prompt missing that section entirely', () {
      // Analysis is missing SCOPE_FILES even though the change plan targets it.
      const analysis = '<ROOT_CAUSE>rc</ROOT_CAUSE>'
          '<CONSTRAINTS>c</CONSTRAINTS>';
      const changePlan = '<CHANGES>Update SCOPE_FILES and CONSTRAINTS</CHANGES>';

      final prompt = SuggestSteps.applier(1).buildPrompt(
        _ctx(reasonerOut: analysis, plannerOut: changePlan),
      );

      // Full analysis present (fallback), not just the extractable subset.
      expect(prompt, contains('<ROOT_CAUSE>rc</ROOT_CAUSE>'));
      expect(prompt, contains('<CONSTRAINTS>c</CONSTRAINTS>'));

      // The output instructions must not forbid the applier from emitting
      // SCOPE_FILES just because it wasn't in the existing analysis — it's
      // the very section the change plan targets and _mergeAnalysis() can
      // append it. A blanket "don't output anything not shown above" would
      // silently block the one thing this refinement pass needs to add.
      expect(prompt, isNot(contains('Do not output any section not shown above')));
      expect(prompt, contains('SCOPE_FILES'));
    });

    test('no recognized section names in the change plan → full analysis sent', () {
      const analysis = '<ROOT_CAUSE>rc</ROOT_CAUSE><CONSTRAINTS>c</CONSTRAINTS>';
      const changePlan = '<CHANGES>Something vague</CHANGES>';

      final prompt = SuggestSteps.applier(1).buildPrompt(
        _ctx(reasonerOut: analysis, plannerOut: changePlan),
      );

      expect(prompt, contains('<ROOT_CAUSE>rc</ROOT_CAUSE>'));
      expect(prompt, contains('<CONSTRAINTS>c</CONSTRAINTS>'));
    });
  });

  group('SuggestSteps.applier — postProcess merge (_mergeAnalysis)', () {
    test('an existing section is replaced in place', () {
      final ctx = _ctx(
        reasonerOut: '<ROOT_CAUSE>old</ROOT_CAUSE><CONSTRAINTS>c</CONSTRAINTS>',
        plannerOut: '',
      );
      final merged = SuggestSteps.applier(1).postProcess!(
        '<ROOT_CAUSE>new</ROOT_CAUSE>',
        ctx,
      );

      expect(merged, contains('<ROOT_CAUSE>new</ROOT_CAUSE>'));
      expect(merged, isNot(contains('old')));
      expect(merged, contains('<CONSTRAINTS>c</CONSTRAINTS>'));
    });

    test('a section the applier emits that the base analysis never had is '
        'appended, not silently dropped — replaceFirst is a no-op when the '
        'tag is not already present, which is exactly the case '
        '_applierPrompt\'s own fallback sends the applier the full analysis '
        'to try to avoid', () {
      final ctx = _ctx(
        reasonerOut: '<CONSTRAINTS>c</CONSTRAINTS>', // no ROOT_CAUSE at all
        plannerOut: '',
      );
      final merged = SuggestSteps.applier(1).postProcess!(
        '<ROOT_CAUSE>now provided</ROOT_CAUSE>',
        ctx,
      );

      expect(merged, contains('<CONSTRAINTS>c</CONSTRAINTS>'));
      expect(merged, contains('<ROOT_CAUSE>now provided</ROOT_CAUSE>'));
    });

    test('a tag absent from the applier\'s own response leaves that section '
        'untouched in the base — correct no-op, not a bug', () {
      final ctx = _ctx(
        reasonerOut: '<ROOT_CAUSE>rc</ROOT_CAUSE><CONSTRAINTS>c</CONSTRAINTS>',
        plannerOut: '',
      );
      final merged = SuggestSteps.applier(1).postProcess!(
        '<CONSTRAINTS>updated</CONSTRAINTS>', // no ROOT_CAUSE in the response
        ctx,
      );

      expect(merged, contains('<ROOT_CAUSE>rc</ROOT_CAUSE>'));
      expect(merged, contains('<CONSTRAINTS>updated</CONSTRAINTS>'));
    });
  });
}
