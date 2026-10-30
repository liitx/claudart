// shape_consolidation_test.dart — classes that hold the same properties are
// written once, in a base, not twice.
//
// For every pair of classes in lib/ that share three or more fields (at least
// half of the smaller class), one must extend the other. The fields are read
// from the parsed source (test/helpers/class_shapes.dart), so the pairs are
// exact. The count may only go down, to zero.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/class_shapes.dart';

/// Independent literal: the pairs still written twice. A ratchet to zero.
const _knownConsolidatablePairs = 0;

Map<String, String> _libSources() => {
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          p.normalize(entity.path): entity.readAsStringSync(),
    };

void main() {
  group('consolidatablePairs', () {
    const holder = 'class A { final int x; final int y; final int z; }\n';

    test('finds two unrelated classes holding the same three fields', () {
      final pairs = consolidatablePairs({
        'a.dart': holder,
        'b.dart': 'class B { final int x; final int y; final int z; }\n',
      });
      expect(pairs.map((pair) => '${pair.first}/${pair.second}'), ['A/B']);
      expect(pairs.single.sharedFields, ['x', 'y', 'z']);
    });

    test('passes a class that extends the other', () {
      expect(
        consolidatablePairs({
          'a.dart': holder,
          'b.dart': 'class B extends A { final int x; final int y; '
              'final int z; }\n',
        }),
        isEmpty,
      );
    });

    test('flags two siblings that repeat what their base should hold', () {
      final pairs = consolidatablePairs({
        'a.dart': 'abstract class Base {}\n'
            'class A extends Base { final int x; final int y; final int z; }\n'
            'class B extends Base { final int x; final int y; final int z; }\n',
      });
      expect(pairs.map((pair) => '${pair.first}/${pair.second}'), ['A/B']);
    });

    test('ignores classes sharing fewer than three fields', () {
      expect(
        consolidatablePairs({
          'a.dart': holder,
          'b.dart': 'class B { final int x; final int y; final String q; }\n',
        }),
        isEmpty,
      );
    });

    test('ignores fields that differ in type', () {
      expect(
        consolidatablePairs({
          'a.dart': holder,
          'b.dart': 'class B { final String x; final String y; '
              'final String z; }\n',
        }),
        isEmpty,
      );
    });

    test('does not count static fields', () {
      expect(
        consolidatablePairs({
          'a.dart': 'class A { static const int x = 1; static const int y = 2; '
              'static const int z = 3; }\n',
          'b.dart': 'class B { static const int x = 1; static const int y = 2; '
              'static const int z = 3; }\n',
        }),
        isEmpty,
      );
    });
  });

  group('the code consolidates shared properties', () {
    final sources = _libSources();

    test('the parser sees the classes of lib', () {
      expect(classShapes(sources).length, greaterThan(90));
    });

    test('pairs of classes holding the same fields do not grow', () {
      final pairs = consolidatablePairs(sources);
      expect(
        pairs.length,
        lessThanOrEqualTo(_knownConsolidatablePairs),
        reason: 'two classes hold the same properties and neither extends the '
            'other: put them in a base class. Pairs: '
            '${pairs.map((pair) => '${pair.first}/${pair.second} '
                '(${pair.sharedFields.join(', ')})').join('; ')}',
      );
    });
  });
}
