// workspace_config_test.dart — StackType / WorkspaceRole / ProofNotation /
// WorkspaceConfig (lib/workspace/workspace_config.dart)
//
// Distinct from test/config_test.dart, which covers the unrelated
// WorkspaceConfig in lib/config.dart (workspace.json's local scan/sensitivity
// settings, not the session-scoped owner/project/session config this file
// parses at Step 0). No file imports both, so there's no active name
// collision — just a latent one, noted and left alone here.

import 'package:test/test.dart';
import 'package:claudart/errors/failure_type.dart';
import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/workspace/workspace_config.dart';
import '../helpers/mocks.dart';
import '../helpers/project_fixture.dart';

const _workspaceDir = ProjectFixture.workspace;
const _workspaceJsonPath = '$_workspaceDir/workspace.json';

void main() {
  group('StackType.fromString', () {
    for (final s in StackType.values) {
      test('round-trips ${s.name}', () {
        expect(StackType.fromString(s.value), equals(s));
      });
    }

    test('returns null for an unrecognised value', () {
      expect(StackType.fromString('cobol'), isNull);
    });
  });

  group('WorkspaceRole.fromString', () {
    test('maintainer round-trips', () {
      expect(WorkspaceRole.fromString('maintainer'),
          equals(WorkspaceRole.maintainer));
    });

    test('contributor round-trips', () {
      expect(WorkspaceRole.fromString('contributor'),
          equals(WorkspaceRole.contributor));
    });

    test('an unrecognised value is not a role, and is not guessed', () {
      expect(WorkspaceRole.fromString('owner'), isNull);
    });

    test('maintainer canUpdateReadme is true', () {
      expect(WorkspaceRole.maintainer.canUpdateReadme, isTrue);
    });

    test('contributor canUpdateReadme is false', () {
      expect(WorkspaceRole.contributor.canUpdateReadme, isFalse);
    });
  });

  group('ProofNotation.fromString', () {
    test('dart-grounded round-trips', () {
      expect(ProofNotation.fromString('dart-grounded'),
          equals(ProofNotation.dartGrounded));
      expect(ProofNotation.dartGrounded.value, equals('dart-grounded'));
    });

    test('ts-grounded round-trips', () {
      expect(ProofNotation.fromString('ts-grounded'),
          equals(ProofNotation.tsGrounded));
      expect(ProofNotation.tsGrounded.value, equals('ts-grounded'));
    });

    test('generic round-trips', () {
      expect(ProofNotation.fromString('generic'), ProofNotation.generic);
      expect(ProofNotation.generic.value, equals('generic'));
    });

    test('an unrecognised value is not a notation, and is not guessed', () {
      expect(ProofNotation.fromString('python-grounded'), isNull);
    });
  });

  group('$WorkspaceConfig.load with a value it does not know', () {
    const base = '{"owner": {"name": "n", "email": "e", "handle": "h"}, '
        '"project": {"name": "p", "stack": ["dart"], "role": ROLE}, '
        '"session": {"agents": [], "knowledge": [], '
        '"proofNotation": NOTATION, "sensitivityMode": false}}';

    String json({
      String role = '"maintainer"',
      String notation = '"generic"',
    }) =>
        base.replaceFirst('ROLE', role).replaceFirst('NOTATION', notation);

    test('a known role and notation load', () {
      final io = MemoryFileIO(files: {_workspaceJsonPath: json()});
      expect(
        WorkspaceConfig.load(_workspaceDir, io: io)!.project.role,
        WorkspaceRole.maintainer,
      );
    });

    test('an unknown role is unreadable, not quietly a contributor', () {
      final io = MemoryFileIO(
        files: {_workspaceJsonPath: json(role: '"owner"')},
      );
      expect(
        () => WorkspaceConfig.load(_workspaceDir, io: io),
        throwsA(isA<WorkspaceConfigUnreadableException>()),
      );
    });

    test('an unknown proof notation is unreadable, not quietly generic', () {
      final io = MemoryFileIO(
        files: {_workspaceJsonPath: json(notation: '"python-grounded"')},
      );
      expect(
        () => WorkspaceConfig.load(_workspaceDir, io: io),
        throwsA(isA<WorkspaceConfigUnreadableException>()),
      );
    });
  });

  group('WorkspaceConfig.load', () {
    test('returns null when workspace.json is missing', () {
      final io = MemoryFileIO();
      expect(WorkspaceConfig.load(_workspaceDir, io: io), isNull);
    });

    test('returns null when workspace.json is empty', () {
      final io = MemoryFileIO(files: {_workspaceJsonPath: ''});
      expect(WorkspaceConfig.load(_workspaceDir, io: io), isNull);
    });

    test('throws WorkspaceConfigUnreadableException for malformed json', () {
      final io = MemoryFileIO(files: {
        _workspaceJsonPath: '{not valid json',
      });
      expect(
        () => WorkspaceConfig.load(_workspaceDir, io: io),
        throwsA(isA<WorkspaceConfigUnreadableException>()),
      );
    });

    test('the exception carries the workspaceConfigUnreadable failure', () {
      final io = MemoryFileIO(files: {_workspaceJsonPath: '[1, 2]'});
      try {
        WorkspaceConfig.load(_workspaceDir, io: io);
        fail('load should have thrown');
      } on WorkspaceConfigUnreadableException catch (e) {
        expect(e.failureType, FailureType.workspaceConfigUnreadable);
      }
    });

    // Valid JSON of the wrong shape throws a TypeError (an Error, not an
    // Exception); each of these is unreadable, reported as the typed failure.
    final wrongShapes = <String, String>{
      'a missing section': '{"hand": "written"}',
      'a section of the wrong type':
          '{"owner": "x", "project": 1, "session": 2}',
      'a field of the wrong type':
          '{"owner": {"name": 1, "email": "e", "handle": "h"}}',
      'a top-level list': '[1, 2]',
    };
    wrongShapes.forEach((name, text) {
      test('throws WorkspaceConfigUnreadableException for $name', () {
        final io = MemoryFileIO(files: {_workspaceJsonPath: text});
        expect(
          () => WorkspaceConfig.load(_workspaceDir, io: io),
          throwsA(isA<WorkspaceConfigUnreadableException>()),
        );
      });
    });

    test('parses a full workspace.json into typed fields', () {
      final io = MemoryFileIO(files: {
        _workspaceJsonPath: '''
{
  "owner": {"name": "Aksana", "email": "a@vgv.dev", "handle": "aksana", "strict": true},
  "project": {"name": "claudart", "stack": ["dart", "flutter"], "role": "maintainer", "repo": "claudart", "org": "vgv"},
  "session": {"agents": ["suggest", "debug"], "knowledge": ["PLAN.md"], "proofNotation": "dart-grounded", "sensitivityMode": true}
}
''',
      });

      final cfg = WorkspaceConfig.load(_workspaceDir, io: io)!;

      expect(cfg.owner.name, equals('Aksana'));
      expect(cfg.owner.email, equals('a@vgv.dev'));
      expect(cfg.owner.handle, equals('aksana'));
      expect(cfg.owner.strict, isTrue);

      expect(cfg.project.name, equals('claudart'));
      expect(cfg.project.stack, equals([StackType.dart, StackType.flutter]));
      expect(cfg.project.role, equals(WorkspaceRole.maintainer));
      expect(cfg.project.repo, equals('claudart'));
      expect(cfg.project.org, equals('vgv'));

      expect(cfg.session.agents, equals([AgentFlow.suggest, AgentFlow.debug]));
      expect(cfg.session.knowledge, equals(['PLAN.md']));
      expect(cfg.session.proofNotation, equals(ProofNotation.dartGrounded));
      expect(cfg.session.sensitivityMode, isTrue);
    });

    test('applies defaults for omitted optional fields', () {
      final io = MemoryFileIO(files: {
        _workspaceJsonPath: '''
{
  "owner": {"name": "Aksana", "email": "a@vgv.dev", "handle": "aksana"},
  "project": {"name": "claudart", "stack": []},
  "session": {"agents": [], "knowledge": []}
}
''',
      });

      final cfg = WorkspaceConfig.load(_workspaceDir, io: io)!;

      expect(cfg.owner.strict, isFalse);
      expect(cfg.project.role, equals(WorkspaceRole.contributor));
      expect(cfg.project.repo, isNull);
      expect(cfg.project.org, isNull);
      expect(cfg.session.proofNotation, equals(ProofNotation.generic));
      expect(cfg.session.sensitivityMode, isFalse);
    });

    test('drops unrecognised stack and agent entries instead of throwing', () {
      final io = MemoryFileIO(files: {
        _workspaceJsonPath: '''
{
  "owner": {"name": "Aksana", "email": "a@vgv.dev", "handle": "aksana"},
  "project": {"name": "claudart", "stack": ["dart", "cobol"]},
  "session": {"agents": ["suggest", "unknown-agent"], "knowledge": []}
}
''',
      });

      final cfg = WorkspaceConfig.load(_workspaceDir, io: io)!;

      expect(cfg.project.stack, equals([StackType.dart]));
      expect(cfg.session.agents, equals([AgentFlow.suggest]));
    });
  });

  group('WorkspaceConfig.toJson / write round-trip', () {
    const config = WorkspaceConfig(
      owner: WorkspaceOwner(
        name: 'Aksana',
        email: 'a@vgv.dev',
        handle: 'aksana',
        strict: true,
      ),
      project: WorkspaceProject(
        name: 'claudart',
        stack: [StackType.dart, StackType.flutter],
        role: WorkspaceRole.maintainer,
        repo: 'claudart',
        org: 'vgv',
      ),
      session: WorkspaceSession(
        agents: [AgentFlow.suggest, AgentFlow.debug],
        knowledge: ['dart'],
        proofNotation: ProofNotation.dartGrounded,
        sensitivityMode: true,
      ),
    );

    test('fromJson(toJson(x)) round-trips every field', () {
      final roundTripped = WorkspaceConfig.fromJson(config.toJson());

      expect(roundTripped.owner.name, equals(config.owner.name));
      expect(roundTripped.owner.email, equals(config.owner.email));
      expect(roundTripped.owner.handle, equals(config.owner.handle));
      expect(roundTripped.owner.strict, equals(config.owner.strict));

      expect(roundTripped.project.name, equals(config.project.name));
      expect(roundTripped.project.stack, equals(config.project.stack));
      expect(roundTripped.project.role, equals(config.project.role));
      expect(roundTripped.project.repo, equals(config.project.repo));
      expect(roundTripped.project.org, equals(config.project.org));

      expect(roundTripped.session.agents, equals(config.session.agents));
      expect(roundTripped.session.knowledge, equals(config.session.knowledge));
      expect(roundTripped.session.proofNotation, equals(config.session.proofNotation));
      expect(roundTripped.session.sensitivityMode, equals(config.session.sensitivityMode));
    });

    test('omits optional project fields from toJson when null', () {
      const noOptionals = WorkspaceProject(
        name: 'claudart',
        stack: [StackType.dart],
        role: WorkspaceRole.contributor,
      );
      expect(noOptionals.toJson().containsKey('repo'), isFalse);
      expect(noOptionals.toJson().containsKey('org'), isFalse);
    });

    test('write persists content that load reads back identically', () {
      final io = MemoryFileIO();
      config.write(_workspaceDir, io: io);
      final loaded = WorkspaceConfig.load(_workspaceDir, io: io)!;
      expect(loaded.toJson(), equals(config.toJson()));
    });
  });
}
