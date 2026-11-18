// environment.dart — the process environment, read in one place
//
// Every variable claudart reads (HOME, the workspace root, the debug switch,
// colour) comes through here, so a test or a future typed reader replaces one
// getter instead of nine call sites.

import 'dart:io';

/// The environment variables of this process.
Map<String, String> get processEnvironment => Platform.environment;

/// The name of the variable that holds the home directory.
const String homeEnvVar = 'HOME';

/// The home directory in [environment], or null when it is unset or empty.
String? homeDirectoryFrom(Map<String, String> environment) {
  final value = environment[homeEnvVar];
  return value == null || value.isEmpty ? null : value;
}

/// The home directory of this process, or null when it is unset or empty.
String? get homeDirectory => homeDirectoryFrom(processEnvironment);
