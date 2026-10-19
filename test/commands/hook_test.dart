import 'dart:convert';

import 'package:claudart/commands/hook.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/session/session_state.dart';
import 'package:claudart/templates/handoff_template.dart' show blankHandoff;
import 'package:claudart/workspace/workspace_config.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

const _root = '/projects/my-app';
const _workspace = '/workspaces/my-app';
const _dartFile = '$_root/lib/a.dart';
const _exploring = HandoffStatus.suggestInvestigating;

// Independent literals: the statuses a session may implement from.
const _implementable = {
  HandoffStatus.readyForDebug,
  HandoffStatus.debugInProgress,
};

HookOutcome _expectedOutcome({
  required bool isDartSource,
  required HandoffStatus status,
  required bool strict,
}) {
  if (!isDartSource || _implementable.contains(status)) {
    return HookOutcome.silent;
  }
  return strict ? HookOutcome.deny : HookOutcome.advise;
}

String _stdin(String filePath) => jsonEncode({
      'tool_name': 'Edit',
      'tool_input': {'file_path': filePath},
    });

MemoryFileIO _ioWithSession({
  required HandoffStatus status,
  bool strict = false,
  bool withConfig = true,
}) {
  final io = MemoryFileIO();
  Registry.empty()
      .add(const RegistryEntry(
        name: 'my-app',
        projectRoot: _root,
        workspacePath: _workspace,
        createdAt: '2026-01-01',
        lastSession: '2026-01-01',
      ))
      .save(io: io);
  io.write(
    handoffPathFor(_workspace),
    _liveHandoffAt(status),
  );
  if (withConfig) {
    WorkspaceConfig(
      owner: WorkspaceOwner(
        name: 'n',
        email: 'e@x.com',
        handle: 'h',
        strict: strict,
      ),
      project: const WorkspaceProject(
        name: 'my-app',
        stack: [StackType.dart],
        role: WorkspaceRole.maintainer,
      ),
      session: const WorkspaceSession(
        agents: [],
        knowledge: [],
        proofNotation: ProofNotation.generic,
        sensitivityMode: false,
      ),
    ).write(_workspace, io: io);
  }
  return io;
}

String _liveHandoffAt(HandoffStatus status) {
  // A live session: a real bug, so effectiveStatus is the written status.
  return blankHandoff
      .replaceFirst('suggest-investigating', status.value)
      .replaceFirst(RegExp(r'## Bug\n+_[^\n]*'), '## Bug\n\nA real bug.');
}

String? _hookOutput(String stdin, MemoryFileIO io) {
  final out = StringBuffer();
  runHook(stdinText: stdin, io: io, out: out);
  final text = out.toString().trim();
  return text.isEmpty ? null : text;
}

