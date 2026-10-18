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
`create`, else the main checkout.
_Avoid_: creating checkout

**Primary project**:
The DDEV project of the main checkout.

**Shared Git directory**:
The main checkout's `.git` directory, which holds the objects and refs every worktree shares, plus
each linked worktree's own metadata.
_Avoid_: common dir, shared repository, main .git

**Git mount**:
What startup adds to a worktree's web container so Git works there: the shared Git directory,
mounted read-only, and a generated `.git` file, mounted read-only over the worktree's, that points
Git at it. `WORKTREE_MOUNT_GIT=false` turns it off.
