Fixes #REPLACE_ME_WITH_RELATED_ISSUE_NUMBER

<!-- Add one label, which sets this PR's section in the release notes: bug, enhancement, breaking-change, ddev-compat, documentation, maintenance or dependencies. Use skip-changelog to leave it out. -->

## Summary

<!-- What changes and why, in a sentence or two. Add the smallest view that makes it clear: a diff of the startup steps, a call tree or a file tree. -->

## Evidence

<!-- The test or output that fails before this change and passes after it. Say which tests you ran: shellcheck, `bats ./tests/lib.bats`, `bats ./tests --filter-tags '!release'`. -->

- **Before:**
  **After:**

To try this PR in a project:

```bash
ddev add-on get fourkitchens/ddev-fire-worktrees --pr REPLACE_ME_WITH_THIS_PR_NUMBER
ddev fire-worktree-create test-pr-branch
```

## Merge Danger

**Door:** <!-- one-way or two-way: can a later release undo this for users who already ran it? -->

**Blast Radius:** <!-- one word, such as first-start, remove, hostnames or docs; then who notices and how -->
