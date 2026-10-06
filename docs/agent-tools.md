# T3 and other agent tools

Any tool that creates Git worktrees works: run `ddev fire-worktree-start` in the new checkout.
Worktrees that start at the same time take turns at `ddev start`, so a tool can start several at
once.

A worktree inside your main checkout, such as Claude Code's `.claude/worktrees/`, works too, but
sibling directories are better: if your main project uses Mutagen, it syncs a nested worktree into
its own container.

## T3

For [T3](https://t3.codes), add these actions to the project's `t3.json`:

```json
{
  "$schema": "https://t3.codes/schema/t3.json",
  "scripts": [
    { "name": "Start worktree", "command": "ddev fire-worktree-start", "icon": "play", "runOnWorktreeCreate": true, "async": false },
    { "name": "Delete worktree environment", "command": "ddev fire-worktree-remove --keep-checkout", "icon": "configure" },
    { "name": "Find orphaned worktree environments", "command": "ddev fire-worktree-prune", "icon": "configure" }
  ]
}
```

**Start worktree** runs when T3 creates a thread's worktree. Startup copies local files from the
checkout T3 names in `T3CODE_PROJECT_ROOT`.

T3 has no hook for deleting a worktree, so run **Delete worktree environment** before deleting a
thread. If you forget, **Find orphaned worktree environments** lists what's left behind; delete it
with `ddev fire-worktree-prune --yes`.

## Cleaning up after other tools

When a tool deletes a worktree's checkout itself, its DDEV project and database stay behind. Run
`ddev fire-worktree-prune` from any checkout to list them, and `ddev fire-worktree-prune --yes` to
delete them.
