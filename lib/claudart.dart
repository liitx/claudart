// claudart.dart — public library barrel
//
// Exports the pipeline engine and session types for consumers (e.g. zedup).
// Import with: import 'package:claudart/claudart.dart';

export 'paths.dart' show handoffFileName, skillsFileName, archivesDirName, archiveIndexFileName, flowCheckpointFileName, parseWorkspaceDirFromStatusOutput, handoffPathFor;
export 'providers/agent_provider.dart';
export 'registry.dart' show Registry, RegistryEntry;
export 'md_io.dart' show readSection, readStatus, updateSection, updateStatus, parseScopeFiles;
export 'pipeline/agent_model.dart';
export 'pipeline/agent_flow.dart';
export 'pipeline/agents/confirmation.dart';
export 'pipeline/step_status.dart';
export 'pipeline/pipeline_event.dart';
export 'pipeline/agent_response.dart';
export 'pipeline/state_hue.dart';
export 'pipeline/agent_step.dart';
export 'pipeline/step_mode.dart';
export 'pipeline/flows/suggest_steps.dart';
export 'pipeline/flows/debug_steps.dart';
export 'pipeline/flows/flow_steps.dart';
export 'pipeline/pipeline_context.dart';
export 'pipeline/pipeline_slot.dart';
export 'pipeline/pipeline_executor.dart';
export 'pipeline/step_result.dart';
export 'pipeline/claude_session.dart' show newClaudeSessionId;
export 'pipeline/claudart_surface.dart';
export 'pipeline/event_response_map.dart';
export 'pipeline/step_route.dart';
export 'pipeline/usage.dart';
export 'pipeline/xml_tags.dart';
export 'session/archive_entry.dart';
export 'session/session_state.dart';
export 'session/pending_confirmation.dart';
export 'session/run_mode.dart';
export 'workspace/workspace_index.dart';
export 'version.dart';
