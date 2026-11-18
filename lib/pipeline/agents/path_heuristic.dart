// path_heuristic.dart — classifies file paths into design vs. logic surfaces.
//
// Used by the planner to decide whether a scoped task should route through
// the GuiDesignAgent (AgentFlow.guiDesign). The classification is
// enum-driven so callers can iterate over every variant and reason about
// thresholds without bare strings sprinkled at decision sites.
//
// Substring tables live as enum getters (`directoryHints`,
// `basenameHints`) so every pattern that influences routing has one
// home. Per the no-regex doctrine from slice 1, lookups use
// `String.contains` / `endsWith` over the lower-cased path —
// `RegExp` was previously needed to anchor the basename match, but
// extracting the basename via `lastIndexOf('/')` is cheaper and
// allocation-free.

const String _dartExtension = '.dart';

/// Variant tags a scoped file lands in. The planner uses majority vote
/// across the input scope: if ≥ N files land in a design-surface variant
/// the work is routed through guiDesign.
///
/// Variant order doubles as match priority: [classifyPath] iterates
/// `values` and returns the first hit, so `lib/ui/wave_painter.dart`
/// resolves to [guiPainter] (painter wins over ui) — preserving the
/// pre-enum-driven precedence.
enum DesignSurface {
  /// `**/widgets/**/*.dart` — Flutter/Dart widget definitions.
  guiWidget(
    isDesignSurface: true,
    tag: 'widget',
    directoryHints: ['/widgets/'],
    basenameHints: [],
  ),

  /// `**/painters/**/*.dart` or basename containing `painter` — custom
  /// paint logic. Higher priority than [guiUi] so a painter that lives
  /// under `lib/ui/` still routes here.
  guiPainter(
    isDesignSurface: true,
    tag: 'painter',
    directoryHints: ['/painters/'],
    basenameHints: ['painter'],
  ),

  /// `**/ui/**/*.dart` — generic UI layer.
  guiUi(
    isDesignSurface: true,
    tag: 'ui',
    directoryHints: ['/ui/'],
    basenameHints: [],
  ),

  /// `**/theme*/**/*.dart`, `**/style*/**/*.dart`, or basename
  /// containing `theme` / `style` — design tokens.
  guiTheme(
    isDesignSurface: true,
    tag: 'theme',
    directoryHints: ['/theme/', '/style/'],
    basenameHints: ['theme', 'style'],
  ),

  /// Any other path — non-design surface.
  logic(
    isDesignSurface: false,
    tag: 'logic',
    directoryHints: [],
    basenameHints: [],
  );

  const DesignSurface({
    required this.isDesignSurface,
    required this.tag,
    required this.directoryHints,
    required this.basenameHints,
  });

  /// Whether this surface counts toward "this work is design-heavy".
  final bool isDesignSurface;

  /// Short label for log lines and the planner JSONL.
  final String tag;

  /// Directory-name substrings (slash-bounded, lower-case) that signal
  /// this surface. Match wins regardless of basename.
  final List<String> directoryHints;

  /// Basename substrings (lower-case) that signal this surface when
  /// the file ends in `.dart`. Lets `wave_painter.dart` outside a
  /// `/painters/` directory still route to [guiPainter].
  final List<String> basenameHints;
}

/// Classifies a single path into a [DesignSurface] variant. Iterates
/// variants in declaration order — first match wins — so adding a new
/// surface only requires placing it at the right priority slot.
DesignSurface classifyPath(String path) {
  final lower    = path.toLowerCase();
  final basename = _basenameOf(lower);
  final hasDartExtension = basename.endsWith(_dartExtension);
  for (final surface in DesignSurface.values) {
    if (surface == DesignSurface.logic) continue;
    if (surface.directoryHints.any(lower.contains)) return surface;
    if (hasDartExtension && surface.basenameHints.any(basename.contains)) {
      return surface;
    }
  }
  return DesignSurface.logic;
}

/// Whether the supplied paths warrant routing to the GuiDesignAgent.
/// Threshold: at least half the paths classify as a design surface.
bool isDesignScope(List<String> paths) {
  if (paths.isEmpty) return false;
  final design = paths.where((p) => classifyPath(p).isDesignSurface).length;
  return design * 2 >= paths.length;
}

/// Returns the segment after the last `/` (or the whole input when
/// the path has no separators). Allocation-free for the no-slash case.
String _basenameOf(String path) {
  final lastSlash = path.lastIndexOf('/');
  return lastSlash < 0 ? path : path.substring(lastSlash + 1);
}
