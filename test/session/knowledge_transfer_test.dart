// knowledge_transfer_test.dart — whether a handoff carries a knowledge
// transfer: a root cause and a scope, both with real content.

import 'package:claudart/session/handoff_placeholder.dart';
import 'package:claudart/session/handoff_section.dart';
import 'package:claudart/session/knowledge_transfer.dart';
import 'package:test/test.dart';

const _real = HandoffSection('a real section');
final _blank = HandoffSection(HandoffPlaceholder.notYetDetermined.text);

void main() {
  group('$KnowledgeTransfer.of', () {
    // Independent literals: (root cause real?, scope real?) -> converged?
    const table = <(bool, bool), KnowledgeTransfer>{
      (true, true): KnowledgeTransfer.converged,
      (true, false): KnowledgeTransfer.unconverged,
      (false, true): KnowledgeTransfer.unconverged,
      (false, false): KnowledgeTransfer.unconverged,
    };

    table.forEach((realness, expected) {
      final (rootCauseReal, scopeReal) = realness;
      test(
        'root cause ${rootCauseReal ? 'real' : 'blank'}, '
        'scope ${scopeReal ? 'real' : 'blank'}: ${expected.name}',
        () {
          expect(
            KnowledgeTransfer.of(
              rootCause: rootCauseReal ? _real : _blank,
              scope: scopeReal ? _real : _blank,
            ),
            expected,
          );
        },
      );
    });

    test('the table covers every combination', () {
      expect(table.length, 4);
    });
  });
}
