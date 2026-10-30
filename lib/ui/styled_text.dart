// styled_text.dart — user text that carries its own colour
//
// A sentence in text/user_text.json can name a style as a placeholder
// (`{dim}`, `{bold}`, `{reset}` ...); the code that prints it supplies none of
// them, they come from here.

import '../generated/user_text.g.dart';
import 'ansi.dart' as ansi;

/// The style placeholders a text may use, by the name it writes them with.
const Map<String, String> ansiStyles = {
  'reset': ansi.reset,
  'bold': ansi.bold,
  'dim': ansi.dim,
  'red': ansi.red,
  'green': ansi.green,
  'yellow': ansi.yellow,
  'magenta': ansi.magenta,
  'cyan': ansi.cyan,
  'white': ansi.white,
  'grey': ansi.grey,
};

extension StyledUserText on UserText {
  /// The text with its style placeholders and the given [values] filled.
  String styled([Map<String, Object?> values = const {}]) =>
      format({...ansiStyles, ...values});
}
