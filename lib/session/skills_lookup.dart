// skills_lookup.dart — surfaces the most relevant Root Cause Patterns from
// skills.md for the current handoff's bug, instead of the whole growing
// list. PLAN.md's "Skills + cosine retrieval" backfill entry claimed
// lib/similarity/cosine.dart already powered this — it didn't, until now.

import 'md_io.dart';
import '../similarity/cosine.dart';

/// Splits the `## Root Cause Patterns` section into one chunk per bullet.
List<String> _patternBullets(String skillsContent) {
  final section = readSection(skillsContent, 'Root Cause Patterns');
  return section
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.startsWith('- '))
      .toList();
}

/// Returns the [k] `## Root Cause Patterns` bullets from [skillsContent]
/// most similar to [query] (typically the handoff's Bug text), ranked by
/// TF-IDF cosine similarity over the pattern corpus itself. Empty when
/// skills.md has no patterns yet, or [query] is blank.
List<String> relevantSkillPatterns(
  String skillsContent,
  String query, {
  int k = 3,
}) {
  if (query.trim().isEmpty) return [];
  final chunks = _patternBullets(skillsContent);
  if (chunks.isEmpty) return [];
  final corpus = buildIdfCorpus(chunks);
  return topKChunks(query, chunks, k, corpus);
}
