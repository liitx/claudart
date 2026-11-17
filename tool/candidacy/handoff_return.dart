// handoff_return.dart — what an agent hands back for a candidate, as types.
//
// The handoff template used to describe each returned field in prose. Here each
// field is a variant that says what value it carries (`ReturnValueKind`) and what
// the code does with it (`ReturnRoute`), so a returned entry is routed by the
// compiler's exhaustive switches and a new field or route cannot be added without
// deciding both. The fields are dartrix's `LedgerField`, one for one (a test).

import 'package:dartrix/dartrix.dart';

import 'evidence_audit.dart' show citationSeparator;

/// The shape a value has once the entry is read from JSON.
enum ReturnJsonShape { text, list, map, number }

/// What kind of value a returned field carries.
enum ReturnValueKind {
  /// A non-empty name that identifies something.
  identifier(shape: ReturnJsonShape.text),

  /// One of the `CandidateStatus` names.
  candidateStatus(shape: ReturnJsonShape.text),

  /// `path :: text`.
  citation(shape: ReturnJsonShape.text),

  /// A list of citations.
  citationList(shape: ReturnJsonShape.list),

  /// A non-empty sentence written for a reader.
  narrative(shape: ReturnJsonShape.text),

  /// A list of variant names.
  variantList(shape: ReturnJsonShape.list),

  /// One `ProofAuditOutcome` name for each `ProofAuditCheck` name that is given.
  auditOutcomes(shape: ReturnJsonShape.map),

  /// A number from 0 to 1.
  unitInterval(shape: ReturnJsonShape.number),

  /// Named measurements, each from 0 to 1.
  factorSet(shape: ReturnJsonShape.map);

  const ReturnValueKind({required this.shape});

  /// The JSON shape a value of this kind has.
  final ReturnJsonShape shape;
}

/// What the code does with a returned field.
enum ReturnRoute {
  /// Keys the entry to its candidate.
  ledgerKey,

  /// Moves the candidate along the status machine (`legalNext`).
  statusMachine,

  /// Scopes the claim to a spec section.
  specGate,

  /// Names the mocks the audit judged.
  mockGate,

  /// Is checked to exist (the evidence audit).
  evidenceGate,

  /// Is recorded for a reader and routed nowhere.
  narrativeRecord,

  /// Decides whether a proof is full or partial.
  coverageGate,

  /// Refuses promotion when a check did not pass.
  auditGate,

  /// Is recorded as where the claim stops holding.
  boundaryRecord,

  /// Is what an axiom's confidence must reach.
  promotionGate,

  /// Feeds the confidence grade.
  gradingInput,
}

/// A field of the entry an agent returns, one for each dartrix `LedgerField`.
enum HandoffReturnField {
  candidateId(
    ledgerField: LedgerField.candidateId,
    kind: ReturnValueKind.identifier,
    route: ReturnRoute.ledgerKey,
    meaning: 'which postulate',
  ),
  status(
    ledgerField: LedgerField.status,
    kind: ReturnValueKind.candidateStatus,
    route: ReturnRoute.statusMachine,
    meaning: 'the status the candidate moves to; a partial proof is `bounded`',
  ),
  specReference(
    ledgerField: LedgerField.specReference,
    kind: ReturnValueKind.citation,
    route: ReturnRoute.specGate,
    meaning: 'the spec section it is scoped to',
  ),
  mockDatasetVersion(
    ledgerField: LedgerField.mockDatasetVersion,
    kind: ReturnValueKind.identifier,
    route: ReturnRoute.mockGate,
    meaning: 'the mocks the proof ran on',
  ),
  evidence(
    ledgerField: LedgerField.evidence,
    kind: ReturnValueKind.citationList,
    route: ReturnRoute.evidenceGate,
    meaning: 'citations that exist',
  ),
  justification(
    ledgerField: LedgerField.justification,
    kind: ReturnValueKind.narrative,
    route: ReturnRoute.narrativeRecord,
    meaning: 'what was run and found, plainly',
  ),
  variantsInSpec(
    ledgerField: LedgerField.variantsInSpec,
    kind: ReturnValueKind.variantList,
    route: ReturnRoute.coverageGate,
    meaning: 'every variant the spec names',
  ),
  variantsCovered(
    ledgerField: LedgerField.variantsCovered,
    kind: ReturnValueKind.variantList,
    route: ReturnRoute.coverageGate,
    meaning: 'the variants the tests cover',
  ),
  audit(
    ledgerField: LedgerField.audit,
    kind: ReturnValueKind.auditOutcomes,
    route: ReturnRoute.auditGate,
    meaning: 'the Phase 0 outcome of each check; no promotion on mocks that did '
        'not pass',
  ),
  boundary(
    ledgerField: LedgerField.boundary,
    kind: ReturnValueKind.narrative,
    route: ReturnRoute.boundaryRecord,
    meaning: 'where it stops holding',
  ),
  threshold(
    ledgerField: LedgerField.threshold,
    kind: ReturnValueKind.unitInterval,
    route: ReturnRoute.promotionGate,
    meaning: 'for an axiom: the confidence it must reach, justified',
  ),
  factors(
    ledgerField: LedgerField.factors,
    kind: ReturnValueKind.factorSet,
    route: ReturnRoute.gradingInput,
    meaning: 'measured boundary, topology reach and impact',
  );

