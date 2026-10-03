import 'dart:io';

import 'package:claudart/ui/terminal_support.dart';
import 'package:test/test.dart';

void main() {
  group('canUseRawTerminal', () {
    test('false when stdin reports no terminal (probe is never called)', () {
      var probed = false;
      final ok = canUseRawTerminal(
        hasTerminal: () => false,
        echoModeProbe: () => probed = true,
      );
      expect(ok, isFalse);
      expect(probed, isFalse);
    });

    test('true when stdin reports a terminal and the probe succeeds', () {
      expect(canUseRawTerminal(hasTerminal: () => true, echoModeProbe: () {}), isTrue);
    });

    test('false when stdin claims a terminal but raw mode is unusable (/dev/null on macOS)', () {
      final ok = canUseRawTerminal(
        hasTerminal: () => true,
        echoModeProbe: () => throw const StdinException('Error getting terminal echo mode'),
      );
      expect(ok, isFalse);
    });

    test('other failures are not swallowed', () {
      expect(
        () => canUseRawTerminal(hasTerminal: () => true, echoModeProbe: () => throw StateError('boom')),
        throwsStateError,
      );
    });
  });
}
