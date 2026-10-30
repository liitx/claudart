import 'package:claudart/commands/command_seams.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

void main() {
  group('$CommandSeams', () {
    test('a command given none of them has none replaced', () {
      const seams = CommandSeams();
      expect(seams.io, isNull);
      expect(seams.projectRootOverride, isNull);
      expect(seams.exitFn, isNull);
      expect(seams.confirmFn, isNull);
      expect(seams.askFn, isNull);
      expect(seams.pickFn, isNull);
    });

    test('forProjectRoot changes the root and keeps the rest', () {
      final io = MemoryFileIO();
      Never exitFn(int code) => throw StateError('$code');
      bool confirmFn(String question) => true;
      bool? askFn(String question) => null;
      int pickFn(List<String> items) => 0;
      final seams = CommandSeams(
        io: io,
        projectRootOverride: '/one',
        exitFn: exitFn,
        confirmFn: confirmFn,
        askFn: askFn,
        pickFn: pickFn,
      ).forProjectRoot('/two');
      expect(seams.projectRootOverride, '/two');
      expect(seams.io, same(io));
      expect(seams.exitFn, same(exitFn));
      expect(seams.confirmFn, same(confirmFn));
      expect(seams.askFn, same(askFn));
      expect(seams.pickFn, same(pickFn));
    });
  });
}
