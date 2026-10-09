/// Custom lint rules. Most are derived by hand from dartrix's PARADIGMS.md
/// (see "Sync process" below); `UnconditionalConfirmRequiresPromptFn` is the
/// one exception — it's claudart-local, tied to this repo's own
/// `confirmFn`/`askFn`/`promptFn` interactive-prompt API shape, not a
/// general cross-repo convention dartrix would own. Don't route a future
/// PARADIGMS.md proposal for it; add claudart-local rules like it directly
/// here and say so in their own doc comment.
///
/// ## Dependency verdict
///
/// dartrix is intentionally absent from this package's `pubspec.yaml` — even
/// as a dev dependency. claudart's shipped runtime (`lib/`) has zero
/// `package:dartrix` imports; dartrix appears only in the root package's
/// `dev_dependencies` for test-time matrix coverage (`test/matrix/`). Lint
/// enforcement does not require a code-level link to dartrix.
///
/// ## Sync process
///
/// These rules re-derive paradigms from PARADIGMS.md prose. There is no
/// compile-time signal when PARADIGMS.md gains a new paradigm and this file
/// does not. The process to stay in sync:
///
/// 1. Propose the new paradigm as a PR against `dartrix/PARADIGMS.md`.
/// 2. Once merged, hand-port the corresponding `DartLintRule` into this file.
/// 3. Add it to `_ClaudartLints.getLintRules`.
///
/// Staying in sync is a convention, not a code dependency. Do not add dartrix
/// as a dependency here to mechanise this — the lint rules depend only on
/// `analyzer` and `custom_lint_builder`, and that must stay true.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

PluginBase createPlugin() => _ClaudartLints();

class _ClaudartLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        BareStringForEnum(),
        EnumValuesLoopInSingleTest(),
        UngroupedIdenticalSwitchCases(),
        UnconditionalConfirmRequiresPromptFn(),
      ];
}

/// Flags `switch` statements dispatching on two or more string-literal
/// `case` values. claudart's standing rule: "every user-facing literal,
/// every config key, every path, every CLI arg lives on an enhanced-enum
/// getter" — a switch on raw string literals is exactly the shape that
/// rule forbids, and `missing_enum_constant_in_switch` can't catch it
/// because the switch was never typed on an enum in the first place.
class BareStringForEnum extends DartLintRule {
  BareStringForEnum() : super(code: _code);

  static const _code = LintCode(
    name: 'bare_string_for_enum',
    problemMessage:
        'Switch dispatches on string literals instead of an enum. '
        'Model these cases as an enum and switch on it.',
    correctionMessage:
        'Introduce (or reuse) an enum whose variants are these string '
        'values, then switch on the enum.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    // A pure string→enum translation factory (fromString-style) is
    // sometimes written as a switch *statement* with string-literal cases
    // too, and that shape is legitimate — it's the canonical, singular
    // place a string maps to its enum, not behavior dispatch. The
    // distinguishing signal, same as the switch-expression check below:
    // illegitimate dispatch has at least one case body that *does*
    // something (a call/await), not just returns/assigns a plain value.
    context.registry.addSwitchStatement((node) {
      final literalCases = node.members.where(_isStringLiteralCase).toList();
      if (literalCases.length < 2) return;
      if (!literalCases.any(_isActionCase)) return;
      reporter.atNode(node, _code);
    });

    // Switch *expressions* (`switch (x) { 'a' => ... }`) are the same
    // dispatch shape and can bypass the statement-only check above.
    context.registry.addSwitchExpression((node) {
      final literalCases = node.cases.where(_isStringLiteralExpressionCase).toList();
      if (literalCases.length < 2) return;
      if (!literalCases.any((c) => _containsAction(c.expression))) return;
      reporter.atNode(node, _code);
    });
  }

  /// True when [member]'s statements contain an action (a call/await), the
  /// same signal [_containsAction] checks for switch-expression cases —
  /// mirrored here so both switch shapes are held to one standard.
  static bool _isActionCase(SwitchMember member) =>
      member.statements.any(_containsAction);

  /// True when an action (a call/await) appears anywhere inside [node], not
  /// just as its top-level form — a top-level-only check misses actions
  /// wrapped in parentheses (`(doThing())`), conditionals
  /// (`cond ? doThing() : other`), or any other nesting.
  static bool _containsAction(AstNode node) {
    try {
      node.accept(const _ActionExpressionFinder());
      return false;
    } on _ActionFound {
      return true;
    }
  }

