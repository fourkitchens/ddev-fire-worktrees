# How it works

## What startup does

`ddev fire-worktree-start`, which `create` also runs:

1. Writes `.ddev/config.worktree.local.yaml` with the worktree's DDEV project name and hostnames.
2. Copies the gitignored files in `WORKTREE_COPY_FILES` that the worktree doesn't have.
3. Starts the project, seeding a new database from `--db`.
4. Runs `ddev composer install` when the project has a `composer.json`.
5. If it just copied a database, runs `WORKTREE_BUILD_COMMAND`. `--no-build` skips this and prints
   the command.
6. Prints the worktree's URLs.

It's safe to rerun: an existing worktree keeps its project name and data.

## Details

* **Project name.** Startup writes `.ddev/config.worktree.local.yaml` with `override_config: true`
  and a name such as `mysite-abc-123-hero-1234567890`: the prefix, the directory name, and a
  checksum of the checkout's path. The name stays the same when you rename the branch. DDEV
  gitignores the file and loads it after `config.local.yaml`; startup also adds it to
  `.git/info/exclude`.
* **Hostnames.** Each `additional_hostnames` entry is rewritten for the worktree, and
  `additional_fqdns` and fixed host ports are left out. See
  [Multi-domain and multisite projects](drupal.md#multi-domain-and-multisite-projects).
* **Local files.** Startup copies `WORKTREE_COPY_FILES` from the checkout that ran `create`, else
  from `T3CODE_PROJECT_ROOT`, else from your main checkout. It never overwrites a file.
* **Database.** DDEV seeds a database only when it creates the database volume, so a copy never
  replaces a worktree's data. See [Choosing the database](databases.md).
* **Parallel starts.** A lock in your temporary directory makes worktrees take turns at `ddev start`.
* **Prune.** Startup records each worktree in `.git/fire-worktrees`. Prune deletes only recorded
  projects whose checkout is gone. It lists, but never deletes, older worktree projects that match
  your prefix, since another clone may own them.
* **Safety.** The commands refuse to run startup in the main checkout, to overwrite a config file
  they didn't write, or to remove a checkout with uncommitted work. They never delete branches.
* **Portability.** The commands are Bash 3.2 scripts that read DDEV's YAML themselves, so they need
  no `jq`, `yq` or Python.