  const HandoffReturnField({
    required this.ledgerField,
    required this.kind,
    required this.route,
    required this.meaning,
  });

  /// The dartrix field this one types.
  final LedgerField ledgerField;

  /// What value it carries.
  final ReturnValueKind kind;

  /// What the code does with it.
  final ReturnRoute route;

  /// What it means to the agent returning it.
  final String meaning;

  /// The key it is written under.
  String get key => ledgerField.name;

  /// Whether a returned entry must carry it.
  bool get isRequired => ledgerField.isRequired;
}

/// Why a returned field was refused.
enum ReturnFaultReason {
  /// A required field is absent.
  missing,

  /// The value is not of the shape its kind has.
  wrongShape,

  /// The value has the right shape but is not a value of its kind.
  notOfKind,
}

/// A returned field that was refused, and why.
typedef ReturnFault = ({HandoffReturnField field, ReturnFaultReason reason});

bool _hasShape(Object value, ReturnJsonShape shape) => switch (shape) {
      ReturnJsonShape.text => value is String,
      ReturnJsonShape.list => value is List,
      ReturnJsonShape.map => value is Map,
      ReturnJsonShape.number => value is num,
    };

bool _isCitation(Object? value) =>
    value is String && value.contains(citationSeparator);

bool _isUnit(Object? value) => value is num && value >= 0 && value <= 1;

/// Whether [value], already of the shape of [kind], is a value of that kind.
bool _isOfKind(ReturnValueKind kind, Object value) => switch (kind) {
      ReturnValueKind.identifier ||
      ReturnValueKind.narrative =>
        (value as String).trim().isNotEmpty,
      ReturnValueKind.candidateStatus =>
        CandidateStatus.values.any((s) => s.name == value),
      ReturnValueKind.citation => _isCitation(value),
      ReturnValueKind.citationList => (value as List).every(_isCitation),
      ReturnValueKind.variantList => (value as List).every((v) => v is String),
      ReturnValueKind.auditOutcomes => (value as Map).entries.every((e) =>
          ProofAuditCheck.values.any((c) => c.name == e.key) &&
          ProofAuditOutcome.values.any((o) => o.name == e.value)),
      ReturnValueKind.unitInterval => _isUnit(value),
      ReturnValueKind.factorSet => (value as Map).values.every(_isUnit),
    };

/// Every field of [returned] that is missing, of the wrong shape, or not a
/// value of its kind, in field order. Empty when the entry can be routed.
List<ReturnFault> checkReturn(Map<String, Object?> returned) {
  final faults = <ReturnFault>[];
  for (final field in HandoffReturnField.values) {
    final value = returned[field.key];
    if (value == null) {
      if (field.isRequired) {
        faults.add((field: field, reason: ReturnFaultReason.missing));
      }
      continue;
    }
    if (!_hasShape(value, field.kind.shape)) {
      faults.add((field: field, reason: ReturnFaultReason.wrongShape));
    } else if (!_isOfKind(field.kind, value)) {
      faults.add((field: field, reason: ReturnFaultReason.notOfKind));
    }
  }
  return faults;
}

/// The table the handoff template carries: one row for each field.
String renderReturnTable() {
  final buffer = StringBuffer()
    ..writeln('| Field | Required | Value | Routed to | Meaning |')
    ..writeln('|---|---|---|---|---|');
  for (final field in HandoffReturnField.values) {
    buffer.writeln('| `${field.key}` | ${field.isRequired ? 'yes' : 'no'} | '
        '`${field.kind.name}` | `${field.route.name}` | ${field.meaning} |');
  }
  return buffer.toString();
}
