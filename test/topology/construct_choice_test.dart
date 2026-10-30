// construct_choice_test.dart — the proof that the choice of construct is
// decided, consistent, and applied.
//
// Part 1 proves the decision table (test/helpers/construct_choice.dart) over
// every combination of its facts: each case is decided by some rule, no rule
// is dead, every construct is reachable, and the properties that state the
// best practice hold. Part 2 names real cases and the construct they call
// for. Part 3 runs the detectors over lib/ and holds each count at its floor: a
// new case that uses the wrong construct fails here, naming the declaration.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/construct_choice.dart';

const _bool = [false, true];

/// Whether the guard-clause rule, which outranks the others, applies.
bool _guardApplies(CaseFacts f) =>
    f.failingBranchEnds && f.alternatives != Alternatives.threeOrMore;

/// Every combination of the seven yes-or-no facts for one setting of the three
/// graded ones.
Iterable<CaseFacts> _combinations(
  DecisionSites sites,
  Alternatives alternatives,
  RelatedParameters related,
) sync* {
  for (final closedSet in _bool) {
    for (final data in _bool) {
      for (final plain in _bool) {
        for (final shares in _bool) {
          for (final byInput in _bool) {
            for (final notEditable in _bool) {
              for (final ends in _bool) {
                yield (
                  closedSet: closedSet,
                  carriesDifferentData: data,
                  decisionSites: sites,
                  resultIsPlainValue: plain,
                  typesShareProperties: shares,
                  chosenByInput: byInput,
                  typeNotEditable: notEditable,
                  alternatives: alternatives,
                  failingBranchEnds: ends,
                  relatedParameters: related,
                );
              }
            }
          }
        }
      }
    }
  }
}

/// Every case in the domain: 2^7 x 3 x 3 x 2 = 2304.
Iterable<CaseFacts> _allCases() sync* {
  for (final sites in DecisionSites.values) {
    for (final alternatives in Alternatives.values) {
      for (final related in RelatedParameters.values) {
        yield* _combinations(sites, alternatives, related);
      }
    }
  }
}

CaseFacts _case({
  bool closedSet = false,
  bool carriesDifferentData = false,
  DecisionSites sites = DecisionSites.none,
  bool plainValue = false,
  bool sharesProperties = false,
  bool byInput = false,
  bool notEditable = false,
  Alternatives alternatives = Alternatives.one,
  bool ends = false,
  RelatedParameters related = RelatedParameters.fewerThanThree,
}) =>
    (
      closedSet: closedSet,
      carriesDifferentData: carriesDifferentData,
      decisionSites: sites,
      resultIsPlainValue: plainValue,
      typesShareProperties: sharesProperties,
      chosenByInput: byInput,
      typeNotEditable: notEditable,
      alternatives: alternatives,
      failingBranchEnds: ends,
      relatedParameters: related,
    );

Map<String, String> _libSources() => {
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          p.normalize(entity.path): entity.readAsStringSync(),
    };

/// Independent literals: how many cases each detector may still report. Each
/// may only go down, to zero, as the code is consolidated.
const _knownEnumsWithFactSwitches = 13;
const _knownIntConstantNamespaces = 0;
const _knownSeamHeavyFunctions = 0;

