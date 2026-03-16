import 'package:test/test.dart';
import 'package:claudart/similarity/cosine.dart';

void main() {
  group('tfidfVector', () {
    final corpus = {
      'the': 0.01,
      'and': 0.01,
      'bloc': 0.1,
      'audio': 0.8,
      'repository': 0.7,
    };

    test('produces non-empty vector for known terms', () {
      final v = tfidfVector('audio bloc', corpus);
      expect(v, isNotEmpty);
      expect(v.containsKey('audio'), isTrue);
      expect(v.containsKey('bloc'), isTrue);
    });

    test('unknown terms get IDF 1.0', () {
      final v = tfidfVector('xyzunknown', corpus);
      // tf = 1/1 = 1.0, idf = 1.0 → weight = 1.0
      expect(v['xyzunknown'], closeTo(1.0, 0.001));
    });

    test('common terms get lower weight', () {
      final v = tfidfVector('the the the', corpus);
      // tf = 1.0, idf = 0.01 → very low weight
      expect(v['the']!, lessThan(0.05));
    });

    test('empty string returns empty vector', () {
      expect(tfidfVector('', corpus), isEmpty);
    });

    test('repeated term has correct TF', () {
      final v = tfidfVector('audio audio bloc', corpus);
      final audioWeight = v['audio']!;
      final blocWeight = v['bloc']!;
      // audio appears 2/3 times, bloc 1/3
      // audio weight > bloc weight (both positive idf)
      expect(audioWeight, greaterThan(blocWeight));
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors return 1.0', () {
      final v = {'a': 1.0, 'b': 2.0};
      expect(cosineSimilarity(v, v), closeTo(1.0, 0.001));
    });

    test('orthogonal vectors return 0.0', () {
      final a = {'x': 1.0};
      final b = {'y': 1.0};
      expect(cosineSimilarity(a, b), closeTo(0.0, 0.001));
    });

    test('empty vectors return 0.0', () {
      expect(cosineSimilarity({}, {'a': 1.0}), equals(0.0));
      expect(cosineSimilarity({'a': 1.0}, {}), equals(0.0));
      expect(cosineSimilarity({}, {}), equals(0.0));
    });

    test('partial overlap returns intermediate value', () {
      final a = {'x': 1.0, 'y': 1.0};
      final b = {'x': 1.0, 'z': 1.0};
      final sim = cosineSimilarity(a, b);
      expect(sim, greaterThan(0.0));
      expect(sim, lessThan(1.0));
    });
  });

  group('topKChunks', () {
    final corpus = <String, double>{
      'audio': 0.8,
      'playback': 0.9,
      'bloc': 0.1,
      'network': 0.85,
      'error': 0.6,
    };

    test('returns k most relevant chunks', () {
      final chunks = [
        'audio playback bloc handles audio state',
        'network error handling and retries',
        'general dart coding patterns',
      ];
      final result = topKChunks('audio playback issue', chunks, 2, corpus);
      expect(result, hasLength(2));
      expect(result.first, contains('audio'));
    });

    test('returns all chunks if k > chunks.length', () {
      final chunks = ['audio bloc', 'network error'];
      final result = topKChunks('test', chunks, 5, corpus);
      expect(result.length, equals(chunks.length));
    });

    test('returns empty list for empty chunks', () {
      expect(topKChunks('query', [], 3, corpus), isEmpty);
    });

    test('most relevant chunk appears first', () {
      final chunks = [
        'unrelated content about databases and sql',
        'audio playback bloc and state management',
      ];
      final result = topKChunks('audio bloc playback', chunks, 2, corpus);
      expect(result.first, contains('audio'));
    });
  });
}
