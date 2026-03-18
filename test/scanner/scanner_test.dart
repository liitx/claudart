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
        'audio_bloc.dart':
            'class AudioBloc extends Bloc<AudioEvent, AudioState> {}',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioBloc'), isTrue);
      expect(
        result.entities['AudioBloc']!.tokenType,
        equals(EntityType.bloc),
      );
    });

    test('detects Repository correctly', () {
      final io = buildIo({
        'audio_repository.dart':
            'abstract class AudioRepository { Future<void> play(); }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioRepository'), isTrue);
      expect(
        result.entities['AudioRepository']!.tokenType,
        equals(EntityType.repository),
      );
    });

    test('detects Extension correctly', () {
      final io = buildIo({
        'audio_ext.dart': 'extension AudioBlocX on AudioBloc { void stop() {} }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioBlocX'), isTrue);
      expect(
        result.entities['AudioBlocX']!.tokenType,
        equals(EntityType.extension),
      );
    });

    test('detects Enum correctly', () {
      final io = buildIo({
        'audio_status.dart': 'enum AudioStatus { playing, paused, stopped }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioStatus'), isTrue);
      expect(
        result.entities['AudioStatus']!.tokenType,
        equals(EntityType.enumType),
      );
    });

    test('detects Widget correctly', () {
      final io = buildIo({
        'audio_widget.dart':
            'class AudioWidget extends StatelessWidget { @override Widget build(BuildContext context) => SizedBox(); }',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioWidget'), isTrue);
      expect(
        result.entities['AudioWidget']!.tokenType,
        equals(EntityType.widget),
      );
    });

    test('detects typedef callback', () {
      final io = buildIo({
        'callbacks.dart': 'typedef AudioCallback = void Function(String);',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.entities.containsKey('AudioCallback'), isTrue);
      expect(
        result.entities['AudioCallback']!.tokenType,
        equals(EntityType.callback),
      );
    });

    test('.g.dart files are skipped', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/lib/audio.g.dart':
            'class AudioBloc extends Bloc<AudioEvent, AudioState> {}',
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
        'audio_bloc.dart': 'class AudioBloc extends Bloc<AudioEvent, AudioState> {}',
        'audio_repository.dart': 'class AudioRepository {}',
      });
      final result = scanProject(projectRoot, io: io);
      expect(result.filesScanned, equals(2));
    });

    test('custom ignore rules respected', () {
      final io = MemoryFileIO(files: {
        '$projectRoot/lib/audio.g.dart': 'class Generated {}',
        '$projectRoot/lib/audio.dart': 'class AudioBloc extends Bloc<E, S> {}',
      });
      final rules = loadIgnoreRules(projectRoot, io: io);
      final result = scanProject(projectRoot, ignoreRules: rules, io: io);
      expect(result.entities.containsKey('AudioBloc'), isTrue);
      expect(result.entities.containsKey('Generated'), isFalse);
    });
  });
}
