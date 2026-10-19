import 'dart:convert';

import 'package:claudart/templates/claude_settings_template.dart';
import 'package:test/test.dart';

const _hookCommand = 'claudart hook pre-edit';
const _userSettings = '{"permissions":{"allow":["Bash(ls)"]},'
    '"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":'
    '[{"type":"command","command":"echo hi"}]}]}}';

Map<String, dynamic> _merged(String existing) =>
    jsonDecode(mergeClaudeSettings(existing)) as Map<String, dynamic>;

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
      final first = mergeClaudeSettings('');
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
      final once = mergeClaudeSettings(_userSettings);
      expect(mergeClaudeSettings(once), once);
    });

    test('leaves an env value the user already set', () {
      final merged = _merged('{"env":{"CLAUDART_DEBUG":"0","X":"y"}}');
      expect(merged['env'], {'CLAUDART_DEBUG': '0', 'X': 'y'});
    });

    test('a file that is not a JSON object throws FormatException', () {
      expect(() => mergeClaudeSettings('[1]'), throwsFormatException);
      expect(() => mergeClaudeSettings('nope'), throwsFormatException);
    });

    test('ends with a newline', () {
      expect(mergeClaudeSettings(''), endsWith('}\n'));
    });
  });

  group('claudeSettingsAreFresh', () {
    test('false for an empty file', () {
      expect(claudeSettingsAreFresh(''), isFalse);
    });

    test('true for what merge writes', () {
      expect(claudeSettingsAreFresh(mergeClaudeSettings('')), isTrue);
      expect(claudeSettingsAreFresh(mergeClaudeSettings(_userSettings)), isTrue);
    });

    test('false when the hook entry differs', () {
      final stale =
          mergeClaudeSettings('').replaceFirst('Edit|Write|MultiEdit', 'Edit');
      expect(claudeSettingsAreFresh(stale), isFalse);
    });

    test('false when the env var is missing', () {
      final stale = mergeClaudeSettings('').replaceFirst('CLAUDART_DEBUG', 'X');
      expect(claudeSettingsAreFresh(stale), isFalse);
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
      expect(claudeSettingsAreFresh(doubled), isFalse);
    });

    test('false for text that is not a JSON object', () {
      expect(claudeSettingsAreFresh('nope'), isFalse);
      expect(claudeSettingsAreFresh('[1]'), isFalse);
    });

    test('the hook command is the one the binary dispatches', () {
      expect(ClaudeSettingsWire.hookCommand, _hookCommand);
    });
  });
}
