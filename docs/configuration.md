# Configuration

Every setting is optional. Add them to `web_environment` in `.ddev/config.yaml` for the whole team,
or in `.ddev/config.local.yaml` for yourself; the local file wins. The commands read these files
directly, so settings apply before a worktree's DDEV project exists.

A worktree's own files come first. When they don't set a setting, such as on a branch from before
your project added it, startup takes the value from the checkout you ran `create` in, else from your
main checkout. The worktree then gets the same name prefix, copied files and build as a new branch,
whichever tool started it. Later commands in that worktree, such as `refresh`, read its own files,
including the `config.local.yaml` it copied, then your main checkout's.

| Variable | Default | Purpose |
| --- | --- | --- |
| `WORKTREE_NAME_PREFIX` | Your project's name, cut to 12 characters | Start of each worktree's DDEV project name and URL. |
| `WORKTREE_BASE_REF` | Your remote's default branch, else `main` | Start point for a new branch when `create` gets none. With `--fetch`, origin's copy of it. |
| `WORKTREE_COPY_FILES` | `.ddev/config.local.yaml <docroot>/sites/default/settings.local.php` | Space-separated gitignored files, relative to the project root, copied into a new worktree when missing. |
| `WORKTREE_DB` | `primary` | Default for `--db`. See [Choosing the database](databases.md). |
| `WORKTREE_BUILD_COMMAND` | `ddev site-build --skip-db-import` when `ddev-fire` is installed; else `ddev drush deploy -y` for Drupal 8 and later, `ddev drush updb -y` for Drupal 7, and `none` for other project types | Runs in the worktree after a database copy. `none` skips it. |
| `WORKTREE_BUILD_FAILURE` | `fail` | What `start` and `refresh` do when the build fails, after it prints the URLs and the command to rerun. `fail` exits 1. `warn` exits 0, so an agent tool carries on in the running site. |
| `WORKTREE_MOUNT_GIT` | `true` | Whether `start` mounts the shared Git directory read-only in the web container, so `git` works there (see [Git in the web container](how-it-works.md#git-in-the-web-container)). `false` turns it off, and the next `start` deletes the files it wrote for the mount. When DDEV's global `no_bind_mounts` is true, as for remote Docker, `start` skips the mount whatever this says. |

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
