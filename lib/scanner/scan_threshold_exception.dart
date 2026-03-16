/// Thrown when the number of files to scan exceeds the safety threshold.
class ScanThresholdException implements Exception {
  final int filesFound;
  final int threshold;
  final String reason;
  final List<String> suggestions;

  const ScanThresholdException({
    required this.filesFound,
    required this.threshold,
    required this.reason,
    required this.suggestions,
  });

  @override
  String toString() =>
      'ScanThresholdException: found $filesFound files '
      '(threshold $threshold). $reason';
}
