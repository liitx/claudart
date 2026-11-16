# Template: a timed source

Where claudart records how long something took, read back as typed records. This is
how to add one, and the proof it needs before it is trusted. Written 2026-11-16 with
the first four sources; `test/logging/timed_source_test.dart` fails when a source is
added without being named here.

## Why this exists (spec before code)

`performance.md` was removed on 2026-11-06 (methodical_refactor S9): every log row
that has a duration already records it. What was missing was one typed way to read
those durations, and a proof that every log's timing is either read or explicitly
not. So performance is verified by deriving it from the logs, never by a second
file.

## The four required members of a `TimedSource` variant

| Member | Answers |
|---|---|
| `logFile` | which log holds its rows |
| `qualifies` | which rows of that log are this source's (an outcome row of `interactions` is not a run) |
| `rawDurationOf` | where on the row the duration sits |
| `labelOf` | what the row is about (the command, the gate, the step, the proof) |

All four are exhaustive switches over the enum. No default arm: a new variant does
not compile until it answers all four.

## The sources

| Source | Log | A row qualifies when | Duration | Label |
|---|---|---|---|---|
| `commandRun` | `interactions` | `rowKind` is `run` | `durationMs` | `command` |
| `gateRun` | `gates` | always | `durationMs` | `gate` |
| `stepCompleted` | `steps` | `kind` is `agentCompleted` | `detail` | `stepId` |
| `proofFault` | `proofs` | always | `durationMs` | `proof` |

Logs with no timing, stated and proven row by row: `errors`, `transitions`,
`models`, `planner`.

## Steps to add a source

1. Name the variant and answer the four members (the compiler lists what is missing).
2. Add a row to the sources table above.
3. Write the row with the real writer in the matrix of
   `test/logging/timed_source_test.dart` and state the duration and label it must read
   back as, by hand, not from the reader.
4. Add the non-qualifying row that must read as nothing.
5. If the log was in the untimed set, take it out; the test fails until you do.
6. `make mutation-test` on the file, and the gate, as for any `lib/` change.

## What a gap is

A row that qualifies but has no usable duration is returned as a gap with its reason
(`durationMissing`, `durationNotWholeNumber`, `durationNegative`, `labelMissing`),
never counted as zero and never dropped. `claudart status` says how many there are.

## Known, not covered

`scanDuration` on a scan's outcome row is a fractional number with no recorded unit,
so it is not read as a duration; it is a gap in the spec, not in this code.