  static bool _isStringLiteralCase(SwitchMember member) {
    if (member is SwitchCase) {
      return member.expression is StringLiteral;
    }
    if (member is SwitchPatternCase) {
      final pattern = member.guardedPattern.pattern;
      return pattern is ConstantPattern && pattern.expression is StringLiteral;
    }
    return false;
  }

  static bool _isStringLiteralExpressionCase(SwitchExpressionCase case_) {
    final pattern = case_.guardedPattern.pattern;
    return pattern is ConstantPattern && pattern.expression is StringLiteral;
  }

}

/// Thrown by [_ActionExpressionFinder] the moment it finds an action, so the
/// walk stops immediately instead of finishing the subtree — a switch case
/// is small, but this runs once per case across every switch in the file.
class _ActionFound implements Exception {
  const _ActionFound();
}

/// Finds whether a case body (a list of statements, unlike a switch
/// expression's single `=>` expression) contains a call/await anywhere —
/// the same "does something" signal [BareStringForEnum._containsAction]
/// checks for switch expressions. Throws [_ActionFound] on the first match
/// rather than setting a flag, so [AstNode.visitChildren] unwinds instead of
/// continuing to walk sibling subtrees that can no longer change the result.
class _ActionExpressionFinder extends RecursiveAstVisitor<void> {
  const _ActionExpressionFinder();

  @override
  void visitMethodInvocation(MethodInvocation node) => throw const _ActionFound();

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      throw const _ActionFound();

  @override
  void visitAwaitExpression(AwaitExpression node) => throw const _ActionFound();
}

/// Flags a `for` loop over `SomeEnum.values` nested inside a single
/// `test()` body. dartrix's `testing` paradigm (PARADIGMS.md): "Matrix-driven
/// ... Enum-owned test groups, generic bodies, test names from variant
/// identity." A loop inside one `test()` collapses every variant's pass/fail
/// into one indistinguishable result — the first failure stops the loop and
/// hides every variant after it. The loop must wrap `test()`, one call per
/// variant, never the reverse.
class EnumValuesLoopInSingleTest extends DartLintRule {
  EnumValuesLoopInSingleTest() : super(code: _code);

  static const _code = LintCode(
    name: 'enum_values_loop_in_single_test',
    problemMessage:
        'Looping over enum .values inside a single test() body collapses '
        'every variant into one pass/fail and hides which one broke.',
    correctionMessage:
        'Move the for loop outside test() — one test() call per variant, '
        'named from the variant identity.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      // target == null: an unqualified call, e.g. `test(...)` from
      // package:test's top-level function — not `someObject.test(...)`,
      // an instance method that happens to share the name.
      if (node.target != null) return;
      if (node.methodName.name != 'test') return;
      final callback = node.argumentList.arguments
          .whereType<FunctionExpression>()
          .firstOrNull;
      if (callback == null) return;

      final finder = _EnumValuesForLoopFinder();
      callback.body.accept(finder);
      for (final loop in finder.matches) {
        reporter.atNode(loop, _code);
      }
    });
  }
}

/// Collects every `for`-each loop whose iterable is `SomeEnum.values` —
/// specifically an enum's static `.values`, not any `.values` getter
/// (e.g. `someMap.values`, a completely unrelated, common Dart pattern
/// that happens to share the property name).
class _EnumValuesForLoopFinder extends RecursiveAstVisitor<void> {
  final List<ForStatement> matches = [];

  @override
  void visitForStatement(ForStatement node) {
    final forLoopParts = node.forLoopParts;
    if (forLoopParts is ForEachParts && _isEnumValuesAccess(forLoopParts.iterable)) {
      matches.add(node);
    }
    super.visitForStatement(node);
  }

  /// True only when [iterableExpression] is `.values` accessed on an enum
  /// type itself (`SomeEnum.values`), verified via the resolved element —
  /// not by property name alone, which `someMap.values` also matches.
  static bool _isEnumValuesAccess(Expression iterableExpression) => switch (iterableExpression) {
        PropertyAccess(:final propertyName, :final target) =>
          propertyName.name == 'values' && target != null && _referencesEnum(target),
        PrefixedIdentifier(:final identifier, :final prefix) =>
          identifier.name == 'values' && _referencesEnum(prefix),
        _ => false,
      };

  /// True when [expression] itself refers to an enum declaration (as a
  /// type reference, e.g. the `SomeEnum` in `SomeEnum.values`) or has a
  /// static type whose element is an enum.
  static bool _referencesEnum(Expression expression) {
    if (expression is Identifier && expression.element is EnumElement) {
      return true;
    }
    final type = expression.staticType;
    return type is InterfaceType && type.element is EnumElement;
  }
}

