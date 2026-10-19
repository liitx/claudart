// append_lines.dart — a child process for the file_io concurrent-append test:
// appends [count] distinct lines to the file at args[0], as writer args[1].

import 'package:claudart/file_io.dart';

void main(List<String> args) {
  final path = args[0];
  final writer = args[1];
  final count = int.parse(args[2]);
  for (var i = 0; i < count; i++) {
    const RealFileIO().append(path, 'w$writer-$i ${'x' * 120}\n');
  }
}
