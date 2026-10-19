import 'dart:convert';

import 'package:claudart/templates/claude_settings_template.dart';
import 'package:test/test.dart';

const _hookCommand = 'claudart hook pre-edit';
const _userSettings = '{"permissions":{"allow":["Bash(ls)"]},'
    '"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":'
    '[{"type":"command","command":"echo hi"}]}]}}';

/// What link writes for a project that is not sensitive.
String _withTrace(String existing) =>
    mergeClaudeSettings(existing, debugTrace: true);

Map<String, dynamic> _merged(String existing, {bool debugTrace = true}) =>
    jsonDecode(mergeClaudeSettings(existing, debugTrace: debugTrace))
        as Map<String, dynamic>;

List<dynamic> _preToolUse(Map<String, dynamic> settings) =>
    (settings['hooks'] as Map<String, dynamic>)['PreToolUse'] as List<dynamic>;

void main() {
  group('mergeClaudeSettings', () {
    test('from nothing, writes the hook entry and the debug env var', () {
      expect(_merged(''), {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Edit|Write|MultiEdit',
              'hooks': [
                {'type': 'command', 'command': _hookCommand},
              ],
            },
          ],
        },
        'env': {'CLAUDART_DEBUG': '1'},
      });
    });

    test('keeps every other key and every other hook', () {
      final merged = _merged(_userSettings);
      expect(merged['permissions'], {
        'allow': ['Bash(ls)'],
      });
      expect((merged['hooks'] as Map)['PostToolUse'], isNotEmpty);
      expect(_preToolUse(merged).length, 1);
    });

    test('adds beside the user\'s own PreToolUse hooks', () {
      final merged = _merged(
        '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":'
        '[{"type":"command","command":"mine"}]}]}}',
      );
      expect(_preToolUse(merged).length, 2);
    });

    test('updates its own entry in place instead of adding another', () {
      final first = _withTrace('');
      final stale = first.replaceFirst('Edit|Write|MultiEdit', 'Edit');
      final merged = _merged(stale);
      expect(_preToolUse(merged).length, 1);
      expect(
        (_preToolUse(merged).single as Map)['matcher'],
        'Edit|Write|MultiEdit',
      );
    });

    test('updates its entry in place when a user hook comes before it', () {
      final staleManaged = jsonEncode({
        'matcher': 'Edit',
        'hooks': [
          {'type': 'command', 'command': _hookCommand},
        ],
      });
      final merged = _merged(
        '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":'
        '[{"type":"command","command":"mine"}]},$staleManaged]}}',
      );
      final entries = _preToolUse(merged);
      expect(entries.length, 2);
      expect((entries.first as Map)['matcher'], 'Bash');
      expect((entries.last as Map)['matcher'], 'Edit|Write|MultiEdit');
    });

    test('is idempotent', () {
      final once = _withTrace(_userSettings);
      expect(mergeClaudeSettings(once, debugTrace: true), once);
    });

    test('leaves an env value the user already set', () {
      final merged = _merged('{"env":{"CLAUDART_DEBUG":"0","X":"y"}}');
      expect(merged['env'], {'CLAUDART_DEBUG': '0', 'X': 'y'});
    });

    test('a file that is not a JSON object throws FormatException', () {
      expect(() => _withTrace('[1]'), throwsFormatException);
      expect(() => _withTrace('nope'), throwsFormatException);
    });

    test('ends with a newline', () {
      expect(_withTrace(''), endsWith('}\n'));
    });
  });

  group('claudeSettingsAreFresh', () {
    test('false for an empty file', () {
      expect(claudeSettingsAreFresh('', debugTrace: true), isFalse);
    });

    test('true for what merge writes', () {
      final fromNothing = _withTrace('');
      final fromUser = _withTrace(_userSettings);
      expect(claudeSettingsAreFresh(fromNothing, debugTrace: true), isTrue);
      expect(claudeSettingsAreFresh(fromUser, debugTrace: true), isTrue);
    });

    test('false when the hook entry differs', () {
      final stale =
          _withTrace('').replaceFirst('Edit|Write|MultiEdit', 'Edit');
      expect(claudeSettingsAreFresh(stale, debugTrace: true), isFalse);
    });

    test('false when the env var is missing', () {
      final stale = _withTrace('').replaceFirst('CLAUDART_DEBUG', 'X');
      expect(claudeSettingsAreFresh(stale, debugTrace: true), isFalse);
    });

    test('false when the hook appears twice', () {
      final doubled = jsonEncode({
        'hooks': {
          'PreToolUse': [
            for (var i = 0; i < 2; i++)
              {
                'matcher': 'Edit|Write|MultiEdit',
                'hooks': [
                  {'type': 'command', 'command': _hookCommand},
                ],
              },
          ],
        },
        'env': {'CLAUDART_DEBUG': '1'},
      });
      expect(claudeSettingsAreFresh(doubled, debugTrace: true), isFalse);
    });

    test('false for text that is not a JSON object', () {
      expect(claudeSettingsAreFresh('nope', debugTrace: true), isFalse);
      expect(claudeSettingsAreFresh('[1]', debugTrace: true), isFalse);
    });

    test('the hook command is the one the binary dispatches', () {
      expect(ClaudeSettingsWire.hookCommand, _hookCommand);
    });
  });

  group('a sensitive project (debugTrace: false)', () {
    test('gets the hook and no env var', () {
      final merged = _merged('', debugTrace: false);
      expect(_preToolUse(merged).length, 1);
      expect(merged.containsKey('env'), isFalse);
    });

    test('loses the debug var claudart set, and an env left empty', () {
      final merged =
          _merged('{"env":{"CLAUDART_DEBUG":"1"}}', debugTrace: false);
      expect(merged.containsKey('env'), isFalse);
    });

    test('keeps the user\'s other env vars when it removes its own', () {
      final merged = _merged(
        '{"env":{"CLAUDART_DEBUG":"1","KEEP":"me"}}',
        debugTrace: false,
      );
      expect(merged['env'], {'KEEP': 'me'});
    });

    test('leaves a value the user set to something other than 1', () {
      final merged =
          _merged('{"env":{"CLAUDART_DEBUG":"0"}}', debugTrace: false);
      expect(merged['env'], {'CLAUDART_DEBUG': '0'});
    });

    test('fresh without the var, stale while the managed 1 is there', () {
      final clean = mergeClaudeSettings('', debugTrace: false);
      expect(claudeSettingsAreFresh(clean, debugTrace: false), isTrue);
      final withDebug = _withTrace('');
      expect(claudeSettingsAreFresh(withDebug, debugTrace: false), isFalse);
    });

    test('a user value other than 1 counts as fresh', () {
      final text = mergeClaudeSettings(
        '{"env":{"CLAUDART_DEBUG":"0"}}',
        debugTrace: false,
      );
      expect(claudeSettingsAreFresh(text, debugTrace: false), isTrue);
    });

    test('a settings file that wants the trace is stale without the var', () {
      final clean = mergeClaudeSettings('', debugTrace: false);
      expect(claudeSettingsAreFresh(clean, debugTrace: true), isFalse);
    });
  });
}
