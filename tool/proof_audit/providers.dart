// providers.dart — the matrices the proof audit seeds faults into
//
// One list, read by the runner and by the coverage rule that every decision
// table is either audited here or named as not audited yet.

import 'closure_faults.dart';
import 'command_faults.dart';
import 'fault.dart';
import 'listener_faults.dart';
import 'project_logger_faults.dart';
import 'table_faults.dart';
import 'timed_source_faults.dart';

const auditProviders = <FaultProvider>[
  TransitionTableFaults(),
  ClosureEvidenceFaults(),
  ClaudartCommandFaults(),
  HandoffListenerFaults(),
  TimedSourceFaults(),
  ProjectLoggerFaults(),
];
