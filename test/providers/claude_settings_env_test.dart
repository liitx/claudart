// claude_settings_env_test.dart — readClaudeSettingsEnv's parse/degrade
// paths, one scenario per test() per dartrix's testing paradigm.

import 'package:claudart/providers/claude_settings_env.dart';
import 'package:test/test.dart';

import '../helpers/mocks.dart';

void main() {
  group('readClaudeSettingsEnv', () {
    test('reads string entries out of the top-level env object', () {
      final io = MemoryFileIO(files: {
        '/fake/settings.json': '{"env": {"AWS_PROFILE": "ai-tooling-bedrock-access"}}',
      });
      final env = readClaudeSettingsEnv(io: io, path: '/fake/settings.json');
      expect(env, equals({'AWS_PROFILE': 'ai-tooling-bedrock-access'}));
    });

    test('returns empty when the file does not exist', () {
      final io = MemoryFileIO();
      final env = readClaudeSettingsEnv(io: io, path: '/fake/missing.json');
      expect(env, isEmpty);
    });

    test('returns empty when the JSON is malformed', () {
      final io = MemoryFileIO(files: {'/fake/settings.json': '{not json'});
      final env = readClaudeSettingsEnv(io: io, path: '/fake/settings.json');
      expect(env, isEmpty);
    });

    test('returns empty when env key is absent', () {
      final io = MemoryFileIO(files: {'/fake/settings.json': '{"other": true}'});
      final env = readClaudeSettingsEnv(io: io, path: '/fake/settings.json');
      expect(env, isEmpty);
    });

    test('returns empty when env is not an object', () {
      final io = MemoryFileIO(files: {'/fake/settings.json': '{"env": "nope"}'});
      final env = readClaudeSettingsEnv(io: io, path: '/fake/settings.json');
      expect(env, isEmpty);
    });

    test('drops non-string values instead of throwing', () {
      final io = MemoryFileIO(files: {
        '/fake/settings.json': '{"env": {"AWS_PROFILE": "x", "SOME_FLAG": true}}',
      });
      final env = readClaudeSettingsEnv(io: io, path: '/fake/settings.json');
      expect(env, equals({'AWS_PROFILE': 'x'}));
    });
  });
}
