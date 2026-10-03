// portability_gap_test.dart — one test() per PortabilityGap variant, per
// dartrix's testing paradigm — a loop here would collapse every variant's
// pass/fail into one result and hide failures after the first.

import 'package:claudart/claudart.dart';
import 'package:test/test.dart';

void main() {
  group('PortabilityGap invariants hold for every variant', () {
    for (final gap in PortabilityGap.values) {
      test('${gap.name} has non-empty whatsMissing and trackedIn', () {
        expect(gap.whatsMissing, isNotEmpty);
        expect(gap.trackedIn, isNotEmpty);
      });
    }
  });

  group('PortabilityGap.providerWiring', () {
    test('is open — the primitive exists but is not wired in yet', () {
      expect(PortabilityGap.providerWiring.status, equals(PortabilityGapStatus.open));
      expect(PortabilityGap.providerWiring.trackedIn, contains('docs/provider_setup.md'));
    });
  });

  group('PortabilityGap.zedEditorIntegration', () {
    test('is tabled — no second IDE target to generalize against', () {
      expect(PortabilityGap.zedEditorIntegration.status, equals(PortabilityGapStatus.tabled));
      expect(PortabilityGap.zedEditorIntegration.whatsMissing, contains('link.dart'));
    });
  });

  group('PortabilityGap.zedupEnvWorkspaceResolution', () {
    test('is tabled — ZedProfile is org identity, not IDE coupling', () {
      expect(PortabilityGap.zedupEnvWorkspaceResolution.status, equals(PortabilityGapStatus.tabled));
      expect(PortabilityGap.zedupEnvWorkspaceResolution.whatsMissing, contains('ZedProfile'));
    });
  });

  group('PortabilityGap.verificationHarness', () {
    test('is open — claudart doctor ships a partial check set', () {
      expect(PortabilityGap.verificationHarness.status, equals(PortabilityGapStatus.open));
      expect(PortabilityGap.verificationHarness.trackedIn, contains('doctor.dart'));
    });
  });

  group('PortabilityGap.hardcodedWorkspacePaths', () {
    test('is open — CLAUDE.md\'s Knowledge base section hardcodes this machine\'s paths', () {
      expect(PortabilityGap.hardcodedWorkspacePaths.status, equals(PortabilityGapStatus.open));
      expect(PortabilityGap.hardcodedWorkspacePaths.whatsMissing, contains('CLAUDE.md'));
    });
  });

  group('PortabilityGapStatus.label', () {
    test('open', () => expect(PortabilityGapStatus.open.label, equals('open')));
    test('tabled', () => expect(PortabilityGapStatus.tabled.label, equals('tabled')));
    test('planned', () => expect(PortabilityGapStatus.planned.label, equals('planned')));
  });
}
