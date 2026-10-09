// workspace_config_test.dart — StackType / WorkspaceRole / ProofNotation /
// WorkspaceConfig (lib/workspace/workspace_config.dart)
//
// Distinct from test/config_test.dart, which covers the unrelated
// WorkspaceConfig in lib/config.dart (workspace.json's local scan/sensitivity
// settings, not the session-scoped owner/project/session config this file
// parses at Step 0). No file imports both, so there's no active name
// collision — just a latent one, noted and left alone here.

import 'package:test/test.dart';
import 'package:claudart/pipeline/agent_flow.dart';
import 'package:claudart/workspace/workspace_config.dart';
import '../helpers/mocks.dart';

const _workspaceDir = '/workspaces/my-app';
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

    test('unrecognised value defaults to contributor', () {
      expect(
          WorkspaceRole.fromString('owner'), equals(WorkspaceRole.contributor));
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

    test('unrecognised value defaults to generic', () {
      expect(ProofNotation.fromString('python-grounded'),
          equals(ProofNotation.generic));
      expect(ProofNotation.generic.value, equals('generic'));
    });
  });

  group('WorkspaceConfig.load', () {
    test('returns null when workspace.json is missing', () {
      final io = MemoryFileIO();
      expect(WorkspaceConfig.load(_workspaceDir, io: io), isNull);
    });

    test('returns null when workspace.json is malformed json', () {
      final io = MemoryFileIO(files: {
        _workspaceJsonPath: '{not valid json',
      });
      expect(WorkspaceConfig.load(_workspaceDir, io: io), isNull);
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
