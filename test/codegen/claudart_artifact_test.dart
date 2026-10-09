import 'package:test/test.dart';
import 'package:claudart/codegen/claudart_artifact.dart';

void main() {
  group('ClaudartArtifact', () {
    test('has exactly the 4 real derivations link.dart regenerates', () {
      expect(
        ClaudartArtifact.values,
        equals([
          ClaudartArtifact.commandTemplates,
          ClaudartArtifact.claudeMdTail,
          ClaudartArtifact.readmeRoadmap,
          ClaudartArtifact.dependencyConfig,
        ]),
      );
    });

    test('commandTemplates is first — locks the existing write order from before this enum existed', () {
      expect(ClaudartArtifact.values.first, ClaudartArtifact.commandTemplates);
    });
  });
}
