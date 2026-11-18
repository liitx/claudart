# refactor_audit

Read-only measurements that run before and during a methodical refactor
(`docs/methodical_refactor.md`). None of them changes the working tree.

| Script | Question it answers | Make target |
|---|---|---|
| `liveness.sh` | Do the lints, guards, and random-order suite catch the defects they claim to? Seeds each defect in a scratch copy. | `make liveness` |
| `spawn_census.sh` | How many times does each real command spawn git? Runs the compiled CLI in a throwaway project. | `make spawn-census` |

The FileIO call census is a test, not a script:
`test/topology/call_census_test.dart` writes `docs/topology/call_census.md`
(`make topology`).
