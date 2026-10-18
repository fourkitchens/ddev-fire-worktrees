# How it works

## What startup does

`ddev fire-worktree-start`, which `create` also runs:

1. Copies the gitignored files in `WORKTREE_COPY_FILES` that the worktree doesn't have, so a copied
   `config.local.yaml` applies from the first start.
2. Writes `.ddev/config.worktree.local.yaml` with the worktree's DDEV project name and hostnames.
3. Starts the project, seeding a new database from `--db`.
4. Runs `ddev composer install` when the project has a `composer.json`, then copies from your main
   checkout each `.gitignore` the worktree lacks that hides one of its untracked files, such as the
   Drupal scaffold's. See [Drupal notes](drupal.md#drupal-notes).
5. If it just copied a database, runs `WORKTREE_BUILD_COMMAND`. `--no-build` skips this and prints
   the command. A copy that [looks incomplete](databases.md#when-the-database-is-copied) isn't
   built.
6. Warns about untracked files that Composer or the build created and nothing hides, since
   `remove` refuses a worktree that has them.
7. Prints the worktree's URLs. For a Drupal site with a database, it also prints a one-time login
   link from `ddev drush uli`. If the build failed, it then prints the command to rerun and exits
   1, or 0 with `WORKTREE_BUILD_FAILURE=warn`.

It's safe to rerun: an existing worktree keeps its project name and data.

## Details

* **Project name.** Startup writes `.ddev/config.worktree.local.yaml` with `override_config: true`
  and a name such as `mysite-abc-123-hero-1234567890`: the prefix, the directory name cut to 24
  characters, and a checksum of the checkout's path. A pull request's base worktree keeps `-base`
  at the end of the cut, as in `mysite-abc-123-hero-base-1234567890`. The name stays the same when
  you rename the branch, and a rerun keeps the name the worktree already has. DDEV
  gitignores the file and loads it after `config.local.yaml`; startup also adds it to
  `.git/info/exclude`.
* **Hostnames.** Each `additional_hostnames` entry is rewritten for the worktree, and
  `additional_fqdns` and fixed host ports are left out. See
  [Multi-domain and multisite projects](drupal.md#multi-domain-and-multisite-projects).
* **Local files.** Startup copies `WORKTREE_COPY_FILES` from the checkout that ran `create`, else
  from `T3CODE_PROJECT_ROOT`, else from your main checkout. It never overwrites a file.
* **Scaffold `.gitignore` files.** For each untracked file in the worktree, startup asks your main
  checkout's Git which file ignores it. It copies that file from the main checkout when it's a
  `.gitignore` inside the project, the worktree has no file there, and the main checkout ignores it
  too, and prints `Copied <path> from the main checkout`. It repeats until there's nothing more to
  copy, so a `.gitignore` that another one hides is copied too. Unlike `WORKTREE_COPY_FILES`, these
  always come from the main checkout, not the source checkout that `WORKTREE_COPY_FILES` comes
  from, since a source checkout that is another worktree may lack them as well. Startup never overwrites a file or changes the main
  checkout.
* **Settings.** Startup reads the `WORKTREE_*` settings from the worktree's own config files. When
  `create` runs it, a setting those files don't set comes from the checkout that ran `create`.
* **Log.** Each start appends its output to the worktree's `.ddev/fire-worktree-start.log`, under a
  line with the date, and prints the log's path when it fails. Startup adds the log to
  `.git/info/exclude`, and `remove` deletes it with the checkout.
* **Database.** DDEV seeds a database only when it creates the database volume, so startup never
  replaces a worktree's data. `ddev fire-worktree-refresh` does, after asking: it runs
  `ddev start --reset-database` with the worktree's project name, which deletes only the database
  volume, and seeds a new one. Both note where the database came from in the worktree's Git
  directory, as `fire-worktree-db`, for `ddev fire-worktree-info`. The file's modification time is
  when the database was created. See [Choosing the database](databases.md).
* **Parallel starts.** A lock in DDEV's global directory, `~/.ddev/fire-worktree-start.lock`, makes
  worktrees take turns at `ddev start`, including when they refresh, whichever tool or shell runs
  them. `ddev version` shows the directory as `global-ddev-dir`.
* **Prune.** Startup records each worktree in `.git/fire-worktrees`, taking a short lock
  (`.git/fire-worktrees.lock`) so parallel starts, removes and prunes keep each other's entries.
  Prune deletes only recorded projects whose checkout is gone. Without the checkout, `ddev delete`
  can't find add-on services' volumes, such as Solr's, so prune also deletes every volume Docker
  Compose labelled with the project. It lists, but never deletes, older worktree projects and
  leftover volumes that match the prefix of the checkout you run it in or of your main checkout,
  since another clone may own them.
* **Safety.** The commands refuse to run startup or refresh in the main checkout, to refresh a
  worktree before its first start, when DDEV would treat it as your main project, to overwrite a
  config file they didn't write, or to remove a checkout with uncommitted work. They never delete
  branches. `create` moves an existing branch only to fast-forward a pull request's branch that
  tracks the pull request.
* **Portability.** The commands are Bash 3.2 scripts that read DDEV's YAML themselves, so they need
  no `jq`, `yq` or Python.
