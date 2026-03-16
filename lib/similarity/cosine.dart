import 'dart:math';

/// Computes a sparse TF-IDF vector for [text] using [idfCorpus].
/// Terms not in corpus receive IDF weight of 1.0.
Map<String, double> tfidfVector(String text, Map<String, double> idfCorpus) {
  final tokens = _tokenize(text);
  if (tokens.isEmpty) return {};

  final tf = <String, int>{};
  for (final t in tokens) {
    tf[t] = (tf[t] ?? 0) + 1;
  }

  final total = tokens.length;
  final vector = <String, double>{};
  for (final entry in tf.entries) {
    final termFreq = entry.value / total;
    final idf = idfCorpus[entry.key] ?? 1.0;
    final weight = termFreq * idf;
    if (weight > 0) vector[entry.key] = weight;
  }
  return vector;
}

/// Computes cosine similarity between two sparse vectors.
/// Returns 0.0 if either vector is empty.
double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0.0;

  double dot = 0.0;
  for (final entry in a.entries) {
    final bVal = b[entry.key];
    if (bVal != null) dot += entry.value * bVal;
  }

  final magA = sqrt(a.values.fold(0.0, (s, v) => s + v * v));
  final magB = sqrt(b.values.fold(0.0, (s, v) => s + v * v));
  if (magA == 0 || magB == 0) return 0.0;

  return dot / (magA * magB);
}

/// Returns the top-[k] most relevant chunks from [chunks] for [query].
/// Uses TF-IDF vectors + cosine similarity. Chunks are plain text strings.
List<String> topKChunks(
  String query,
  List<String> chunks,
  int k,
  Map<String, double> corpus,
) {
  if (chunks.isEmpty) return [];
  final queryVec = tfidfVector(query, corpus);
  final scored = <(double, String)>[];

  for (final chunk in chunks) {
    final chunkVec = tfidfVector(chunk, corpus);
    final score = cosineSimilarity(queryVec, chunkVec);
    scored.add((score, chunk));
  }

  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return scored.take(k).map((e) => e.$2).toList();
}

List<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 1)
      .toList();
}
