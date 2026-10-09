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

    test('commandTemplates is first — runLink depends on it running before the others read links', () {
      expect(ClaudartArtifact.values.first, ClaudartArtifact.commandTemplates);
    });
  });
}
