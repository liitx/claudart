// dartrix_pin_test.dart — claudart says which dartrix it was proven against.
//
// A pin that is missing or a branch name lets pub resolve a different dartrix
// than the one the suite ran on, so claudart would not know when dartrix moved.
// dartrix reports whether a pin is behind (its dependents report); this only
// keeps the pin a commit.

import 'dart:io';

import 'package:dartrix/dartrix.dart';
import 'package:test/test.dart';

void main() {
  test('dartrix is pinned to a full commit, not floating and not a branch', () {
    final ref = pinnedRefIn(File('pubspec.yaml').readAsStringSync(), 'dartrix');
    expect(ref, isNotNull);
    expect(ref, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(pinStateOf(pinnedRef: ref, headRef: 'x'), isNot(PinState.floating));
  });
}
