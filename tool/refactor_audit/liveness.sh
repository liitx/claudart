#!/bin/zsh
# liveness.sh — do the tools see what they claim to see?
#
# Seeds one known defect per shape in a SCRATCH copy of this repo, runs the
# tool that claims to catch it, and prints one line per seed:
#   <id> | <tool> | <defect> | CAUGHT or MISSED
# A MISSED line is a finding. The working tree is never touched.
#
#   make liveness
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd)
S=$(mktemp -d)
trap 'rm -rf "$S" /tmp/liveness_bak.$$.*' EXIT
rsync -a --exclude .git --exclude coverage --exclude build "$SRC"/ "$S"/
cd "$S"
dart pub get --offline >/dev/null 2>&1

rec() { echo "$1 | $2 | $3 | $4"; }
chk() { # id tool defect needle haystack
  if echo "$5" | grep -q "$4"; then rec "$1" "$2" "$3" CAUGHT; else rec "$1" "$2" "$3" MISSED; fi
}
guard() { # id test-file defect
  if dart test "$2" < /dev/null >/dev/null 2>&1; then rec "$1" "$2" "$3" MISSED; else rec "$1" "$2" "$3" CAUGHT; fi
}

# ---- analyzer and custom_lint: all seeds in separate files, attributed by file
cat > lib/zz_seed_a1.dart <<'D'
int a1() => 'text';
D
cat > lib/zz_seed_a2.dart <<'D'
import 'dart:io';

int a2() => 1;
D
cat > lib/zz_seed_l1.dart <<'D'
void sink(String s) {}

void l1(String x) {
  switch (x) {
    case 'alpha':
      sink('1');
      break;
    case 'beta':
      sink('2');
      break;
  }
}
D
cat > lib/zz_seed_l3.dart <<'D'
enum E3 { a, b, c }

String l3(E3 e) => switch (e) {
      E3.a => 'x',
      E3.b => 'x',
      E3.c => 'y',
    };
D
cat > lib/zz_seed_l4.dart <<'D'
void l4Callee({bool Function(String)? confirmFn, String? Function()? promptFn}) {}

void l4() => l4Callee(confirmFn: (_) => true);
D
cat > lib/zz_seed_l5.dart <<'D'
enum E5 { a, b }

int l5(E5 e) {
  switch (e) {
    case E5.a:
      return 1;
  }
  return 0;
}
D
cat > lib/zz_seed_l6.dart <<'D'
enum E6 { a, b }

int l6(E6 e) => switch (e) {
      E6.a => 1,
      _ => 2,
    };
D
cat > lib/zz_seed_l7.dart <<'D'
bool l7(String s) => s == 'transitions.jsonl' || s == 'errors.jsonl';
D
cat > test/zz_seed_l2_test.dart <<'D'
import 'package:test/test.dart';

enum E2 { a, b }

void main() {
  test('loops inside one test', () {
    for (final v in E2.values) {
      expect(v, isNotNull);
    }
  });
}
D
an=$(dart analyze 2>&1)
cl=$(dart run custom_lint 2>&1)
chk A1 analyzer "type error" zz_seed_a1 "$an"
chk A2 analyzer "unused import" zz_seed_a2 "$an"
chk L1 custom_lint:bare_string_for_enum "string switch with actions" zz_seed_l1 "$cl"
chk L2 custom_lint:enum_values_loop_in_single_test "enum values loop in one test" zz_seed_l2 "$cl"
chk L3 custom_lint:ungrouped_identical_switch_cases "identical arms" zz_seed_l3 "$cl"
chk L4 custom_lint:unconditional_confirm_requires_prompt_fn "confirmFn true, no promptFn" zz_seed_l4 "$cl"
chk L5 analyzer:missing_enum_constant_in_switch "enum switch missing a variant" zz_seed_l5 "$an"
chk L6 any "wildcard arm on an enum switch" zz_seed_l6 "$an$cl"
chk L7 any "bare string compared with ==" zz_seed_l7 "$an$cl"
rm -f lib/zz_seed_* test/zz_seed_*

# ---- duplicate-literal advisory
cat > lib/zz_seed_d1.dart <<'D'
String d1a() => 'some repeated literal';
String d1b() => 'some repeated literal';
D
o=$(dart run tool/check_duplicate_literals.dart lib/zz_seed_d1.dart 2>&1)
chk W1 check_duplicate_literals "same-file duplicate literal (advisory, exits 0)" "repeated literal" "$o"
rm -f lib/zz_seed_d1.dart

# ---- topology guards: seed, run the guard, revert
echo "const t1 = 'transitions.jsonl';" > lib/zz_seed_t1.dart
guard T1 test/topology/literal_ownership_topology_test.dart "log file name literal in lib"
rm -f lib/zz_seed_t1.dart
cat > test/zz_seed_t2_test.dart <<'D'
import 'package:test/test.dart';

void main() {
  test('SessionLogger writes a line', () {});
}
D
guard T2 test/topology/literal_ownership_topology_test.dart "test title naming a type as text"
rm -f test/zz_seed_t2_test.dart
echo "const t6 = 'new_log_file.jsonl';" > lib/zz_seed_t6.dart
guard T6 test/topology/literal_ownership_topology_test.dart "log name literal not yet in LogFile"
rm -f lib/zz_seed_t6.dart
echo "const t4 = 'claude-sonnet-5-5';" > lib/zz_seed_t4.dart
guard T4 test/topology/model_metadata_topology_test.dart "model id literal in lib"
rm -f lib/zz_seed_t4.dart
for pair in "T3 handoff_topology_test.dart handoff_status.md" "T5 environment_topology_test.dart environments.md" "T7 call_census_test.dart call_census.md"; do
  set -- ${=pair}
  cp docs/topology/$3 /tmp/liveness_bak.$$.$3
  echo drift >> docs/topology/$3
  guard $1 test/topology/$2 "generated doc drift ($3)"
  cp /tmp/liveness_bak.$$.$3 docs/topology/$3
done

# ---- random order: a test that passes only in declared order
cat > test/zz_seed_r1_test.dart <<'D'
import 'package:test/test.dart';

var ran = false;

void main() {
  test('first sets', () => ran = true);
  test('second needs first', () => expect(ran, isTrue));
}
D
caught=NO
for seed in 1 2 3 4 5 6 7 8; do
  dart test test/zz_seed_r1_test.dart --test-randomize-ordering-seed=$seed >/dev/null 2>&1 || caught=YES
done
[ $caught = YES ] && rec R1 random-order "order-dependent test" CAUGHT || rec R1 random-order "order-dependent test" MISSED
