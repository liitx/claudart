// log_protection.dart — how a logger treats text that could name the owner's
// code.
//
// Three cases, one type each, so a logger cannot be built "sensitive" without
// saying how it protects the text. Before this, a logger held a
// `sensitivityMode` bool and an optional token map, and 17 call sites built it
// by hand: only 3 passed the map, so for a sensitive project most logs were
// written unabstracted.

import '../sensitivity/abstractor.dart';
import '../sensitivity/detector.dart';
import '../sensitivity/token_map.dart';

/// Written in place of text a logger cannot safely write.
const String redactedLogText = '[redacted: the token map is unreadable]';

/// How a logger protects free text before it reaches a log file.
sealed class LogProtection {
  const LogProtection();

  /// Whether the project being logged is sensitive.
  bool get isSensitive;

  /// [text] as it may be written to a log.
  String protect(String text);

  /// [stackTrace] as it may be written to a log, or null when it must not be.
  String? protectStack(String stackTrace);
}

/// A project that is not sensitive: text is written as it is.
final class PlainLogging extends LogProtection {
  const PlainLogging();

  @override
  bool get isSensitive => false;

  @override
  String protect(String text) => text;

  @override
  String? protectStack(String stackTrace) => stackTrace;
}

/// A sensitive project: identifiers in the text are replaced using [tokenMap].
final class AbstractedLogging extends LogProtection {
  const AbstractedLogging(this.tokenMap);

  final TokenMap tokenMap;

  @override
  bool get isSensitive => true;

  @override
  String protect(String text) =>
      abstractor.abstract(text, tokenMap, defaultDetector);

  @override
  String? protectStack(String stackTrace) => protect(stackTrace);
}

/// A sensitive project whose token map cannot be read: no free text is written
/// at all, only what the log records by type.
final class LabelOnlyLogging extends LogProtection {
  const LabelOnlyLogging();

  @override
  bool get isSensitive => true;

  @override
  String protect(String text) => redactedLogText;

  @override
  String? protectStack(String stackTrace) => null;
}
