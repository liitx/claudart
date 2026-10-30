// construct_choice.dart — which Dart construct fits a case, from its facts.
//
// A case is described by a handful of facts about the code: is the set of
// alternatives closed, do they carry different data, how many places branch on
// them, and so on. `chooseConstruct` is the decision table: an ordered list of
// named rules, each a predicate over the facts and the construct it selects.
// The facts come from small finite domains, so the table is checked over every
// combination (construct_choice_test.dart): every case is decided by some rule,
// and the properties that state the best practice hold.
//
// The detectors below turn real code into facts, so the same table that is
// proved decides whether the code uses the construct it should.

/// How many places branch on the same alternatives for the same concern.
enum DecisionSites { none, one, many }

/// How many alternative outcomes a decision has.
enum Alternatives { one, two, threeOrMore }

/// Whether three or more related values travel together.
enum RelatedParameters { fewerThanThree, threeOrMore }

/// The facts that decide which construct fits a case.
typedef CaseFacts = ({
  /// The alternatives are a finite set known at compile time.
  bool closedSet,

  /// Different alternatives need different fields.
  bool carriesDifferentData,

  /// How many places branch on the alternatives for one concern.
  DecisionSites decisionSites,

  /// What each alternative yields is a plain value, not behavior.
  bool resultIsPlainValue,

  /// Two or more types hold the same properties.
  bool typesShareProperties,

  /// Which instance or type gets built depends on an input.
  bool chosenByInput,

  /// The type cannot be edited, so behavior can only be added from outside.
  bool typeNotEditable,

  /// How many alternative outcomes the decision has.
  Alternatives alternatives,

  /// The failing branch ends the function (a return, a throw, an exit).
  bool failingBranchEnds,

  /// How many related values are passed together.
  RelatedParameters relatedParameters,
});

/// The construct a case should use.
enum Construct {
  /// An early return or throw at the top of the function.
  guardClause,

  /// One class or record that carries the related values.
  bundleType,

  /// A sealed class with a variant per alternative; where the variants differ
  /// in behavior, each overrides the method instead of a switch repeating.
  sealedHierarchy,

  /// An abstract base class holding the shared properties; variants extend it.
  abstractBaseClass,

  /// Each variant's value is a constructor field of an enhanced enum.
  enhancedEnumField,

  /// One switch that maps the alternatives, in the only place that decides.
  switchExpression,

  /// A plain enum with no per-variant data.
  enumType,

  /// A factory constructor that picks what to build, once.
  factoryConstructor,

  /// An extension method adding behavior from outside.
  extensionMethod,

  /// A conditional expression choosing between two values.
  ternary,

  /// An if and else for two real branches.
  ifElse,

  /// No branching at all.
  plainStatement,
}

/// A decision rule: a name for the reason, and when it applies.
enum ConstructRule {
  guardForPrecondition,
  bundleForRelatedParameters,
  sealedForDifferingData,
  enumFieldForRepeatedFacts,
  sealedForRepeatedBehavior,
  switchForOneMapping,
  enumForClosedSetWithoutData,
  baseForSharedProperties,
  factoryForChoiceByInput,
  extensionForUneditableType,
  ternaryForTwoValues,
  ifElseForTwoBranches,
  switchForManyBranches,
  nothingToDecide;

  /// The construct this rule selects.
  Construct get construct => switch (this) {
        guardForPrecondition => Construct.guardClause,
        bundleForRelatedParameters => Construct.bundleType,
        sealedForDifferingData ||
        sealedForRepeatedBehavior =>
          Construct.sealedHierarchy,
        enumFieldForRepeatedFacts => Construct.enhancedEnumField,
        switchForOneMapping ||
        switchForManyBranches =>
          Construct.switchExpression,
        enumForClosedSetWithoutData => Construct.enumType,
        baseForSharedProperties => Construct.abstractBaseClass,
        factoryForChoiceByInput => Construct.factoryConstructor,
        extensionForUneditableType => Construct.extensionMethod,
        ternaryForTwoValues => Construct.ternary,
        ifElseForTwoBranches => Construct.ifElse,
        nothingToDecide => Construct.plainStatement,
      };

