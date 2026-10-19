// project_sensitivity.dart — how a project's sensitivity is decided.
//
// The flag is stored twice: `registry.json` (set by `claudart link
// --sensitive`) and `workspace.json`'s session (set by the owner), and they can
// disagree (claudart's own once did: registry false, workspace.json true).
// Sensitivity is a protective setting, so a disagreement never resolves to the
// weaker answer. `claudart link` calls this once and records the result on the
// registry entry; from then on the entry is the only thing anything asks.

/// The sensitivity to record when linking: what was chosen (flag or prompt),
/// kept on if the owner's workspace.json already marks the project sensitive.
bool reconcileSensitivity({
  required bool chosen,
  required bool ownerMarkedSensitive,
}) =>
    chosen || ownerMarkedSensitive;
