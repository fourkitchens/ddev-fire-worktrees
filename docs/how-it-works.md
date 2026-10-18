# How it works

## What startup does

`ddev fire-worktree-start`, which `create` also runs:

1. Copies the gitignored files in `WORKTREE_COPY_FILES` that the worktree doesn't have, so a copied
   `config.local.yaml` applies from the first start.
2. Writes `.ddev/config.worktree.local.yaml` with the worktree's DDEV project name and hostnames,
   and the files that [mount Git](#git-in-the-web-container) in its web container.
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
  `.git/info/exclude`. The file has a `#ddev-silent-no-warn` line, so DDEV leaves it out of the
  custom configuration it lists on every start.
* **Hostnames.** Each `additional_hostnames` entry is rewritten for the worktree, and
  `additional_fqdns` and fixed host ports are left out. See
  [Multi-domain and multisite projects](drupal.md#multi-domain-and-multisite-projects).
* **Local files.** Startup copies `WORKTREE_COPY_FILES` from the source checkout: the checkout that
  ran `create`, else your main checkout. It never overwrites a file.
* **Scaffold `.gitignore` files.** For each untracked file in the worktree, startup asks your main
  checkout's Git which file ignores it. It copies that file from the main checkout when it's a
  `.gitignore` inside the project, the worktree has no file there, and the main checkout ignores it
  too, and prints `Copied <path> from the main checkout`. It repeats until there's nothing more to
  copy, so a `.gitignore` that another one hides is copied too. Unlike `WORKTREE_COPY_FILES`, these
  always come from the main checkout, not the source checkout that `WORKTREE_COPY_FILES` comes
  from, since a source checkout that is another worktree may lack them as well. Startup never overwrites a file or changes the main
  checkout.
* **Settings.** Startup reads the `WORKTREE_*` settings from the worktree's own config files. A
  setting those files don't set, such as on a branch older than the setting, comes from the source
  checkout. When `create` ran from another worktree, the main checkout doesn't fill in what that
  worktree lacks too.
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
  Prune deletes only recorded projects whose checkout is gone: no checkout that Git lists for the
  repository has the project's name in its generated config, so a worktree moved with
  `git worktree move` keeps its environment. Without the checkout, `ddev delete` can't find add-on
  services' volumes, such as Solr's, so prune also deletes every volume Docker Compose labelled
  with the project. It lists, but never deletes, older worktree projects and leftover volumes that
  match the prefix of the checkout you run it in, of your main checkout, or the default prefix, the
  main checkout's project name, which earlier versions gave a worktree on a branch older than the
  team's prefix. Another clone may own them. Startup counts recorded projects whose checkout is
  gone the same way and prints a one-line notice naming `ddev fire-worktree-prune --yes`. It reads
  only the registry, Git and the filesystem, makes no Docker calls, and changes nothing, since a
  checkout on a drive that isn't mounted looks gone too.
* **Safety.** The commands refuse to run startup or refresh in the main checkout, to refresh a
  worktree before its first start, when DDEV would treat it as your main project, to overwrite a
  file at a generated file's path that they didn't write, or to remove a checkout with uncommitted
  work. They never delete branches. `create` moves an existing branch only to fast-forward a pull
  request's branch that tracks the pull request.
* **Portability.** The commands are Bash 3.2 scripts that read DDEV's YAML themselves, so they need
  no `jq`, `yq` or Python.

## Git in the web container

A linked worktree's `.git` is a file that points at its metadata in the main checkout's shared Git
directory, a host path the web container doesn't have. With Mutagen, the container has no `.git`
at all, because DDEV's Mutagen config ignores it. So startup adds its own Git mount, the same way
with and without Mutagen. Every `fire-worktree-start` writes two files in the worktree's `.ddev`:

* `docker-compose.fire-worktree-git.yaml` mounts the shared Git directory read-only at
  `/mnt/fire-worktrees/git`, and the next file read-only over `/var/www/html/.git`. Like
  `config.worktree.local.yaml`, it has a `#ddev-silent-no-warn` line, so DDEV leaves it out of
  the custom configuration it lists on every start.
* `fire-worktree-git` holds `gitdir: /mnt/fire-worktrees/git/worktrees/<id>`, where `<id>` names
  the worktree's metadata directory. Git takes everything after `gitdir: ` as the path, so this file
  can't carry the "generated" comment the other files start with. The mount path marks it instead.

Git commands that read, such as `git rev-parse`, `git status` and `git log`, then work in the
container, and Drupal's Composer scaffold sees a Git repository and writes its `.gitignore` files.
Commands that write, such as `git commit`, fail with "Read-only file system". Run those on the host.

* **Why read-only.** The shared Git directory lists every worktree by its host path, which the
  container doesn't have, so `git worktree prune` in the container would delete the metadata of
  every worktree that isn't locked. Under Mutagen, a write to the index would also fill it with the
  container's file times, which don't match the host's. `git status` skips its index update when
  it can't write.
* **Why a fixed path.** Mounting at the host path would need a `.git` file mounted under Mutagen
  anyway, and would recreate your home directory's path in the container.
* **A moved main checkout.** The mounts use `create_host_path: false`, so after you move the main
  checkout, `ddev start` and `ddev restart` fail with "bind source path does not exist" rather than
  mounting an empty directory, and `ddev fire-worktree-start` stops earlier, saying the worktree
  "is not inside a Git checkout", because the worktree's own `.git` file names the old path too.
  Run `git worktree repair` from the main checkout, then `ddev fire-worktree-start`, which writes
  the new path.
* **Reruns.** Startup rewrites both files on every run, and refuses to overwrite either one it
  didn't write. A single-file mount keeps showing the file it mounted, so startup changes
  `fire-worktree-git` only when its text changes, and in place. `fire-worktree-refresh`,
  `ddev start` and `ddev restart` use the files as they are. A worktree started before this add-on
  mounted Git gets the mount on its next `fire-worktree-start`.
* **Not committed.** Startup adds both files to `.git/info/exclude`.
* **The container's Git.** The web image's Git can be older than your host's. When the host's Git
  uses a repository feature the container's can't read, such as `worktree.useRelativePaths`, Git in
  the container fails with "unknown repository extension". Startup doesn't check for this; see
  [Troubleshooting](troubleshooting.md).
* **Turning it off.** With `WORKTREE_MOUNT_GIT=false`, or DDEV's global `no_bind_mounts` set for
  remote Docker, startup deletes both files if it wrote them, so the container has no Git metadata
  again. It leaves files it didn't write, and doesn't refuse to start over them. When `ddev start`
  fails with the mount on, startup names the shared Git directory and the setting.