void main() {
  group('the decision table decides every case', () {
    for (final sites in DecisionSites.values) {
      for (final alternatives in Alternatives.values) {
        for (final related in RelatedParameters.values) {
          test(
            'sites ${sites.name}, alternatives ${alternatives.name}, '
            'parameters ${related.name}: all 128 cases have a rule',
            () {
              for (final facts in _combinations(sites, alternatives, related)) {
                expect(() => ruleFor(facts), returnsNormally);
              }
            },
          );
        }
      }
    }

    test('the domain is the 2304 cases the proof claims', () {
      expect(_allCases().length, 2304);
    });
  });

  group('every rule and every construct is used', () {
    for (final rule in ConstructRule.values) {
      test('${rule.name} is the deciding rule for some case', () {
        expect(_allCases().any((facts) => ruleFor(facts) == rule), isTrue);
      });
    }

    for (final construct in Construct.values) {
      test('${construct.name} is chosen for some case', () {
        expect(
          _allCases().any((facts) => chooseConstruct(facts) == construct),
          isTrue,
        );
      });
    }
  });

  group('the best-practice properties hold for every case', () {
    test('a precondition with two or fewer outcomes is a guard clause', () {
      for (final facts in _allCases().where((f) =>
          f.failingBranchEnds && f.alternatives != Alternatives.threeOrMore)) {
        expect(chooseConstruct(facts), Construct.guardClause);
      }
    });

    test('three or more related values are a bundle, unless it is a guard', () {
      for (final facts in _allCases().where((f) =>
          f.relatedParameters == RelatedParameters.threeOrMore &&
          !_guardApplies(f))) {
        expect(chooseConstruct(facts), Construct.bundleType);
      }
    });

    test('behavior that differs per variant at many places is overridden on '
        'the variants', () {
      for (final facts in _allCases().where((f) =>
          f.closedSet &&
          !f.carriesDifferentData &&
          f.decisionSites == DecisionSites.many &&
          !f.resultIsPlainValue &&
          f.relatedParameters == RelatedParameters.fewerThanThree &&
          !_guardApplies(f))) {
        expect(chooseConstruct(facts), Construct.sealedHierarchy);
      }
    });

    test('a closed set whose variants carry different data is sealed', () {
      for (final facts in _allCases().where((f) =>
          f.closedSet &&
          f.carriesDifferentData &&
          f.relatedParameters == RelatedParameters.fewerThanThree &&
          !_guardApplies(f))) {
        expect(chooseConstruct(facts), Construct.sealedHierarchy);
      }
    });

    test('facts repeated at many sites are enum fields, never another switch',
        () {
      for (final facts in _allCases().where((f) =>
          f.closedSet &&
          !f.carriesDifferentData &&
          f.decisionSites == DecisionSites.many &&
          f.resultIsPlainValue &&
          f.relatedParameters == RelatedParameters.fewerThanThree &&
          !_guardApplies(f))) {
        expect(chooseConstruct(facts), Construct.enhancedEnumField);
      }
    });

    test('a switch is the answer only where one place maps the variants', () {
      for (final facts in _allCases()) {
        if (chooseConstruct(facts) == Construct.switchExpression &&
            facts.closedSet &&
            !facts.carriesDifferentData) {
          expect(facts.decisionSites, DecisionSites.one);
        }
      }
    });

    test('a repeated decision never falls back from a field to a switch', () {
      for (final facts in _allCases()
          .where((f) => f.decisionSites == DecisionSites.one)) {
        final more = (
          closedSet: facts.closedSet,
          carriesDifferentData: facts.carriesDifferentData,
          decisionSites: DecisionSites.many,
          resultIsPlainValue: facts.resultIsPlainValue,
          typesShareProperties: facts.typesShareProperties,
          chosenByInput: facts.chosenByInput,
          typeNotEditable: facts.typeNotEditable,
          alternatives: facts.alternatives,
          failingBranchEnds: facts.failingBranchEnds,
          relatedParameters: facts.relatedParameters,
        );
        if (chooseConstruct(facts) == Construct.enhancedEnumField) {
          expect(chooseConstruct(more), Construct.enhancedEnumField);
        }
      }
    });

    test('the decision depends only on the facts: the same facts, one answer',
        () {
      for (final facts in _allCases()) {
        expect(chooseConstruct(facts), chooseConstruct(facts));
      }
    });
  });

  group('named cases call for the construct the architecture uses', () {
    // Independent literals: (what the code needs, the facts, the construct).
    final cases = <String, (CaseFacts, Construct)>{
      'the next step to show for each handoff status, read by two commands': (
        _case(
          closedSet: true,
          sites: DecisionSites.many,
          plainValue: true,
          alternatives: Alternatives.threeOrMore,
        ),
        Construct.enhancedEnumField,
      ),
      'the agent response variants, each with its own fields': (
        _case(
          closedSet: true,
          carriesDifferentData: true,
          alternatives: Alternatives.threeOrMore,
        ),
        Construct.sealedHierarchy,
      ),
      'stop when the project is not registered': (
        _case(ends: true, alternatives: Alternatives.two),
        Construct.guardClause,
      ),
      'nine injected seams passed to every command': (
        _case(related: RelatedParameters.threeOrMore),
        Construct.bundleType,
      ),
      'a menu whose choices were integer constants': (
        _case(closedSet: true),
        Construct.enumType,
      ),
      'the one mapping from a failure to its label': (
        _case(
          closedSet: true,
          sites: DecisionSites.one,
          plainValue: true,
          alternatives: Alternatives.threeOrMore,
        ),
        Construct.switchExpression,
      ),
      'classes that hold the same workspace fields': (
        _case(sharesProperties: true),
        Construct.abstractBaseClass,
      ),
      'build the logger that fits the registry entry': (
        _case(byInput: true),
        Construct.factoryConstructor,
      ),
      'add behavior to a type from another package': (
        _case(notEditable: true),
        Construct.extensionMethod,
      ),
      'pick one of two text values': (
        _case(plainValue: true, alternatives: Alternatives.two),
        Construct.ternary,
      ),
      'two real branches doing different work': (
        _case(alternatives: Alternatives.two),
        Construct.ifElse,
      ),
      'a statement with nothing to decide': (
        _case(),
        Construct.plainStatement,
      ),
    };

    cases.forEach((name, expected) {
      test(name, () {
        expect(chooseConstruct(expected.$1), expected.$2);
      });
    });
  });

  group('the detectors find cases that use the wrong construct', () {
    test('enumsWithFactSwitches finds an enum with two getter switches', () {
      expect(
        enumsWithFactSwitches({
          'lib/a.dart': 'enum Kind {\n  one;\n'
              '  String get a => switch (this) { one => "x" };\n'
              '  int get b => switch (this) { one => 1 };\n}\n',
        }),
        ['Kind (2 getters) in lib/a.dart'],
      );
    });

    test('enumsWithFactSwitches ignores an enum with one', () {
      expect(
        enumsWithFactSwitches({
          'lib/a.dart': 'enum Kind {\n  one;\n'
              '  String get a => switch (this) { one => "x" };\n}\n',
        }),
        isEmpty,
      );
    });

    test('intConstantNamespaces finds integer constants standing in for an '
        'enum', () {
      expect(
        intConstantNamespaces({
          'lib/a.dart': 'abstract final class Menu {\n'
              '  static const a = 0;\n  static const b = 1;\n}\n',
        }),
        ['Menu in lib/a.dart'],
      );
    });

    test('seamHeavyFunctions finds a function with three seam parameters', () {
      expect(
        seamHeavyFunctions({
          'lib/a.dart': 'Future<void> runIt({FileIO? io, ProcessRunner? '
              'runner, Never Function(int c)? exitFn}) async {}',
        }),
        ['runIt (3) in lib/a.dart'],
      );
    });

    test('seamHeavyFunctions ignores a function with fewer', () {
      expect(
        seamHeavyFunctions({
          'lib/a.dart':
              'Future<void> runIt({FileIO? io, String? name}) async {}',
        }),
        isEmpty,
      );
    });
  });

  group('the code uses the construct the table chooses', () {
    final sources = _libSources();

    test('an enum stating facts as repeated getter switches should hold '
        'them as fields: the table agrees', () {
      final facts = _case(
        closedSet: true,
        sites: DecisionSites.many,
        plainValue: true,
        alternatives: Alternatives.threeOrMore,
      );
      expect(chooseConstruct(facts), Construct.enhancedEnumField);
    });

    test('enums stating facts as getter switches do not grow', () {
      final found = enumsWithFactSwitches(sources);
      expect(
        found.length,
        lessThanOrEqualTo(_knownEnumsWithFactSwitches),
        reason: 'an enum states two or more facts with `get x => switch '
            '(this)`: make them constructor fields. Found: $found',
      );
    });

    test('integer constants standing in for an enum do not grow', () {
      final found = intConstantNamespaces(sources);
      expect(
        found.length,
        lessThanOrEqualTo(_knownIntConstantNamespaces),
        reason: 'a class of integer constants is an enum: $found',
      );
    });

    test('functions with three or more seam parameters do not grow', () {
      final found = seamHeavyFunctions(sources);
      expect(
        found.length,
        lessThanOrEqualTo(_knownSeamHeavyFunctions),
        reason: 'three or more seam parameters travel together: pass one '
            'bundle. Found: $found',
      );
    });
  });
}
