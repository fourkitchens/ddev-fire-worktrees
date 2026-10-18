# Agent tools

An agent tool, such as T3, Orca or Conductor, creates a worktree of your project for each task and
runs a coding agent in it. Two lines in the tool's config give each of those worktrees its own DDEV
project, and delete it again when the tool deletes the worktree. Every tool uses the same two lines,
so the sections below differ only in where the lines go.

## Any agent tool

A tool needs a setup script that runs in the new worktree, and ideally a script that runs before it
deletes a worktree. Paste the lines below into those scripts unchanged; they stay the same from
release to release ([why](adr/0001-agent-tools-share-one-git-based-recipe.md)). They run in `sh`,
`bash` and `zsh`, under `set -e` and joined with `&&`, and work from checkouts whose paths have
spaces.

### The setup line

```sh
if [ -x .ddev/commands/host/fire-worktree-start ]; then ddev fire-worktree-start; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-start"; fi
```

It runs the worktree's own `fire-worktree-start` when its branch has the add-on, so a branch that
tests a newer version of the add-on uses it. On a branch older than the add-on, such as an old
release branch, it runs your main checkout's copy, which it finds through Git. Either way, startup
takes local files, and any `WORKTREE_*` setting the worktree's own config lacks, from the main
checkout, so the worktree gets the team's name prefix and build.

Have the agent wait for setup to finish wherever the tool allows it, so it doesn't work in a site
that isn't running yet. Worktrees that start at the same time take turns at `ddev start`, so a tool
can start several at once.

### The teardown line

```sh
if [ -x .ddev/commands/host/fire-worktree-remove ]; then ddev fire-worktree-remove --keep-checkout --yes; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-remove" --keep-checkout --yes; fi || true
```

