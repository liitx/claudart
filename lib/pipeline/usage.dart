// usage.dart — token-usage value type for pipeline steps
//
// Promoted from private `_Usage` in suggest.dart to a public, reusable type.
// Every pipeline step returns a Usage; the executor accumulates them.
//
// Invariants:
//   ∀ u ∈ Usage: u.input >= 0 ∧ u.output >= 0 ∧ u.cacheRead >= 0 ∧ u.cost >= 0
//   (u1 + u2).input == u1.input + u2.input  (and so on for all fields)

class Usage {
  final int input;
  final int output;
  final int cacheRead;
  final double cost;

  const Usage({
    this.input    = 0,
    this.output   = 0,
    this.cacheRead = 0,
    this.cost     = 0,
  });

  Usage operator +(Usage o) => Usage(
    input:     input     + o.input,
    output:    output    + o.output,
    cacheRead: cacheRead + o.cacheRead,
    cost:      cost      + o.cost,
  );

  /// Human-readable summary for terminal display.
  /// Example: 'in 3.2k · cached 1.1k · out 412 · $0.0008'
  String format() {
    final buf = StringBuffer('in ${_fmtN(input)}');
    if (cacheRead > 0) buf.write(' · cached ${_fmtN(cacheRead)}');
    buf.write(' · out ${_fmtN(output)}');
    if (cost > 0) buf.write(' · \$${cost.toStringAsFixed(4)}');
    return buf.toString();
  }

  @override
  String toString() => 'Usage(in:$input, out:$output, cached:$cacheRead, \$$cost)';
}

String _fmtN(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
