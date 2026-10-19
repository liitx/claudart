// increment_counter.dart — a child process for the withExclusiveLock test:
// adds 1 to the integer in the file at args[0], args[1] times, each as a
// read-modify-write under the lock (or without it when args[2] is 'nolock',
// to show the loss the lock prevents).

import 'dart:io';

import 'package:claudart/file_io.dart';

void main(List<String> args) {
  final path = args[0];
  final times = int.parse(args[1]);
  final locked = args[2] != 'nolock';
  const io = RealFileIO();
  void bump() {
    final current = int.tryParse(io.read(path).trim()) ?? 0;
    io.write(path, '${current + 1}');
  }

  for (var i = 0; i < times; i++) {
    locked ? io.withExclusiveLock(path, bump) : bump();
  }
  exit(0);
}
