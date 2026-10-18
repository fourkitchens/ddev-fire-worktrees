# ddev-fire-worktrees

Gives each Git worktree of a DDEV project its own DDEV project, hostnames and database, so several
branches of one site can run side by side.

## Language

**Primary checkout**:
The repository's original, non-worktree checkout, whose `.git` directory every linked worktree
shares. Its DDEV project is the primary project.
_Avoid_: main checkout (easily confused with the `main` branch)
