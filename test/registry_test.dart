import 'package:test/test.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'helpers/mocks.dart';

RegistryEntry _entry(String name, {String? projectRoot}) => RegistryEntry(
      name: name,
      projectRoot: projectRoot ?? '/projects/$name',
      workspacePath: '/workspaces/$name',
      createdAt: '2026-03-16',
      lastSession: '2026-03-16',
    );

void main() {
  group('Registry.load', () {
    test('returns empty registry when file missing', () {
      final io = MemoryFileIO();
      final reg = Registry.load(io: io);
      expect(reg.isEmpty, isTrue);
      expect(reg.entries, isEmpty);
    });

    test('returns empty registry when file is corrupt', () {
      final io = MemoryFileIO(files: {registryPath: 'not-json'});
      final reg = Registry.load(io: io);
      expect(reg.isEmpty, isTrue);
    });

    test('parses entries correctly', () {
      final io = MemoryFileIO(files: {
        registryPath: '''
{
  "_warning": "...",
  "workspaces": [
    {
      "name": "my-app",
      "projectRoot": "/projects/my-app",
      "workspacePath": "/workspaces/my-app",
      "createdAt": "2026-03-15",
      "lastSession": "2026-03-16",
      "sensitivityMode": true
    }
  ]
}''',
      });
      final reg = Registry.load(io: io);
      expect(reg.entries, hasLength(1));
      final e = reg.entries.first;
      expect(e.name, equals('my-app'));
      expect(e.sensitivityMode, isTrue);
      expect(e.lastSession, equals('2026-03-16'));
    });

    test('sensitivityMode defaults to false when missing from json', () {
      final io = MemoryFileIO(files: {
        registryPath: '''
{
  "workspaces": [
    {
      "name": "x",
      "projectRoot": "/p",
      "workspacePath": "/w",
      "createdAt": "2026-01-01",
      "lastSession": "2026-01-01"
    }
  ]
}''',
      });
      final reg = Registry.load(io: io);
      expect(reg.findByName('x')!.sensitivityMode, isFalse);
    });
  });

  group('Registry.save', () {
    test('writes _warning field', () {
      final io = MemoryFileIO();
      Registry.empty().save(io: io);
      final raw = io.read(registryPath);
      expect(raw, contains('_warning'));
    });

    test('round-trip preserves all entry fields', () {
      final io = MemoryFileIO();
      final original = Registry.empty().add(_entry('my-app'));
      original.save(io: io);
      final loaded = Registry.load(io: io);
      final e = loaded.findByName('my-app')!;
      expect(e.name, equals('my-app'));
      expect(e.projectRoot, equals('/projects/my-app'));
      expect(e.workspacePath, equals('/workspaces/my-app'));
    });

    test('round-trip preserves multiple entries', () {
      final io = MemoryFileIO();
      Registry.empty()
          .add(_entry('project-a'))
          .add(_entry('project-b'))
          .save(io: io);
      final loaded = Registry.load(io: io);
      expect(loaded.entries, hasLength(2));
      expect(loaded.findByName('project-a'), isNotNull);
      expect(loaded.findByName('project-b'), isNotNull);
    });
  });

  group('Registry.findByName', () {
    test('returns entry for known name', () {
      final reg = Registry.empty().add(_entry('my-app'));
      expect(reg.findByName('my-app'), isNotNull);
    });

    test('returns null for unknown name', () {
      final reg = Registry.empty().add(_entry('my-app'));
      expect(reg.findByName('other'), isNull);
    });
  });

  group('Registry.findByProjectRoot', () {
    test('returns entry matching project root path', () {
      final reg = Registry.empty()
          .add(_entry('my-app', projectRoot: '/projects/my-app'));
      final e = reg.findByProjectRoot('/projects/my-app');
      expect(e, isNotNull);
      expect(e!.name, equals('my-app'));
    });

    test('returns null when no entry matches path', () {
      final reg = Registry.empty().add(_entry('my-app'));
      expect(reg.findByProjectRoot('/somewhere/else'), isNull);
    });
  });

  group('Registry.add', () {
    test('adds new entry', () {
      final reg = Registry.empty().add(_entry('my-app'));
      expect(reg.findByName('my-app'), isNotNull);
    });

    test('replacing existing entry by name does not grow the registry', () {
      final updated = _entry('my-app').copyWith(lastSession: '2026-04-01');
      final reg = Registry.empty()
          .add(_entry('my-app'))
          .add(updated);
      expect(reg.entries, hasLength(1));
      expect(reg.findByName('my-app')!.lastSession, equals('2026-04-01'));
    });

    test('does not mutate original registry', () {
      final original = Registry.empty();
      original.add(_entry('my-app'));
      expect(original.isEmpty, isTrue);
    });
  });

  group('Registry.remove', () {
    test('removes entry by name', () {
      final reg = Registry.empty()
          .add(_entry('my-app'))
          .remove('my-app');
      expect(reg.findByName('my-app'), isNull);
    });

    test('does not affect other entries', () {
      final reg = Registry.empty()
          .add(_entry('project-a'))
          .add(_entry('project-b'))
          .remove('project-a');
      expect(reg.findByName('project-b'), isNotNull);
    });

    test('is safe when name does not exist', () {
      final reg = Registry.empty().add(_entry('my-app'));
      expect(() => reg.remove('unknown'), returnsNormally);
      expect(reg.entries, hasLength(1));
    });
  });

  group('Registry.touchSession', () {
    test('updates lastSession for named entry', () {
      final reg = Registry.empty()
          .add(_entry('my-app'))
          .touchSession('my-app');
      final today = DateTime.now().toIso8601String().split('T').first;
      expect(reg.findByName('my-app')!.lastSession, equals(today));
    });

    test('does not affect other entries', () {
      final reg = Registry.empty()
          .add(_entry('project-a'))
          .add(_entry('project-b'))
          .touchSession('project-a');
      expect(
        reg.findByName('project-b')!.lastSession,
        equals('2026-03-16'),
      );
    });

    test('returns self unchanged when name not found', () {
      final reg = Registry.empty().add(_entry('my-app'));
      final result = reg.touchSession('unknown');
      expect(result.entries, hasLength(1));
    });
  });
}
