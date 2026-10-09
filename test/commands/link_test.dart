import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:claudart/commands/link.dart';
import 'package:claudart/registry.dart';
import 'package:claudart/paths.dart';
import 'package:claudart/codegen/dependency_config_codegen.dart';
import '../helpers/mocks.dart';

const _projectRoot = '/projects/my-app';
const _projectName = 'my-app';

class _ExitException implements Exception {
  final int code;
  const _ExitException(this.code);
}

Never _throwExit(int code) => throw _ExitException(code);

MemoryFileIO _emptyIO() => MemoryFileIO();

void main() {
  group('link — new project registration', () {
    test('adds entry to registry', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false, // no sensitivity
        exitFn: _throwExit,
      );
      final registry = Registry.load(io: io);
      expect(registry.findByName(_projectName), isNotNull);
    });

    test('entry has correct projectRoot', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.projectRoot, equals(_projectRoot));
    });

    test('entry workspacePath resolves to workspaceFor(name)', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.workspacePath, equals(workspaceFor(_projectName)));
    });

    test('creates workspace directory', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.dirExists(workspaceFor(_projectName)), isTrue);
    });

    test('creates .claude symlink in project root', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isTrue);
    });

    test('adds .claude to .gitignore when not present', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, contains('.claude'));
    });

    test('does not duplicate .claude in .gitignore', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '.claude\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });
  });

  group('link — sensitivity mode', () {
    test('sensitivityMode false when user declines', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.sensitivityMode, isFalse);
    });

    test('sensitivityMode true when user accepts', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => true,
        exitFn: _throwExit,
      );
      final entry = Registry.load(io: io).findByName(_projectName)!;
      expect(entry.sensitivityMode, isTrue);
    });
  });

  group('link — re-linking existing project', () {
    test('does not create duplicate registry entry', () async {
      final io = _emptyIO();
      // Register once.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      // Re-link.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false, // decline change, decline enable
        exitFn: _throwExit,
      );
      final entries = Registry.load(io: io).entries;
      expect(entries.where((e) => e.name == _projectName), hasLength(1));
    });

    test('preserves createdAt on re-link', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final original =
          Registry.load(io: io).findByName(_projectName)!.createdAt;

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final updated = Registry.load(io: io).findByName(_projectName)!.createdAt;
      expect(updated, equals(original));
    });

    test('replaces existing symlink', () async {
      final io = _emptyIO();
      // Plant a stale symlink.
      io.links.add(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      // Symlink should still exist (recreated).
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isTrue);
    });

    test('can update sensitivityMode on re-link', () async {
      final io = _emptyIO();
      // First link — sensitivity off.
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(
        Registry.load(io: io).findByName(_projectName)!.sensitivityMode,
        isFalse,
      );

      // Re-link — accept change, enable sensitivity.
      var confirmCall = 0;
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) {
          confirmCall++;
          // Q1: "Change sensitivity mode?" → yes
          // Q2: "Enable sensitivity mode?" → yes
          return true;
        },
        exitFn: _throwExit,
      );
      expect(
        Registry.load(io: io).findByName(_projectName)!.sensitivityMode,
        isTrue,
      );
      // confirmFn was called at least twice: once to change, once to enable.
      expect(confirmCall, greaterThanOrEqualTo(2));
    });

    test('skips symlink when .claude is a real directory', () async {
      final io = _emptyIO();
      // Pre-create .claude as a real directory in project root.
      io.createDir(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      // Registration should succeed.
      final entry = Registry.load(io: io).findByName(_projectName);
      expect(entry, isNotNull);
      expect(entry!.projectRoot, equals(_projectRoot));

      // .claude directory should still exist (not replaced).
      expect(io.dirExists(p.join(_projectRoot, '.claude')), isTrue);

      // No symlink should be created.
      expect(io.linkExists(p.join(_projectRoot, '.claude')), isFalse);

      // Workspace directory should still be created.
      expect(io.dirExists(workspaceFor(_projectName)), isTrue);
    });

    test('does not add .claude to .gitignore when it is a real directory',
        () async {
      final io = _emptyIO();
      io.createDir(p.join(_projectRoot, '.claude'));

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, isNot(contains('.claude')));
    });

    test('syncs command templates into a real .claude/commands/ directory',
        () async {
      final io = _emptyIO();
      final realCmdsDir = p.join(_projectRoot, '.claude', 'commands');
      // Pre-create .claude as a real directory with a stale legacy command
      // file — carries the marker, so it's a stale claudart template, not
      // user content, and should still be synced.
      io.createDir(realCmdsDir);
      io.write(p.join(realCmdsDir, 'debug.md'),
          'stale content\nclaudart: generated\n');

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      // The legacy filename is kept (not deleted) but its content is synced —
      // not left stale.
      expect(io.fileExists(p.join(realCmdsDir, 'debug.md')), isTrue);
      expect(io.read(p.join(realCmdsDir, 'debug.md')),
          isNot(equals('stale content\nclaudart: generated\n')));

      // The suffixed filename should now exist with identical content — 1:1.
      final suffixed = io.read(p.join(realCmdsDir, 'debug-$_projectName.md'));
      expect(suffixed, equals(io.read(p.join(realCmdsDir, 'debug.md'))));
    });

    test('does not clobber a user command with the same name', () async {
      final io = _emptyIO();
      final realCmdsDir = p.join(_projectRoot, '.claude', 'commands');
      io.createDir(realCmdsDir);
      // The user's own suggest.md — no claudart marker, must survive.
      io.write(p.join(realCmdsDir, 'suggest.md'), '# My own suggest command\n');

      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      expect(
        io.read(p.join(realCmdsDir, 'suggest.md')),
        equals('# My own suggest command\n'),
      );
    });
  });

  group('link — .gitignore edge cases', () {
    test('creates .gitignore when missing', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.fileExists(p.join(_projectRoot, '.gitignore')), isTrue);
    });

    test('appends to existing .gitignore without clobbering', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '*.log\nbuild/\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect(gitignore, contains('*.log'));
      expect(gitignore, contains('.claude'));
    });

    test('recognises .claude/ (trailing slash) as already present', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '.claude/\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });

    test('recognises /.claude (leading slash) as already present', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, '.gitignore'), '/.claude\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final gitignore = io.read(p.join(_projectRoot, '.gitignore'));
      expect('.claude'.allMatches(gitignore).length, equals(1));
    });
  });

  group('link — CLAUDE.md regeneration', () {
    test('creates CLAUDE.md from scratch when none exists', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final claudeMd = io.read(claudeMdPathFor(_projectRoot));
      expect(claudeMd,
          contains('## Generated by claudart link | Project: my-app'));
    });

    test('preserves hand-written content above the marker, replaces below it',
        () async {
      final io = _emptyIO();
      io.write(claudeMdPathFor(_projectRoot), '''# my-app — CLAUDE.md

## Profile

Hand-written profile section — must survive.

---

## Generated by claudart link | Project: my-app
> stale content that must be replaced

## Workflow protocol
stale
''');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final claudeMd = io.read(claudeMdPathFor(_projectRoot));
      expect(
          claudeMd, contains('Hand-written profile section — must survive.'));
      expect(claudeMd, isNot(contains('stale content that must be replaced')));
      expect(claudeMd, contains('Never push to remote'));
    });

    test(
        'appends the generated section when no marker is found in an existing file',
        () async {
      final io = _emptyIO();
      io.write(claudeMdPathFor(_projectRoot), '''# my-app — CLAUDE.md

## Profile

A hand-written CLAUDE.md that pre-dates this feature — no marker heading.
''');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final claudeMd = io.read(claudeMdPathFor(_projectRoot));
      expect(claudeMd, contains('no marker heading.'));
      expect(claudeMd,
          contains('## Generated by claudart link | Project: my-app'));
    });
  });

  group('link — README Roadmap splice', () {
    // Regression: the marker regex originally used `\z` for "end of
    // input," which Dart/JS regex silently treats as a literal lowercase
    // `z` (there is no `\z` metacharacter in ECMAScript-flavored regex).
    // A roadmap.json row containing a lowercase `z` (e.g. real content
    // like "zedup-side") made the splice stop mid-row instead of at the
    // real end of the Roadmap block, corrupting README.md. This row is
    // deliberately chosen to contain a `z` before the section end.
    const readmePath = '$_projectRoot/README.md';
    const roadmapJsonPath = '$_projectRoot/roadmap.json';

    test(
        'splices roadmap.json rows into the marker, even when the '
        'existing README content contains a lowercase "z"', () async {
      final io = _emptyIO();
      io.write(roadmapJsonPath, '''
{"rows": [{"phase": "1", "scope": "new row", "status": "shipped"}]}
''');
      // The existing content BETWEEN the marker and the real "---"
      // boundary contains a lowercase "z" ("zedup-side") — this is what
      // the marker regex matches against before substitution. The `\z`
      // bug stopped matching right here instead of at the real boundary.
      io.write(readmePath, '''
# my-app

## Roadmap

<!-- claudart:link:roadmap -->
<details>
<summary><strong>Old</strong></summary>

| Phase | Scope | Status |
|---|---|---|
| 1 | old row (zedup-side) | shipped |

</details>

---

## Next section
Untouched.
''');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final readme = io.read(readmePath);
      expect(readme, contains('| 1 | new row | shipped |'));
      expect(readme, isNot(contains('old row')));
      expect(readme, contains('## Next section\nUntouched.'));
      // The bug's exact symptom: leftover fragments of the old block
      // leaking past </details> because the match ended mid-row instead
      // of at the real "---" boundary.
      expect(readme.split('</details>').length, equals(2));
    });

    test('leaves README.md untouched when roadmap.json is absent', () async {
      final io = _emptyIO();
      io.write(readmePath, '''
## Roadmap

<!-- claudart:link:roadmap -->
old content
''');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.read(readmePath), contains('old content'));
    });
  });

  group('link — dependency-config codegen', () {
    test('regenerates lib/generated/dependency_config.g.dart from pubspec.yaml', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), '''
name: my_app
dependencies:
  dartrix:
    git:
      url: https://github.com/liitx/dartrix.git
''');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final generated = io.read(p.join(_projectRoot, kDependencyConfigGeneratedRelativePath));
      expect(generated, contains('const bool usesDartrix = true;'));
    });

    test('usesDartrix is false when pubspec.yaml has no dartrix dependency', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), 'name: my_app\n');
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      final generated = io.read(p.join(_projectRoot, kDependencyConfigGeneratedRelativePath));
      expect(generated, contains('const bool usesDartrix = false;'));
    });

    test('skips codegen entirely when the project has no pubspec.yaml', () async {
      final io = _emptyIO();
      await runLink(
        [_projectName],
        io: io,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      expect(io.fileExists(p.join(_projectRoot, kDependencyConfigGeneratedRelativePath)), isFalse);
    });

    setUpAll(() => registerFallbackValue(fakeResult('')));

    test('does NOT recompile by default, even when bin/<name>.dart exists and content changed', () async {
      // The real safety case this guards: linking claudart or zedup's own
      // repo (self-linking) must never silently overwrite the installed
      // ~/bin/<name> with whatever's currently checked out, including
      // uncommitted WIP. Recompiling is opt-in (--recompile), not a
      // default side effect of link.
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), 'name: $_projectName\n');
      io.write(p.join(_projectRoot, 'bin', '$_projectName.dart'), 'void main() {}\n');
      final runner = MockProcessRunner();

      await runLink(
        [_projectName],
        io: io,
        runner: runner,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      verifyNever(() => runner.run(any(), any(), workingDirectory: any(named: 'workingDirectory')));
      expect(
        io.fileExists(p.join(_projectRoot, kDependencyConfigGeneratedRelativePath)),
        isTrue,
        reason: 'the generated config itself is always written, regardless of --recompile',
      );
    });

    test('recompiles when --recompile is passed and bin/<name>.dart exists and content changed', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), 'name: $_projectName\n');
      io.write(p.join(_projectRoot, 'bin', '$_projectName.dart'), 'void main() {}\n');
      final runner = MockProcessRunner();
      when(() => runner.run(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => fakeResult(''));

      await runLink(
        [_projectName, '--recompile'],
        io: io,
        runner: runner,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      final captured = verify(() => runner.run(
            captureAny(),
            captureAny(),
            workingDirectory: captureAny(named: 'workingDirectory'),
          )).captured;
      expect(captured[0], 'dart');
      expect(captured[1], contains('compile'));
      expect(captured[1], contains(p.join('bin', '$_projectName.dart')));
      expect(captured[2], _projectRoot);
    });

    test('--recompile does not recompile when the project has no bin/<name>.dart entrypoint', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), 'name: $_projectName\n');
      final runner = MockProcessRunner();

      await runLink(
        [_projectName, '--recompile'],
        io: io,
        runner: runner,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      verifyNever(() => runner.run(any(), any(), workingDirectory: any(named: 'workingDirectory')));
    });

    test('--recompile does not recompile on a second link when nothing changed', () async {
      final io = _emptyIO();
      io.write(p.join(_projectRoot, 'pubspec.yaml'), 'name: $_projectName\n');
      io.write(p.join(_projectRoot, 'bin', '$_projectName.dart'), 'void main() {}\n');
      final runner = MockProcessRunner();
      when(() => runner.run(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .thenAnswer((_) async => fakeResult(''));

      await runLink(
        [_projectName, '--recompile'],
        io: io,
        runner: runner,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );
      await runLink(
        [_projectName, '--recompile'],
        io: io,
        runner: runner,
        projectRootOverride: _projectRoot,
        confirmFn: (_) => false,
        exitFn: _throwExit,
      );

      verify(() => runner.run(any(), any(), workingDirectory: any(named: 'workingDirectory')))
          .called(1);
    });
  });

  group('link — sensitivity flags and end of input', () {
    Future<void> link(MemoryFileIO io, List<String> args, {bool? Function(String)? askFn}) => runLink(
          args,
          io: io,
          projectRootOverride: _projectRoot,
          askFn: askFn,
          exitFn: _throwExit,
        );

    bool? neverAsked(String q) => throw StateError('should not have been asked: $q');

    Matcher exitsWith(int code) =>
        throwsA(isA<_ExitException>().having((e) => e.code, 'code', code));

    test('--sensitive turns it ON without asking', () async {
      final io = _emptyIO();
      await link(io, [_projectName, '--sensitive'], askFn: neverAsked);
      expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isTrue);
    });

    test('--no-sensitive turns it OFF without asking', () async {
      final io = _emptyIO();
      await link(io, ['--no-sensitive', _projectName], askFn: neverAsked);
      expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isFalse);
    });

    test('a flag is never taken as the project name', () async {
      final io = _emptyIO();
      await link(io, ['--sensitive'], askFn: neverAsked);
      final names = Registry.load(io: io).entries.map((e) => e.name).toList();
      expect(names, isNot(contains('--sensitive')));
      expect(names, hasLength(1));
    });

    test('both flags together is an error and registers nothing', () async {
      final io = _emptyIO();
      await expectLater(link(io, [_projectName, '--sensitive', '--no-sensitive'], askFn: neverAsked), exitsWith(1));
      expect(Registry.load(io: io).isEmpty, isTrue);
    });

    test('an unknown option is an error and registers nothing', () async {
      final io = _emptyIO();
      await expectLater(link(io, [_projectName, '--bogus'], askFn: neverAsked), exitsWith(1));
      expect(Registry.load(io: io).isEmpty, isTrue);
    });

    test('answering yes and no at the prompt behaves as before', () async {
      final yes = _emptyIO();
      await link(yes, [_projectName], askFn: (_) => true);
      expect(Registry.load(io: yes).findByName(_projectName)!.sensitivityMode, isTrue);
      final no = _emptyIO();
      await link(no, [_projectName], askFn: (_) => false);
      expect(Registry.load(io: no).findByName(_projectName)!.sensitivityMode, isFalse);
    });

    test('end of input on a new project aborts with exit 1 and writes nothing', () async {
      final io = _emptyIO();
      await expectLater(link(io, [_projectName], askFn: (_) => null), exitsWith(1));
      expect(Registry.load(io: io).isEmpty, isTrue);
      expect(io.files, isEmpty);
    });

    group('re-linking an existing project', () {
      Future<MemoryFileIO> linkedWith({required bool sensitive}) async {
        final io = _emptyIO();
        await link(io, [_projectName], askFn: (_) => sensitive);
        return io;
      }

      test('end of input at "Change sensitivity mode?" aborts and keeps the setting', () async {
        final io = await linkedWith(sensitive: true);
        await expectLater(link(io, [_projectName], askFn: (_) => null), exitsWith(1));
        expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isTrue);
      });

      test('end of input at "Enable sensitivity mode?" aborts and keeps the setting', () async {
        final io = await linkedWith(sensitive: true);
        var calls = 0;
        await expectLater(
          link(io, [_projectName], askFn: (_) => ++calls == 1 ? true : null),
          exitsWith(1),
        );
        expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isTrue);
      });

      test('--no-sensitive flips an ON project to OFF without asking', () async {
        final io = await linkedWith(sensitive: true);
        await link(io, [_projectName, '--no-sensitive'], askFn: neverAsked);
        expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isFalse);
      });

      test('declining to change keeps the current setting', () async {
        final io = await linkedWith(sensitive: true);
        await link(io, [_projectName], askFn: (_) => false);
        expect(Registry.load(io: io).findByName(_projectName)!.sensitivityMode, isTrue);
      });
    });
  });
}
