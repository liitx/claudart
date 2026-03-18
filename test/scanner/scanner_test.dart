import 'package:test/test.dart';
import 'package:claudart/scanner/scanner.dart';
import 'package:claudart/scanner/scan_threshold_exception.dart';
import 'package:claudart/ignore_rules.dart';
import '../helpers/mocks.dart';

void main() {
  group('DartScanner', () {
    const projectRoot = '/project';

    MemoryFileIO buildIo(Map<String, String> dartFiles) {
      final files = <String, String>{};
      for (final entry in dartFiles.entries) {
        files['$projectRoot/lib/${entry.key}'] = entry.value;
      }
      return MemoryFileIO(files: files);
    }

    test('detects Bloc class correctly', () {
      final io = buildIo({
        'volume_bloc.dart':
            'class VolumeBloc extends Bloc<VolumeEvent, VolumeState> {}',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeBloc'), isTrue);
      expect(
        result.entities['VolumeBloc']!.tokenType,
        equals(EntityType.bloc),
      );
    });

    test('detects Repository correctly', () {
      final io = buildIo({
        'volume_repository.dart':
            'abstract class VolumeRepository { Future<void> play(); }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeRepository'), isTrue);
      expect(
        result.entities['VolumeRepository']!.tokenType,
        equals(EntityType.repository),
      );
    });

    test('detects Extension correctly', () {
      final io = buildIo({
        'volume_ext.dart': 'extension VolumeBlocX on VolumeBloc { void stop() {} }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeBlocX'), isTrue);
      expect(
        result.entities['VolumeBlocX']!.tokenType,
        equals(EntityType.extension),
      );
    });

    test('detects Enum correctly', () {
      final io = buildIo({
        'volume_status.dart': 'enum VolumeStatus { playing, paused, stopped }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeStatus'), isTrue);
      expect(
        result.entities['VolumeStatus']!.tokenType,
        equals(EntityType.enumType),
      );
    });

    test('detects Widget correctly', () {
      final io = buildIo({
        'volume_widget.dart':
            'class VolumeWidget extends StatelessWidget { @override Widget build(BuildContext context) => SizedBox(); }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeWidget'), isTrue);
      expect(
        result.entities['VolumeWidget']!.tokenType,
        equals(EntityType.widget),
      );
    });

    test('detects typedef callback', () {
      final io = buildIo({
        'callbacks.dart': 'typedef VolumeCallback = void Function(String);',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('VolumeCallback'), isTrue);
      expect(
        result.entities['VolumeCallback']!.tokenType,
        equals(EntityType.callback),
      );
    });

    test('.g.dart files are skipped', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/lib/audio.g.dart':
            'class VolumeBloc extends Bloc<VolumeEvent, VolumeState> {}',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities, isEmpty);
      expect(result.filesSkipped, greaterThan(0));
    });

    test('threshold hit throws ScanThresholdException with correct fields', () {
      // Build 5 files, set threshold to 3
      final files = <String, String>{};
      for (var i = 0; i < 5; i++) {
        files['$projectRoot/lib/file_$i.dart'] = 'class C$i {}';
      }
      final io = MemoryFileIO(files: files);
      expect(
        () => scanProject(projectRoot, io: io, threshold: 3),
        throwsA(
          isA<ScanThresholdException>()
              .having((e) => e.filesFound, 'filesFound', equals(5))
              .having((e) => e.threshold, 'threshold', equals(3))
              .having(
                (e) => e.suggestions,
                'suggestions',
                isNotEmpty,
              ),
        ),
      );
    });

    test('filesScanned reflects actual scanned count', () {
      final io = buildIo({
        'volume_bloc.dart': 'class VolumeBloc extends Bloc<VolumeEvent, VolumeState> {}',
        'volume_repository.dart': 'class VolumeRepository {}',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.filesScanned, equals(2));
    });

    test('custom ignore rules respected', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/lib/audio.g.dart': 'class Generated {}',
        '$projectRoot/lib/buster.dart': 'class VolumeBloc extends Bloc<E, S> {}',
      });
      final rules = loadIgnoreRules(projectRoot, io: io);
      final result = scanProject(projectRoot, ignoreRules: rules, io: io);
      expect(result.entities.containsKey('VolumeBloc'), isTrue);
      expect(result.entities.containsKey('Generated'), isFalse);
    });
  });
}
