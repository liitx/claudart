// command_faults.dart — single changes to what each CLI command says about itself
//
// Every `ClaudartCommand` states its facts as constructor data, and other
// code (the dispatch, the launcher, the boundary that records each run, the
// handoff writer) trusts them. Each fact of each command is changed on its own:
// a true/false fact flipped, the wire name altered, the entry points swapped
// for another set, a handoff event added or removed. The proofs are meant to
// check each against the command's real source.

import 'dart:io';

import 'package:claudart/commands/support/claudart_command.dart';
import 'package:claudart/session/handoff_event.dart';

import 'fault.dart';
import 'line_faults.dart';

const _sourceFilePath = 'lib/commands/support/claudart_command.dart';
const _entrySets = ['_cliOnly', '_cliAndLauncher', '_cliAndChat'];
const _flags = [
  'supportsHeadless',
  'recordsStepModels',
  'ownsProjectOption',
  'supportsProjectSelector',
];

/// The `handoffEvents:` statement written for [events].
List<String> _eventsStatement(Set<HandoffEvent> events) {
  if (events.isEmpty) return ['    handoffEvents: _noEvents,'];
  final ordered = [
    for (final event in HandoffEvent.values)
      if (events.contains(event)) event,
  ];
  return [
    '    handoffEvents: {',
    for (final event in ordered) '      HandoffEvent.${event.name},',
    '    },',
  ];
}

class ClaudartCommandFaults extends FaultProvider {
  const ClaudartCommandFaults();

  @override
  String get proof => 'claudartCommand';

  @override
  List<String> get tierOneTests => const [
        'test/commands/claudart_command_test.dart',
        'test/commands/interaction_boundary_test.dart',
      ];

  @override
  List<String> get tierTwoTests => const [
        'test/commands',
        'test/topology',
        'test/session',
        'test/conformance',
      ];

  @override
  List<SeededFault> faults(String repositoryRoot) {
    final lines = File('$repositoryRoot/$_sourceFilePath').readAsStringSync().split('\n');
    final faults = <SeededFault>[];
    final blockStart = RegExp(r'^  (\w+)\($');
    var found = 0;

    for (var index = 0; index < lines.length; index++) {
      final start = blockStart.firstMatch(lines[index]);
      if (start == null) continue;
      final command = ClaudartCommand.values.byName(start.group(1)!);
      found++;
      final blockEnd = linesBetween(lines, index + 2, lines.skip(index + 1).firstWhere(
          (l) => l == '  ),' || l == '  );'))
          .last;

      for (var number = index + 2; number <= blockEnd; number++) {
        final line = lines[number - 1];
        final flag = RegExp(r'^    (\w+): (true|false),$').firstMatch(line);
        if (flag != null && _flags.contains(flag.group(1))) {
          final flipped = flag.group(2) == 'true' ? 'false' : 'true';
          faults.add(_edit(number, '${command.name}.${flag.group(1)}: '
              '${flag.group(2)} -> $flipped',
              (all) => replacingLine(all, number, '    ${flag.group(1)}: $flipped,')));
        }
        final wire = RegExp(r"^    wireName: '([\w-]+)',$").firstMatch(line);
        if (wire != null) {
          faults.add(_edit(number, '${command.name}.wireName: ${wire.group(1)} '
              '-> ${wire.group(1)}_',
              (all) => replacingLine(all, number, "    wireName: '${wire.group(1)}_',")));
        }
        final entry = RegExp(r'^    reachedFrom: (_\w+),$').firstMatch(line);
        if (entry != null) {
          for (final other in _entrySets) {
            if (other == entry.group(1)) continue;
            faults.add(_edit(number, '${command.name}.reachedFrom: '
                '${entry.group(1)} -> $other',
                (all) => replacingLine(all, number, '    reachedFrom: $other,')));
          }
        }
        if (line.startsWith('    handoffEvents:')) {
          final statementEnd =
              line.endsWith('{') ? lines.indexOf('    },', number - 1) + 1 : number;
          for (final event in HandoffEvent.values) {
            final present = command.handoffEvents.contains(event);
            final changed = present
                ? ({...command.handoffEvents}..remove(event))
                : {...command.handoffEvents, event};
            faults.add(_edit(number,
                '${command.name}.handoffEvents: ${present ? 'remove' : 'add'} '
                '${event.name}',
                (all) => [
                      ...all.sublist(0, number - 1),
                      ..._eventsStatement(changed),
                      ...all.sublist(statementEnd),
                    ]));
          }
        }
      }
    }
    if (found != ClaudartCommand.values.length) {
      throw StateError('found $found of ${ClaudartCommand.values.length} '
          'commands in $_sourceFilePath');
    }
    return faults;
  }

  LineEditFault _edit(
    int line,
    String description,
    List<String> Function(List<String> lines) edit,
  ) =>
      LineEditFault(
        proof: proof,
        description: description,
        sourceFile: _sourceFilePath,
        sourceLine: line,
        edit: edit,
      );
}
