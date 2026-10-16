# Plan: dartrix workspace

Gap analysis 2026-10-16. dartrix's own suite passes (93). claudart pins
dartrix main at 14cbc3e (PARADIGMS v0.5.0). The local checkout is on the
unmerged docs/four-roles-testing-paradigm branch (5c23dfe, PARADIGMS v0.6.0:
four-role testing convention, enum/sealed pairing, dependency policy), so the
law claudart reads and the law the owner is editing differ.

## What fails

- v0.6.0 is not on main, so claudart (and any consumer) enforces v0.5.0.
- dartrix's CLAUDE.md has no claudart workflow protocol, knowledge base or
  hooks; Claude Code in dartrix is not bound to the claudart flow.
- Fixture strings in BranchType-related tests are bare; PARADIGMS' own consts
  dimension forbids that.

## Steps

1. Decide v0.6.0: review and merge docs/four-roles-testing-paradigm to main.
   Check: claudart `pub upgrade` resolves it; claudart's CLAUDE.md pointer to
   PARADIGMS.md still resolves.
2. Apply the new four-role testing convention to claudart's test layout only
   where PARADIGMS says `enforce` (new code), not as a mass rewrite.
3. Replace the bare fixture strings with typed values; run dartrix's own
   matrix gaps check.
4. Bind Claude Code: `claudart link` on a branch (same artifacts as zedup).
5. Keep the matrix API stable: claudart's test/matrix/* and claudart_lints
   import it; run `dart test test/matrix` in claudart after every dartrix bump.
