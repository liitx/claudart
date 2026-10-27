// construction_funnel_test.dart — an object that has one way to be built is
// built that way everywhere.
//
// Where many call sites built the same object by hand, each could build it
// wrong. One factory builds it, the public generative constructor is gone, and
// this scan fails if a call site writes the constructor again.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A type, and the only file allowed to call its generative constructor.
const _funnels = <String, String>{
  'SessionLogger': 'lib/logging/logger.dart',
};

/// Every Dart file under lib and bin, with its text.
Map<String, String> _sources() => {
      for (final root in ['lib', 'bin'])
        if (Directory(root).existsSync())
          for (final entity in Directory(root).listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart'))
              p.normalize(entity.path): entity.readAsStringSync(),
    };

/// The files that call [type]'s plain constructor, `Type(`, and not a named
/// one (`Type.factory(`).
List<String> constructorCallers(Map<String, String> sources, String type) {
  final call = RegExp('(?<![\\w.])$type\\(');
  return [
    for (final entry in sources.entries)
      if (call.hasMatch(entry.value)) entry.key,
  ]..sort();
}

void main() {
  group('constructorCallers', () {
    test('finds a plain constructor call', () {
      expect(
        constructorCallers({'a.dart': 'final x = Thing(a: 1);'}, 'Thing'),
        ['a.dart'],
      );
    });

    test('ignores a named constructor or factory', () {
      expect(
        constructorCallers({'a.dart': 'final x = Thing.plain();'}, 'Thing'),
        isEmpty,
      );
    });

    test('ignores a longer type name', () {
      expect(
        constructorCallers({'a.dart': 'final x = MyThing();'}, 'Thing'),
        isEmpty,
      );
    });
  });

  group('one construction path', () {
    final sources = _sources();
    _funnels.forEach((type, owner) {
      test('$type is built only inside $owner', () {
        expect(
          constructorCallers(sources, type).toSet().difference({owner}),
          isEmpty,
          reason: '$type is constructed by hand outside $owner: use its '
              'factory constructors instead',
        );
      });
    });
  });
}
