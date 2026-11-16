// overrides.dart — a scratch copy lives under /tmp, so a relative path in
// pubspec_overrides.yaml (a sibling checkout such as ../dartrix) must point at
// the original place before the copy resolves its packages.

import 'package:path/path.dart' as p;

/// [yaml] with every `path: <relative>` made absolute against [fromRoot], the
/// directory the overrides file was written for. Absolute paths are left alone.
String absolutizeOverridePaths(String yaml, String fromRoot) =>
    yaml.replaceAllMapped(
      RegExp(r'^([ \t]*path:[ \t]*)(\S+)[ \t]*$', multiLine: true),
      (m) => '${m[1]}${p.normalize(p.absolute(fromRoot, m[2]!))}',
    );
