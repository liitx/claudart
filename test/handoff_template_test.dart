import 'package:test/test.dart';
import 'package:claudart/handoff_template.dart';

void main() {
  group('handoffTemplate', () {
    final result = handoffTemplate(
      branch: 'fix/my-bug',
      date: '2026-03-15',
      bug: 'Widget does not update on state change',
      expected: 'Widget reflects latest state immediately',
      projectName: 'my-app',
    );

    test('includes project name in title', () {
      expect(result, contains('Agent Handoff — my-app'));
    });

    test('includes branch and date', () {
      expect(result, contains('Branch: fix/my-bug'));
      expect(result, contains('2026-03-15'));
    });

    test('includes bug and expected behavior', () {
      expect(result, contains('Widget does not update on state change'));
      expect(result, contains('Widget reflects latest state immediately'));
    });

    test('sets initial status to suggest-investigating', () {
      expect(result, contains('suggest-investigating'));
    });

    test('uses placeholder for missing files', () {
      expect(result, contains('_Not yet determined._'));
    });

    test('includes optional files when provided', () {
      final t = handoffTemplate(
        branch: 'main',
        date: '2026-01-01',
        bug: 'bug',
        expected: 'expected',
        projectName: 'my-app',
        files: 'my_feature.dart',
        blocs: 'MyFeatureBloc',
      );
      expect(t, contains('my_feature.dart'));
      expect(t, contains('MyFeatureBloc'));
    });
  });

  group('blankHandoff', () {
    test('is non-empty', () {
      expect(blankHandoff, isNotEmpty);
    });

    test('contains status section', () {
      expect(blankHandoff, contains('## Status'));
      expect(blankHandoff, contains('suggest-investigating'));
    });

    test('contains all required sections', () {
      for (final section in ['Bug', 'Root Cause', 'Scope', 'Debug Progress']) {
        expect(blankHandoff, contains('## $section'));
      }
    });
  });
}