It deletes the worktree's DDEV project, database and service volumes, and leaves the checkout for the
tool to delete. Tools run it with no terminal to answer the confirmation prompt, hence `--yes`. It
always exits 0, so a failure, such as Docker not running, never stops the tool from deleting the
worktree. Its output still shows, and [`prune`](#tools-without-teardown) cleans up afterwards.

### Tools without teardown

When a tool can't run anything before it deletes a worktree, run
`ddev fire-worktree-remove --keep-checkout` in the worktree, then delete the worktree in the tool.
When a worktree's checkout goes without that, its DDEV project, database and service volumes stay
behind. Run `ddev fire-worktree-prune` from any checkout to list them, and
`ddev fire-worktree-prune --yes` to delete them.

Startup tells you when they pile up. When a worktree starts and the registry lists environments
whose checkout is gone, it prints one line saying how many and naming
`ddev fire-worktree-prune --yes`, then carries on. It never deletes them itself, since a checkout
on a drive that isn't mounted looks gone too. It counts only worktrees that `fire-worktree-start`
recorded; `prune` also lists older ones it finds through Docker.

### Branches older than the add-on

In a worktree whose branch doesn't have the add-on, `ddev fire-worktree-info` and the other
commands don't exist. Run your main checkout's copy instead, as the setup and teardown lines do:

```bash
"$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-info" --json
```

### Login links and worktree details

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
`dump`, `unknown` for a worktree started before this was recorded, or `none` when the worktree has no
database, as after `ddev fire-worktree-remove --keep-checkout`. Run `ddev fire-worktree-start` to
copy one in, not `ddev start`, which creates an empty one. `database.created` is when startup or the
last refresh created the database, in UTC, or `null` when that's unknown or there's no database.
`login_url` is `null` when the project isn't running or isn't Drupal.

To give a worktree a new copy of the database, run `ddev fire-worktree-refresh --yes` in it.

### When startup fails

Many tools show only that a setup script failed. Startup appends its output to
`.ddev/fire-worktree-start.log` in the worktree, so you, or the agent in that worktree, can read
what went wrong.

When the build fails, for example when `drush deploy` stops on a configuration error, the site is
still running. Startup prints the URLs and the build command to rerun, then exits 1, so the tool
reports the failure. To let the agent carry on in the running site instead, have startup exit 0:

```yaml
# .ddev/config.local.yaml, which new worktrees copy
web_environment:
    - WORKTREE_BUILD_FAILURE=warn
```

### Worktrees inside the main checkout

A worktree inside your main checkout, such as Claude Code's `.claude/worktrees/`, works too, but
sibling directories are better: if your main project uses Mutagen, it syncs a nested worktree into
its own container.

## T3

For [T3](https://t3.codes), add these actions to the project's `t3.json`:

```json
{
  "$schema": "https://t3.codes/schema/t3.json",
  "scripts": [
    { "name": "Start worktree", "command": "if [ -x .ddev/commands/host/fire-worktree-start ]; then ddev fire-worktree-start; else \"$(dirname \"$(git rev-parse --path-format=absolute --git-common-dir)\")/.ddev/commands/host/fire-worktree-start\"; fi", "icon": "play", "runOnWorktreeCreate": true, "async": false },
    { "name": "Delete worktree environment", "command": "if [ -x .ddev/commands/host/fire-worktree-remove ]; then ddev fire-worktree-remove --keep-checkout; else \"$(dirname \"$(git rev-parse --path-format=absolute --git-common-dir)\")/.ddev/commands/host/fire-worktree-remove\" --keep-checkout; fi", "icon": "configure" },
    { "name": "Find orphaned worktree environments", "command": "if [ -x .ddev/commands/host/fire-worktree-prune ]; then ddev fire-worktree-prune; else \"$(dirname \"$(git rev-parse --path-format=absolute --git-common-dir)\")/.ddev/commands/host/fire-worktree-prune\"; fi", "icon": "configure" }
  ]
}
```

T3 doesn't apply `t3.json` on its own: each person imports the actions, in Settings → Project →
Actions → Import from t3.json, or with **From t3.json** in the scripts menu.

**Start worktree** runs the setup line when T3 creates a thread's worktree, and `"async": false`
keeps the thread waiting until startup finishes. T3 runs only the first action with
`runOnWorktreeCreate`, so make this the only one. Leave `previewUrl` out of these actions: a fixed
URL previews the primary project from every thread.

T3 has no hook for deleting a worktree, so run **Delete worktree environment** before deleting a
thread. If you forget, **Find orphaned worktree environments** lists what's left behind; delete it
with `ddev fire-worktree-prune --yes`. T3's storage cleanup can also delete worktrees without
running anything, which startup's notice about lost checkouts catches. Like the setup line, both
actions fall back to the main checkout's copy on a branch older than the add-on.

## Orca

For [Orca](https://www.onorca.dev), add this to the project's `orca.yaml`:

```yaml
scripts:
  setup: |
    if [ -x .ddev/commands/host/fire-worktree-start ]; then ddev fire-worktree-start; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-start"; fi
  archive: |
    if [ -x .ddev/commands/host/fire-worktree-remove ]; then ddev fire-worktree-remove --keep-checkout --yes; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-remove" --keep-checkout --yes; fi || true
setupAgentStartupPolicy: wait-for-setup
```

`setupAgentStartupPolicy: wait-for-setup` keeps the agent waiting until startup finishes.

Orca takes the setup script from the new worktree's `orca.yaml`, so a worktree on a branch without
the file, such as one older than the recipe, runs no setup. To start those too, each person can put
the setup line in Orca's own hook, in Settings → Repository, set to local-only or run-both; that hook
runs on every branch. Local-only ignores `orca.yaml`'s scripts, so give the hook the teardown line
as its archive script too.

Orca takes the archive script from the main checkout's `orca.yaml`, runs it with no terminal, and
stops it after 2 minutes. `orca worktree rm` runs it only with `--run-hooks`.

## Conductor

For [Conductor](https://www.conductor.build), add this to the project's `.conductor/settings.toml`:

```toml
[scripts]
setup = 'if [ -x .ddev/commands/host/fire-worktree-start ]; then ddev fire-worktree-start; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-start"; fi'
archive = 'if [ -x .ddev/commands/host/fire-worktree-remove ]; then ddev fire-worktree-remove --keep-checkout --yes; else "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.ddev/commands/host/fire-worktree-remove" --keep-checkout --yes; fi || true'
```

The single quotes make each line a TOML literal string, which holds its double quotes without
escaping.

Conductor's Mac app reads this file from the default branch on the remote, so merge it before you
expect new workspaces to use it.

Conductor starts the agent alongside setup and documents no setting to make it wait, so the
agent's first steps may come before the site is running.

## Cursor

For [Cursor](https://cursor.com), add this to the project's `.cursor/worktrees.json`:

```json
{
  "setup-worktree": [
    "if [ -x .ddev/commands/host/fire-worktree-start ]; then ddev fire-worktree-start; else \"$(dirname \"$(git rev-parse --path-format=absolute --git-common-dir)\")/.ddev/commands/host/fire-worktree-start\"; fi"
  ]
}
```

Cursor reads the worktree's `.cursor/worktrees.json`, then the project root's, so a worktree on a
branch older than the file still runs setup.

Cursor has no teardown, and once it has more worktrees than `cursor.worktreeMaxCount` (25 by
default), it deletes older ones without running anything. Rely on startup's notice and
[`prune`](#tools-without-teardown) to clean up after it.

Cursor doesn't document whether setup finishes before the agent starts, so the agent may start
before the site is running. To check on setup, open the Output panel and select "Worktrees Setup".
