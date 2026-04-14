---
archived: 2026-04-13
source: README_v1.md (repo root)
superseded_by: README.md — complete rewrite with architecture diagram, expanded
  commands table, sensitivity/privacy section, workspace structure, v1 workflow
---

README_v1.md was the initial public documentation for claudart. It covered the
same core workflow (setup → /suggest → /save → /debug → teardown) but with a
table-based, more concise structure.

Full content is preserved in git history:
  git show HEAD~:README_v1.md

Key differences from README.md:
- No architecture diagram (lib/ module graph)
- No sensitivity/privacy abstraction section
- No workspace file tree
- No preflight sync check documentation
- No test command coverage (test_X.md system)
- Shorter commands reference table
- No token efficiency comparison
