import 'dart:io';

import 'package:claudart/commands/claudart_command.dart';
import 'package:claudart/session/handoff_event.dart';
import 'package:test/test.dart';

import '../helpers/event_usage.dart';

/// The `lib/commands` source file for a command, when it has its own.
String? _sourceFor(ClaudartCommand command) {
  final stem = switch (command) {
    ClaudartCommand.chat => 'chat_shell',
    ClaudartCommand.confirmPending => 'confirm_pending',
    ClaudartCommand.preflight => 'preflight_cmd',
    ClaudartCommand.map => 'map_cmd',
    _ => command.name,
  };
  final path = 'lib/commands/$stem.dart';
  return File(path).existsSync() ? path : null;
}

/// `runSetup(` for `setup`, `runConfirmPending(` for `confirmPending`.
String _runCall(ClaudartCommand command) =>
    'run${command.name[0].toUpperCase()}${command.name.substring(1)}(';

void main() {
  group('wireName and fromString', () {
    for (final command in ClaudartCommand.values) {
      test('${command.name}: fromString(wireName) round-trips', () {
        expect(ClaudartCommand.fromString(command.wireName), command);
      });
    }

    test('confirmPending is typed with a hyphen', () {
      expect(ClaudartCommand.confirmPending.wireName, 'confirm-pending');
    });

    test('anything else, including version, is not a command', () {
      expect(ClaudartCommand.fromString('version'), isNull);
      expect(ClaudartCommand.fromString('nonsense'), isNull);
      expect(ClaudartCommand.fromString(''), isNull);
    });
  });

  group('supportsHeadless', () {
    const headless = {
      ClaudartCommand.teardown,
      ClaudartCommand.rotate,
      ClaudartCommand.kill,
    };

    for (final command in ClaudartCommand.values) {
      final expected = headless.contains(command);
      test('${command.name}: supportsHeadless is $expected', () {
        expect(command.supportsHeadless, expected);
      });

      // Drift: a command takes a RunMode exactly when it declares headless.
      test('${command.name}: its source agrees', () {
        final path = _sourceFor(command);
        if (path == null) return;
        expect(
          File(path).readAsStringSync().contains('RunMode mode'),
          command.supportsHeadless,
        );
      });
    }
  });

  group('reachedFrom', () {
    const launcher = {
      ClaudartCommand.setup,
      ClaudartCommand.kill,
      ClaudartCommand.link,
    };
    const chat = {ClaudartCommand.flow, ClaudartCommand.suggest};
    final launcherSource = File('lib/commands/launch.dart').readAsStringSync();
    final chatSource = File('lib/commands/chat_shell.dart').readAsStringSync();

    for (final command in ClaudartCommand.values) {
      test('${command.name}: reached from the command line, always', () {
        expect(command.reachedFrom, contains(CommandEntry.cliSubcommand));
      });

      test('${command.name}: reachedFrom matches the literal table', () {
        expect(
          command.reachedFrom.contains(CommandEntry.launcherMenu),
          launcher.contains(command),
        );
        expect(
          command.reachedFrom.contains(CommandEntry.chatShell),
          chat.contains(command),
        );
      });

      // Drift: the launcher / chat shell call a command exactly when declared.
      test('${command.name}: the launcher and chat shell sources agree', () {
        expect(
          launcherSource.contains(_runCall(command)),
          command.reachedFrom.contains(CommandEntry.launcherMenu),
        );
        expect(
          chatSource.contains(_runCall(command)),
          command.reachedFrom.contains(CommandEntry.chatShell),
        );
      });
    }
  });

  group('handoffEvents', () {
    const expected = <ClaudartCommand, Set<HandoffEvent>>{
      ClaudartCommand.setup: {HandoffEvent.setup},
      ClaudartCommand.suggest: {HandoffEvent.saveConfirmedReady},
      ClaudartCommand.debug: {HandoffEvent.fixApplied},
      ClaudartCommand.rotate: {
        HandoffEvent.rotated,
        HandoffEvent.rotatedEmpty,
      },
      ClaudartCommand.teardown: {
        HandoffEvent.tornDown,
        HandoffEvent.reminderSaved,
      },
      ClaudartCommand.kill: {HandoffEvent.killed},
    };
    final usage = usageByEvent(readLibSources());

    for (final command in ClaudartCommand.values) {
      test('${command.name}: handoffEvents matches the literal table', () {
        expect(command.handoffEvents, expected[command] ?? <HandoffEvent>{});
      });

      // Drift: a command passes exactly the events whose usage lists its file.
      test('${command.name}: the events its source passes agree', () {
        final path = _sourceFor(command);
        if (path == null) return;
        final passed = {
          for (final entry in usage.entries)
            if (entry.value.contains(path)) entry.key,
        };
        expect(passed, command.handoffEvents);
      });
    }
  });
}