void main() {
  group('decidePreEdit', () {
    for (final status in HandoffStatus.values) {
      for (final strict in [false, true]) {
        for (final isDartSource in [false, true]) {
          final expected = _expectedOutcome(
            isDartSource: isDartSource,
            status: status,
            strict: strict,
          );
          test(
              '${status.name}, strict=$strict, dart=$isDartSource '
              '-> ${expected.name}', () {
            expect(
              decidePreEdit(
                isDartSource: isDartSource,
                status: status,
                strict: strict,
              ),
              expected,
            );
          });
        }
      }
    }
  });

  group('HookOutcome.messageFor', () {
    test('silent says nothing', () {
      expect(
        HookOutcome.silent.messageFor(
          projectName: 'p',
          status: HandoffStatus.noHandoff,
        ),
        isNull,
      );
    });

    // The wording is the contract Claude reads: pinned in full.
    test('advise is exactly this text', () {
      expect(
        HookOutcome.advise.messageFor(
          projectName: 'my-app',
          status: HandoffStatus.suggestInvestigating,
        ),
        'claudart session for my-app is suggest-investigating, so this '
        'change is not going through the session. Implement code through '
        '/debug (it needs ready-for-debug or debug-in-progress; run /suggest '
        'then /save first) and checkpoint with /save. Other linked sessions: '
        'claudart workspaces.',
      );
    });

    test('deny is exactly this text', () {
      expect(
        HookOutcome.deny.messageFor(
          projectName: 'my-app',
          status: HandoffStatus.noHandoff,
        ),
        'Blocked: claudart session for my-app is no-handoff and this '
        'workspace is strict. Run /suggest then /save to reach '
        'ready-for-debug, then implement through /debug.',
      );
    });

    test('the hook subcommand is pre-edit', () {
      expect(HookWire.preEditSubcommand, 'pre-edit');
    });

    test('advise names the project, the status and the way in', () {
      final message = HookOutcome.advise.messageFor(
        projectName: 'my-app',
        status: _exploring,
      )!;
      expect(message, contains('my-app'));
      expect(message, contains('suggest-investigating'));
      expect(message, contains('/debug'));
      expect(message, contains('claudart workspaces'));
    });

    test('deny says it is blocked and names the way in', () {
      final message = HookOutcome.deny.messageFor(
        projectName: 'my-app',
        status: HandoffStatus.noHandoff,
      )!;
      expect(message, startsWith('Blocked:'));
      expect(message, contains('no-handoff'));
      expect(message, contains('/suggest'));
    });
  });

  group('preEditResponseJson', () {
    test('silent prints nothing', () {
      expect(preEditResponseJson(HookOutcome.silent, null), isNull);
    });

    test('advise adds context and makes no permission decision', () {
      final json = jsonDecode(
        preEditResponseJson(HookOutcome.advise, 'tell claude')!,
      ) as Map<String, dynamic>;
      expect(json, {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'additionalContext': 'tell claude',
        },
      });
    });

    test('deny carries the decision and the reason', () {
      final json = jsonDecode(
        preEditResponseJson(HookOutcome.deny, 'because')!,
      ) as Map<String, dynamic>;
      expect(json, {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'permissionDecision': 'deny',
          'permissionDecisionReason': 'because',
        },
      });
    });

    test('a missing message prints nothing even for advise', () {
      expect(preEditResponseJson(HookOutcome.advise, null), isNull);
    });
  });

  group('editedFilePath', () {
    test('reads tool_input.file_path', () {
      expect(editedFilePath(_stdin('/a/b.dart')), '/a/b.dart');
    });

    final unusable = <String, String>{
      'not json': 'nope',
      'a list': '[1]',
      'no tool_input': '{"tool_name":"Edit"}',
      'tool_input not an object': '{"tool_input":"x"}',
      'no file_path': '{"tool_input":{}}',
      'file_path not a string': '{"tool_input":{"file_path":3}}',
      'empty file_path': '{"tool_input":{"file_path":""}}',
    };
    unusable.forEach((name, input) {
      test('$name gives null', () {
        expect(editedFilePath(input), isNull);
      });
    });
  });

  group('entryContaining', () {
    final registry = Registry.empty()
        .add(const RegistryEntry(
          name: 'outer',
          projectRoot: '/p/outer',
          workspacePath: '/w/outer',
          createdAt: 'x',
          lastSession: 'x',
        ))
        .add(const RegistryEntry(
          name: 'inner',
          projectRoot: '/p/outer/inner',
          workspacePath: '/w/inner',
          createdAt: 'x',
          lastSession: 'x',
        ));

    test('a file in the project resolves to it', () {
      expect(entryContaining(registry, '/p/outer/lib/a.dart')?.name, 'outer');
    });

    test('a nested checkout resolves to the inner one', () {
      expect(
        entryContaining(registry, '/p/outer/inner/lib/a.dart')?.name,
        'inner',
      );
    });

    test('a sibling with the same prefix does not match', () {
      expect(entryContaining(registry, '/p/outer-other/lib/a.dart'), isNull);
    });

    test('a path outside every project is null', () {
      expect(entryContaining(registry, '/elsewhere/a.dart'), isNull);
    });
  });

  group('runHook', () {
    test('a Dart edit outside a ready session advises, with the reason', () {
      final out = _hookOutput(
        _stdin(_dartFile),
        _ioWithSession(status: _exploring),
      );
      final json = jsonDecode(out!) as Map<String, dynamic>;
      final inner = json['hookSpecificOutput'] as Map<String, dynamic>;
      expect(inner['additionalContext'], contains('suggest-investigating'));
      expect(inner.containsKey('permissionDecision'), isFalse);
    });

    test('in a strict workspace the same edit is denied', () {
      final out = _hookOutput(
        _stdin(_dartFile),
        _ioWithSession(status: _exploring, strict: true),
      );
      final inner = (jsonDecode(out!) as Map<String, dynamic>)
          ['hookSpecificOutput'] as Map<String, dynamic>;
      expect(inner['permissionDecision'], 'deny');
    });

    for (final status in _implementable) {
      test('${status.name} lets a Dart edit through silently, even strict', () {
        final io = _ioWithSession(status: status, strict: true);
        expect(_hookOutput(_stdin(_dartFile), io), isNull);
      });
    }

    test('a blank handoff counts as no session: advises', () {
      final io = _ioWithSession(status: HandoffStatus.readyForDebug);
      io.write(handoffPathFor(_workspace), blankHandoff);
      expect(_hookOutput(_stdin(_dartFile), io), contains('no-handoff'));
    });

    test('a non-Dart file is never advised about', () {
      expect(
        _hookOutput(
          _stdin('$_root/README.md'),
          _ioWithSession(status: _exploring, strict: true),
        ),
        isNull,
      );
    });

    test('a file in no linked project is silent', () {
      expect(
        _hookOutput(
          _stdin('/elsewhere/a.dart'),
          _ioWithSession(status: _exploring, strict: true),
        ),
        isNull,
      );
    });

    test('unusable stdin is silent and does not throw', () {
      expect(
        _hookOutput('garbage', _ioWithSession(status: _exploring)),
        isNull,
      );
    });

    test('a missing workspace.json means not strict: advises, not denies', () {
      final out = _hookOutput(
        _stdin(_dartFile),
        _ioWithSession(status: _exploring, withConfig: false),
      );
      expect(out, contains('additionalContext'));
      expect(out, isNot(contains('permissionDecision')));
    });

    test('a failing read never throws', () {
      final io = MockFileIO();
      expect(
        () => runHook(stdinText: _stdin(_dartFile), io: io),
        returnsNormally,
      );
    });
  });
}