  /// Whether this rule applies to [facts].
  bool applies(CaseFacts facts) => switch (this) {
        guardForPrecondition =>
          facts.failingBranchEnds &&
              facts.alternatives != Alternatives.threeOrMore,
        bundleForRelatedParameters =>
          facts.relatedParameters == RelatedParameters.threeOrMore,
        sealedForDifferingData =>
          facts.closedSet && facts.carriesDifferentData,
        enumFieldForRepeatedFacts => facts.closedSet &&
            !facts.carriesDifferentData &&
            facts.decisionSites == DecisionSites.many &&
            facts.resultIsPlainValue,
        // Behavior, not a plain value, that differs per variant at many places
        // belongs on the variants, as overridden methods, not in repeated
        // switches.
        sealedForRepeatedBehavior => facts.closedSet &&
            !facts.carriesDifferentData &&
            facts.decisionSites == DecisionSites.many &&
            !facts.resultIsPlainValue,
        switchForOneMapping => facts.closedSet &&
            !facts.carriesDifferentData &&
            facts.decisionSites == DecisionSites.one,
        enumForClosedSetWithoutData => facts.closedSet &&
            !facts.carriesDifferentData &&
            facts.decisionSites == DecisionSites.none,
        baseForSharedProperties => facts.typesShareProperties,
        factoryForChoiceByInput => facts.chosenByInput,
        extensionForUneditableType => facts.typeNotEditable,
        ternaryForTwoValues => facts.alternatives == Alternatives.two &&
            facts.resultIsPlainValue,
        ifElseForTwoBranches => facts.alternatives == Alternatives.two,
        switchForManyBranches => facts.alternatives == Alternatives.threeOrMore,
        nothingToDecide => facts.alternatives == Alternatives.one,
      };
}

/// The first rule that applies to [facts], in the order of [ConstructRule]; a
/// case no rule decides is a hole in the table and throws, so a test over every
/// combination of facts proves there is none.
ConstructRule ruleFor(CaseFacts facts) {
  for (final rule in ConstructRule.values) {
    if (rule.applies(facts)) return rule;
  }
  throw StateError('no rule decides $facts');
}

/// The construct [facts] call for.
Construct chooseConstruct(CaseFacts facts) => ruleFor(facts).construct;

// ── Detectors: real code to facts ───────────────────────────────────────────

/// The body of the first `{...}` at or after [start] in [source].
String _bodyFrom(String source, int start) {
  final open = source.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}

/// How many getters of the enum declared at [match] switch on `this`.
int _getterSwitches(String source, RegExpMatch match) => RegExp(
      r'\bget \w+\s*=>\s*switch \(this\)',
    ).allMatches(_bodyFrom(source, match.start)).length;

/// Enums that state two or more facts about their variants as getters that
/// switch on `this`: `Name (n getters) in file`.
List<String> enumsWithFactSwitches(Map<String, String> sources) {
  final declaration = RegExp(r'^enum (\w+)[^{]*\{', multiLine: true);
  return [
    for (final entry in sources.entries)
      for (final match in declaration.allMatches(entry.value))
        if (_getterSwitches(entry.value, match) >= 2)
          '${match.group(1)} (${_getterSwitches(entry.value, match)} getters) '
              'in ${entry.key}',
  ]..sort();
}

/// Namespaces of integer constants standing in for an enum: `Name in file`.
List<String> intConstantNamespaces(Map<String, String> sources) {
  final constant = RegExp(r'static const \w* ?\w+ = \d+;');
  final declaration = RegExp(
    r'^abstract final class (\w+)\s*\{',
    multiLine: true,
  );
  return [
    for (final entry in sources.entries)
      for (final match in declaration.allMatches(entry.value))
        if (constant
                .allMatches(_bodyFrom(entry.value, match.start))
                .length >=
            2)
          '${match.group(1)} in ${entry.key}',
  ]..sort();
}

/// The injected-seam parameters a command function repeats.
const seamParameterNames = [
  'io',
  'runner',
  'exitFn',
  'confirmFn',
  'promptFn',
  'pickFn',
  'projectRootOverride',
  'mode',
  'executor',
  'askFn',
];

/// How many seam parameters the parameter list [parameters] declares.
int _seamCount(String parameters) => seamParameterNames
    .where((name) => RegExp('\\b$name\\b').hasMatch(parameters))
    .length;

/// Functions that declare three or more seam parameters: `name (n) in file`.
List<String> seamHeavyFunctions(Map<String, String> sources) {
  final signature = RegExp(
    r'(?:Future<[^>]*>|void|\w+)\s+(\w+)\(\{([^}]*)\}\)\s*(?:async)?\s*\{',
  );
  return [
    for (final entry in sources.entries)
      for (final match in signature.allMatches(entry.value))
        if (_seamCount(match.group(2)!) >= 3)
          '${match.group(1)} (${_seamCount(match.group(2)!)}) in ${entry.key}',
  ]..sort();
}
