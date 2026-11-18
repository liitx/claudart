// class_shapes.dart — the shape of each class: what it holds, and what it
// extends.
//
// A class's *shape* is the set of (type, name) pairs of its instance fields.
// Two classes whose shapes overlap a lot, and that are not related by `extends`,
// are written separately what should be written once in a base class. This
// parses the source (no resolution) so the fields and the inheritance are read
// exactly, not matched with a regular expression.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// A field: its type as written, and its name.
typedef FieldShape = ({String type, String name});

/// A class: where it is, what it extends, and what it holds.
typedef ClassShape = ({
  String name,
  String file,
  String? superclass,
  Set<FieldShape> fields,
});

/// A pair of classes whose shapes overlap and that are not related by
/// inheritance.
typedef ShapePair = ({String first, String second, List<String> sharedFields});

/// The shape of every class declared in [sources] (path -> text).
List<ClassShape> classShapes(Map<String, String> sources) {
  final shapes = <ClassShape>[];
  for (final entry in sources.entries) {
    final unit = parseString(content: entry.value, throwIfDiagnostics: false).unit;
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      final fields = <FieldShape>{};
      for (final member in declaration.members.whereType<FieldDeclaration>()) {
        if (member.isStatic) continue;
        final type = member.fields.type?.toSource() ?? 'dynamic';
        for (final variable in member.fields.variables) {
          fields.add((type: type, name: variable.name.lexeme));
        }
      }
      shapes.add((
        name: declaration.name.lexeme,
        file: entry.key,
        superclass: declaration.extendsClause?.superclass.name2.lexeme,
        fields: fields,
      ));
    }
  }
  return shapes;
}

/// Whether [ancestor] is [descendant] or one of its superclasses.
bool _isAncestor(
  String ancestor,
  String descendant,
  Map<String, ClassShape> byName,
) {
  String? current = descendant;
  final seen = <String>{};
  while (current != null && seen.add(current)) {
    if (current == ancestor) return true;
    current = byName[current]?.superclass;
  }
  return false;
}

/// The pairs of classes that share [minimumShared] or more fields, where the
/// shared fields are at least [minimumOverlap] of the smaller class, and
/// neither class extends the other, so their common properties are written
/// twice.
List<ShapePair> consolidatablePairs(
  Map<String, String> sources, {
  int minimumShared = 3,
  double minimumOverlap = 0.5,
}) {
  final shapes = classShapes(sources);
  final byName = {for (final shape in shapes) shape.name: shape};
  final pairs = <ShapePair>[];
  for (var i = 0; i < shapes.length; i++) {
    for (var j = i + 1; j < shapes.length; j++) {
      final a = shapes[i];
      final b = shapes[j];
      if (_isAncestor(a.name, b.name, byName) ||
          _isAncestor(b.name, a.name, byName)) {
        continue;
      }
      final shared = a.fields.intersection(b.fields);
      final smaller =
          a.fields.length < b.fields.length ? a.fields.length : b.fields.length;
      if (shared.length >= minimumShared &&
          smaller > 0 &&
          shared.length / smaller >= minimumOverlap) {
        pairs.add((
          first: a.name,
          second: b.name,
          sharedFields: [for (final field in shared) field.name]..sort(),
        ));
      }
    }
  }
  return pairs
    ..sort((x, y) => '${x.first}|${x.second}'.compareTo('${y.first}|${y.second}'));
}
