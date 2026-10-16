# T3 and other agent tools

Any tool that creates Git worktrees works: run `ddev fire-worktree-start` in the new checkout.
Worktrees that start at the same time take turns at `ddev start`, so a tool can start several at
once.

A worktree inside your main checkout, such as Claude Code's `.claude/worktrees/`, works too, but
sibling directories are better: if your main project uses Mutagen, it syncs a nested worktree into
its own container.

## Login links and worktree details

For a Drupal site, startup ends with a one-time login link to the worktree. Later, run
`ddev fire-worktree-info --json` in the worktree for its project name, status, URLs, database source
and age, and a new login link:

```json
{
  "name": "mysite-abc-123-hero-1234567890",
  "status": "running",
  "urls": ["https://mysite-abc-123-hero-1234567890.ddev.site"],
  "database": {"source": "primary", "file": "/path/to/mysite/.ddev/db_snapshots/fire-worktree-seed-20261016093000-mariadb_10.11.gz", "created": "2026-10-16T14:30:05Z"},
  "login_url": "https://mysite-abc-123-hero-1234567890.ddev.site/user/reset/1/1760610000/abc/login"
}
```

`database.source` is the `--db` the database came from: `primary`, `latest`, `fresh`, `snapshot` or
`dump`, or `unknown` for a worktree started before this was recorded. `database.created` is when
startup or the last refresh created the database, in UTC, or `null` when that's unknown. `login_url`
is `null` when the project isn't running or isn't Drupal.

To give a worktree a new copy of the database, run `ddev fire-worktree-refresh --yes` in it.

## When startup fails

Many tools show only that a setup script failed. Startup appends its output to
`.ddev/fire-worktree-start.log` in the worktree, so you, or the agent in that thread, can read
what went wrong.

When the build fails, for example when `drush deploy` stops on a configuration error, the site is
still running. Startup prints the URLs and the build command to rerun, then exits 1, so the tool
reports the failure. To let the thread carry on in the running site instead, have startup exit 0:

```yaml
# .ddev/config.local.yaml, which new worktrees copy
web_environment:
    - WORKTREE_BUILD_FAILURE=warn
```

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

When a tool deletes a worktree's checkout itself, its DDEV project, database and service volumes
stay behind. Run `ddev fire-worktree-prune` from any checkout to list them, and
`ddev fire-worktree-prune --yes` to delete them.
