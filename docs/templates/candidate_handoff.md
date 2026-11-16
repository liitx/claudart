# Template: handing a candidate to an agent

For an agent that is asked to test, extend or rely on a claim. It lists what to give
the agent and what it must give back, so it spends its context on the claim and not
on finding the method. The lookup is `docs/candidacy/index.md` (one block per
postulate: statement, spec, mocks, coverage, boundary, confidence, history,
evidence). The method is `docs/candidacy.md`; read only its procedure section.

## Give the agent

- The candidate id and its block from the index.
- The axioms it may rely on: the ones listed under `axiom` in the index (none yet).
  An agent relies on nothing that is not an axiom; a `proven` candidate is evidence,
  not a premise.
- The spec section it is scoped to. A claim is never wider than its spec.
- The mock dataset version, and the evidence it may re-run.

## The agent returns an entry with these fields

| Field | Required | Meaning |
|---|---|---|
| `candidateId` | yes | which postulate |
| `status` | yes | `candidate`, `underTest`, `proven`, `bounded`, `refuted` or `axiom` |
| `specReference` | yes | `path :: text` of the spec it is scoped to |
| `mockDatasetVersion` | yes | the mocks the proof ran on |
| `evidence` | yes | `path :: text` citations that exist |
| `justification` | yes | what was run and found, plainly |
| `variantsInSpec` | yes | every variant the spec names |
| `variantsCovered` | yes | the ones the tests cover; a partial proof is `bounded` |
| `audit` | yes | the Phase 0 outcome of each check; no promotion on mocks that did not pass |
| `boundary` | no | the highest complexity at which it holds |
| `threshold` | no | for an axiom: the confidence it must reach, justified |
| `factors` | no | measured boundary, topology reach, impact |

## Rules the agent is held to

No promotion without a ledger entry. Nothing proven if Phase 0 did not pass for its
mocks. New proof machinery goes to dartrix, usage to claudart. Every assumption is
logged. The gate (`tool/gate.sh`) runs before a commit.
