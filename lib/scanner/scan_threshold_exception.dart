import '../errors/claudart_exception.dart';
import '../errors/failure_type.dart';

/// Thrown when the number of files to scan exceeds the safety threshold.
class ScanThresholdException extends ClaudartException {
  final int filesFound;
  final int threshold;
  final String reason;
  final List<String> suggestions;

  ScanThresholdException({
    required this.filesFound,
    required this.threshold,
    required this.reason,
    required this.suggestions,
  }) : super(FailureType.scanThresholdExceeded);

  @override
  String toString() =>
      'ScanThresholdException: found $filesFound files '
      '(threshold $threshold). $reason';
}
