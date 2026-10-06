# Configuration

Every setting is optional. Add them to `web_environment` in `.ddev/config.yaml` for the whole team,
or in `.ddev/config.local.yaml` for yourself; the local file wins. The commands read these files
directly, so settings apply before a worktree's DDEV project exists.

| Variable | Default | Purpose |
| --- | --- | --- |
| `WORKTREE_NAME_PREFIX` | Your project's name, cut to 12 characters | Start of each worktree's DDEV project name and URL. |
| `WORKTREE_BASE_REF` | Your remote's default branch, else `main` | Start point when `create` gets none. |
| `WORKTREE_COPY_FILES` | `.ddev/config.local.yaml <docroot>/sites/default/settings.local.php` | Space-separated gitignored files, relative to the project root, copied into a new worktree when missing. |
| `WORKTREE_DB` | `primary` | Default for `--db`. See [Choosing the database](databases.md). |
| `WORKTREE_BUILD_COMMAND` | `ddev fire-build --no-db-import` when `ddev-fire` is installed; else `ddev drush deploy -y` for Drupal 8 and later, `ddev drush updb -y` for Drupal 7, and `none` for other project types | Runs in the worktree after a database copy. `none` skips it. |

For example, a team setting in `.ddev/config.yaml`:

```yaml
web_environment:
    - WORKTREE_NAME_PREFIX=acme
    - WORKTREE_BUILD_COMMAND=fire build --no-db-import
```

And a personal override in `.ddev/config.local.yaml` that skips the build:

```yaml
web_environment:
    - WORKTREE_BUILD_COMMAND=none
```

DDEV also passes these variables into the web container. Nothing there reads them, so they're
harmless. Changing them needs no `ddev restart`.

For settings that suit each kind of project, see [Drupal projects](drupal.md).
