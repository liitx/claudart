// mermaid_page.dart — a web page that draws Mermaid diagrams
//
// The diagrams are text in `pre.mermaid` blocks and the page loads Mermaid to
// draw them when it is opened. What a log or a test wrote is escaped, so it
// cannot become markup. Shared by the run page and the traced-checks page.

const String _mermaidModule =
    'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// A diagram under a heading.
typedef MermaidSection = ({String heading, String diagram});

/// The page: [heading] over a heading and a diagram for each of [sections], or
/// [emptyText] when there are none.
String renderMermaidHtml({
  required String pageTitle,
  required String heading,
  required String emptyText,
  required List<MermaidSection> sections,
}) {
  final body = StringBuffer();
  if (sections.isEmpty) {
    body.writeln('<p>${_escapeHtml(emptyText)}</p>');
  }
  for (final section in sections) {
    body
      ..writeln('<h2>${_escapeHtml(section.heading)}</h2>')
      ..writeln('<pre class="mermaid">')
      ..write(_escapeHtml(section.diagram))
      ..writeln('</pre>');
  }
  return '''<!doctype html>
<meta charset="utf-8">
<title>${_escapeHtml(pageTitle)}</title>
<style>body{font-family:system-ui,sans-serif;margin:2rem}h2{margin-top:2.5rem}</style>
<h1>${_escapeHtml(heading)}</h1>
$body<script type="module">
import mermaid from '$_mermaidModule';
mermaid.initialize({startOnLoad: true});
</script>
''';
}
