// environment.dart — the process environment, read in one place
//
// Every variable claudart reads (HOME, the workspace root, the debug switch,
// colour) comes through here, so a test or a future typed reader replaces one
// getter instead of nine call sites.

import 'dart:io';

/// The environment variables of this process.
Map<String, String> get processEnvironment => Platform.environment;
