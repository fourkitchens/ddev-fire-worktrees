# ddev-fire-worktrees

A DDEV add-on that gives each Git worktree of a project its own DDEV project, database and
hostnames, so several branches run side by side.

## Language

**Main checkout**:
The repository's original working tree, the one that holds the `.git` directory rather than a
linked worktree.
_Avoid_: primary checkout

**Source checkout**:
The checkout a worktree's startup copies local files and settings from: the checkout that ran
`create`, else `T3CODE_PROJECT_ROOT`, else the main checkout.
_Avoid_: creating checkout

**Primary project**:
The DDEV project of the main checkout.