/// Flags two or more separate `case`s in the same switch expression whose
/// bodies are identical, when they could instead be combined into one case
/// with `||` pattern alternation. Cross-package paradigm: "group identical
/// right-hand sides with || enum alternation; especially uniform-exit
/// events" — repeated identical bodies are exactly the shape that rule
/// forbids, and nothing previously enforced it.
///
/// Guarded cases (`pattern when condition => body`) are excluded even when
/// their body text matches another case — combining them would silently
/// drop the distinct guard condition, changing behavior, not just style.
class UngroupedIdenticalSwitchCases extends DartLintRule {
  UngroupedIdenticalSwitchCases() : super(code: _code);

  static const _code = LintCode(
    name: 'ungrouped_identical_switch_cases',
    problemMessage:
        'Two or more cases in this switch return the same value. Combine '
        'them with || pattern alternation instead of repeating the body.',
    correctionMessage:
        'e.g. `patternA || patternB || patternC => sameValue` instead of '
        'one case per pattern each repeating `=> sameValue`.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addSwitchExpression((node) {
      final byBody = <String, List<SwitchExpressionCase>>{};
      for (final switchCase in node.cases) {
        if (switchCase.guardedPattern.whenClause != null) continue;
        final key = switchCase.expression.toSource();
        byBody.putIfAbsent(key, () => []).add(switchCase);
      }
      for (final group in byBody.values) {
        if (group.length < 2) continue;
        for (final switchCase in group) {
          reporter.atNode(switchCase, _code);
        }
      }
    });
  }
}

/// Flags `confirmFn: (_) => true` or `askFn: (_) => true` passed to a
/// function that also accepts a `promptFn` parameter, when the call doesn't
/// supply `promptFn`. An unconditional `=> true` always proceeds past the
/// confirm/ask gate; an absent `promptFn` means that path falls through to
/// the function's own real interactive prompt default. Confirmed real:
/// exactly this shape (a test's `confirmFn`/`askFn` answering every
/// question `true`, no `promptFn` given) made a real `mutation_test` run
/// hang indefinitely — the mutated subprocess's stdin pipe was open but
/// never written to, so the default prompt's blocking read never returned.
/// A deterministic `(_) => false`, or any closure that isn't an
/// unconditional `true`, is unaffected — this only catches the one shape
/// that's provably always unsafe without a `promptFn` fallback.
class UnconditionalConfirmRequiresPromptFn extends DartLintRule {
  UnconditionalConfirmRequiresPromptFn() : super(code: _code);

  static const _code = LintCode(
    name: 'unconditional_confirm_requires_prompt_fn',
    problemMessage:
        'confirmFn/askFn unconditionally returns true with no promptFn '
        'supplied — this falls through to the real interactive prompt '
        'default, which can block indefinitely outside a real terminal.',
    correctionMessage:
        'Pass a promptFn (even one that just returns null) alongside an '
        'unconditional confirmFn/askFn, or make the closure conditional/'
        'false instead of always true.',
  );

  static const _targetParamNames = {'confirmFn', 'askFn'};
  static const _fallbackParamName = 'promptFn';

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      final element = node.methodName.element;
      if (element is! ExecutableElement) return;
      final hasPromptFnParam =
          element.formalParameters.any((p) => p.name == _fallbackParamName);
      if (!hasPromptFnParam) return;

      final suppliedPromptFn = node.argumentList.arguments
          .whereType<NamedExpression>()
          .any((a) => a.name.label.name == _fallbackParamName);
      if (suppliedPromptFn) return;

      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression) continue;
        if (!_targetParamNames.contains(arg.name.label.name)) continue;
        if (_isUnconditionalTrue(arg.expression)) {
          reporter.atNode(arg, _code);
        }
      }
    });
  }

  /// True for `(_) => true` (expression body) or `(_) { return true; }`
  /// (single-statement block body) — the two syntactic shapes of "always
  /// returns the literal `true`, unconditionally."
  static bool _isUnconditionalTrue(Expression expr) {
    if (expr is! FunctionExpression) return false;
    final body = expr.body;
    if (body is ExpressionFunctionBody) {
      return _isTrueLiteral(body.expression);
    }
    if (body is BlockFunctionBody) {
      final statements = body.block.statements;
      if (statements.length != 1) return false;
      final stmt = statements.first;
      return stmt is ReturnStatement && _isTrueLiteral(stmt.expression);
    }
    return false;
  }

  static bool _isTrueLiteral(Expression? expr) =>
      expr is BooleanLiteral && expr.value == true;
}
