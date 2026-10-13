// variant_topology.dart — read a getter across every variant of an enum.
//
// Two uses, one function:
//   - expected values for CONSUMER tests come from the variant's own getter
//     (`topologyOf(HandoffStatus.values, (s) => s.canStartDebug)`), not from a
//     hand-typed set the test author keeps in sync;
//   - the same data renders as the variant x getter table (the topology), so
//     docs and diagrams can be generated from the code instead of written.
//
// Caution built into the design: a consumer test derived from a getter proves
// the CONSUMER follows the getter, not that the getter is right. The getter
// itself still needs one independent literal table (the contract) in the
// enum's own test.

/// The variant's own answer for [getter], in declaration order.
Map<V, T> topologyOf<V extends Enum, T>(Iterable<V> variants, T Function(V) getter) =>
    {for (final variant in variants) variant: getter(variant)};

/// Markdown table: one row per variant, one column per named getter.
/// Pass the enum type explicitly (`renderTopology<HandoffStatus>(...)`): Dart
/// cannot infer the closure parameter inside the getters map literal.
String renderTopology<V extends Enum>(
  Iterable<V> variants,
  Map<String, Object? Function(V)> getters,
) {
  final header = '| variant | ${getters.keys.join(' | ')} |';
  final divider = '|${'---|' * (getters.length + 1)}';
  final rows = [
    for (final variant in variants)
      '| ${variant.name} | ${getters.values.map((read) => '${read(variant)}').join(' | ')} |',
  ];
  return [header, divider, ...rows].join('\n');
}
