# PR Message Templates

This directory contains templates for creating well-formatted, comprehensive pull requests.

## Files

| File | Purpose |
|------|---------|
| `.pr-message.md` | Full GitHub-formatted PR description (markdown) |
| `.squashed-commit-message.md` | Commit message for squash-merge commits |

## How to Use

### For GitHub PR (Before Merge)

1. Copy the contents of `.pr-message.md`
2. Create a new PR on GitHub
3. Paste the content as the PR body
4. The markdown will render with:
   - Headers and subheaders
   - Code links to file lines
   - Tables
   - Test results
   - Checkboxes
   - Emoji formatting

### For Squash-merge Commit (After Merge)

1. Copy the contents of `.squashed-commit-message.md`
2. This becomes the commit message for the squashed merge
3. Provides a clean, searchable git history

## Formatting Features Demonstrated

### Headers & Organization
```
# 🚀 Fix Critical Bugs from Code Analysis
## 📋 Summary
## 🐛 Bug Fixes
### 🔴 Critical
### 🟡 High Priority
### 🟢 Medium Priority
### 🟠 Low Priority
```

### Links to File Lines
```
[`lib/file_io.dart`](lib/file_io.dart:38-61)
[`lib/pipeline/pipeline_executor.dart:152-157`](lib/pipeline/pipeline_executor.dart:152-157)
```

### Tables
| File | Lines Changed | Purpose |
|------|--------------|---------|
| ... | ... | ... |

### Code Blocks with Test Results
```
test/session/session_ops_test.dart: 00:00 +17: All tests passed!
```

### Emoji Formatting
- 🔴 Critical
- 🟡 High Priority
- 🟢 Medium Priority
- 🟠 Low Priority
- ✅ Testing passed

### Merge Strategy Recommendation
✅ **Squash and Merge** - this is a bug fix branch...

## GitHub Features Utilized

- [x] Custom emoji (GitHub renders these)
- [x] Markdown links with line numbers
- [x] Tables for file change summaries
- [x] Code fences for terminal output
- [x] Task lists for checklists
- [x] Horizontal rules for section separation
- [x] Headers for organization
- [x] Bold/styling for emphasis
- [x] Blockquotes for issue descriptions

## Example Rendered Output

When this PR is viewed on GitHub, you'll see:

1. A professional header with emoji title
2. Well-organized sections color-coded by severity
3. Clickable links directly to source code lines
4. Test results embedded in the PR body
5. Code review checklist with checkboxes
6. Clear merge strategy recommendation

This makes the PR:
- Easy to review (organized sections)
- Easy to verify (test results included)
- Easy to understand (clear descriptions)
- Easy to maintain (clean links to code)

## Next Steps

1. Review the PR with these features in mind
2. Consider applying this format to future PRs
3. Update templates as needed for your team's standards