[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/fourkitchens/ddev-fire-worktrees/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/fourkitchens/ddev-fire-worktrees/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/fourkitchens/ddev-fire-worktrees)](https://github.com/fourkitchens/ddev-fire-worktrees/commits)
[![release](https://img.shields.io/github/v/release/fourkitchens/ddev-fire-worktrees)](https://github.com/fourkitchens/ddev-fire-worktrees/releases/latest)

# DDEV Fire Worktrees <!-- omit in toc -->

* [Overview](#overview)
* [Requirements](#requirements)
* [Installation](#installation)
* [Usage](#usage)
  * [Commands](#commands)
  * [Choosing the database](#choosing-the-database)
  * [What startup does](#what-startup-does)
* [Advanced Customization](#advanced-customization)
  * [Settings](#settings)
  * [Standard Drupal sites](#standard-drupal-sites)
  * [Projects that build with FIRE](#projects-that-build-with-fire)
  * [Multi-domain and multisite projects](#multi-domain-and-multisite-projects)
* [Lando projects](#lando-projects)
* [Using it with T3 and other agent tools](#using-it-with-t3-and-other-agent-tools)
* [Migrating from project-local worktree commands](#migrating-from-project-local-worktree-commands)
* [How it works](#how-it-works)
* [Drupal notes](#drupal-notes)
* [Troubleshooting](#troubleshooting)
* [Removal](#removal)
* [Contributing](#contributing)
* [Credits](#credits)

## Overview

This add-on runs several branches of a Drupal site side by side. Each
[Git worktree](https://git-scm.com/docs/git-worktree) gets its own DDEV project, database and URLs.
Its database starts as a copy of your main checkout's, then Drupal's deploy steps run so the copy
matches the branch. Your committed `.ddev/config.yaml` never changes.

A standard single-site Drupal project needs no settings. Multi-domain and multisite projects need
a few. The add-on is part of the Fire family with [`ddev-fire`](https://github.com/fourkitchens/ddev-fire),
but neither add-on needs the other.

```bash
ddev fire-worktree-create ABC-123-hero   # new branch and checkout, its own site, a copy of your database
ddev fire-worktree-list                  # every worktree, its status and URL
ddev fire-worktree-remove                # in a worktree: delete its site and checkout, keep the branch
```

## Requirements

* [DDEV](https://ddev.com/) v1.25.4 or later.
* Git, and a project with `.ddev/config.yaml` committed.
* macOS or Linux. The commands run in Bash 3.2 or later and need no `jq`, `yq` or Python.

## Installation

```bash
ddev add-on get fourkitchens/ddev-fire-worktrees
git add .ddev
git commit -m "Add ddev-fire-worktrees"
```

Commit the installed files, because a new worktree only has the commands its branch has. The commands
run on your computer rather than in a container, so no `ddev restart` is needed.

Install only one worktree add-on per project. Other public add-ons also define `ddev worktree-remove`,
which this add-on provides as an alias.

## Usage

### Commands

| Command | Alias | What it does |
| --- | --- | --- |
| `ddev fire-worktree-create <branch> [start-point]` | `worktree-create` | Creates the branch in a directory beside your main checkout, such as `../mysite-abc-123-hero`, then runs startup there. |
| `ddev fire-worktree-start` | `worktree-start` | Gives the worktree you're in its own DDEV project, copies the database into it, and builds it. Safe to rerun. |
| `ddev fire-worktree-list` | | Lists every worktree with its branch, DDEV project, status, uncommitted changes and URL. |
| `ddev fire-worktree-remove [--yes] [--keep-checkout] [path]` | `worktree-remove` | Deletes the worktree's DDEV project and database, then removes the checkout. Keeps the branch. |
| `ddev fire-worktree-prune [--yes]` | | Finds DDEV projects whose checkout is gone, for example after T3 deletes a thread. Deletes them with `--yes`. |

Run `create`, `list` and `prune` from any checkout of the repository. Run `start` inside a worktree.
Run `remove` inside a worktree, or pass its path. Every command accepts `--help`.

`create` starts from `WORKTREE_BASE_REF`, else your remote's default branch, as it stands locally.
Fetch first to start from the newest commit. `create` refuses a branch or directory that already exists.

`remove` refuses the main checkout and a worktree with uncommitted or untracked files. It asks before
deleting anything; pass `--yes` when no one is at the terminal.

### Choosing the database

`create` and `start` take `--db=<source>` and `--no-build`. Without `--db`, they use `WORKTREE_DB`,
else `primary`.

| `--db` | The new worktree's database |
| --- | --- |
| `primary` | A new snapshot of your main checkout's DDEV database. DDEV starts that project for the snapshot if it's stopped. |
| `latest` | The newest snapshot in your main checkout's `.ddev/db_snapshots`, without taking a new one. Faster when you create several worktrees in a row. |
| `fresh` | An empty database. Fill it with `fire build`, `ddev fire-build`, `ddev pull <provider>` or `ddev import-db`. |
| A snapshot file | That `ddev snapshot` file. |
| A SQL dump | Imported with `ddev import-db`. Accepts `.sql`, `.sql.gz`, `.sql.bz2`, `.sql.xz`, `.mysql`, `.mysql.gz`, `.zip`, `.tgz` and `.tar.gz`, for example FIRE's `reference/site-db.sql.gz`. |

The database is copied only when the worktree has none yet, so reruns keep its data. To get a new
copy, run `ddev delete --omit-snapshot --yes` in the worktree, then `ddev fire-worktree-start`.

A snapshot copies every database on your main checkout's server. A SQL dump fills only the `db` database.

### What startup does

`ddev fire-worktree-start`, which `create` also runs:

1. Writes `.ddev/config.worktree.local.yaml` with the worktree's DDEV project name and hostnames.
2. Copies the gitignored files in `WORKTREE_COPY_FILES` that the worktree doesn't have.
3. Starts the project, seeding a new database from `--db`.
4. Runs `ddev composer install` when the project has a `composer.json`.
5. If it just copied a database, runs `WORKTREE_BUILD_COMMAND`. `--no-build` skips this and prints the command.
6. Prints the worktree's URLs.

## Advanced Customization

### Settings

Every setting is optional. Add them to `web_environment` in `.ddev/config.yaml` for the whole team,
or in `.ddev/config.local.yaml` for yourself; the local file wins. The commands read these files
directly, so settings apply before a worktree's DDEV project exists.

| Variable | Default | Purpose |
| --- | --- | --- |
| `WORKTREE_NAME_PREFIX` | Your project's name, cut to 12 characters | Start of each worktree's DDEV project name and URL. |
| `WORKTREE_BASE_REF` | Your remote's default branch, else `main` | Start point when `create` gets none. |
| `WORKTREE_COPY_FILES` | `.ddev/config.local.yaml <docroot>/sites/default/settings.local.php` | Space-separated gitignored files, relative to the project root, copied into a new worktree when missing. |
| `WORKTREE_DB` | `primary` | Default for `--db`. |
| `WORKTREE_BUILD_COMMAND` | `ddev fire-build --no-db-import` when `ddev-fire` is installed; else `ddev drush deploy -y` for Drupal 8 and later, `ddev drush updb -y` for Drupal 7, and `none` for other project types | Runs in the worktree after a database copy. `none` skips it. |

### Standard Drupal sites

A single-site Drupal project with `type: drupal`, `drupal10` or `drupal11` needs no settings. Each
new worktree:

* copies your main checkout's database,
* runs `ddev composer install`,
* runs `ddev drush deploy -y`, which runs database updates, imports configuration, rebuilds caches
  and runs deploy hooks,
* is served at `https://<prefix>-<directory>-<number>.ddev.site`.

Some common changes:

* **Compiled theme assets.** If your theme's built CSS and JavaScript are gitignored, add the theme
  build to `WORKTREE_BUILD_COMMAND`. For FIRE projects, see the next section.
* **No configuration management.** `drush deploy` imports configuration and fails when the sync
  directory is empty. Use `WORKTREE_BUILD_COMMAND=ddev drush updb -y && ddev drush cr`.
* **Other local files.** Add files your project keeps out of Git, such as `.env` or `auth.json`, to
  `WORKTREE_COPY_FILES`. List the defaults too if you still want them copied.

### Projects that build with FIRE

In a project with a `fire.yml`, `drush deploy` doesn't build the theme. Use FIRE's build without its
database download instead:

```yaml
web_environment:
    - WORKTREE_BUILD_COMMAND=fire build --no-db-import
```

`fire build --no-db-import` runs `composer install`, the JavaScript and theme builds, then
`drush updb`, `drush cim` and deploy hooks. FIRE runs on your computer, so each developer needs the
FIRE launcher, or can use `./vendor/bin/fire build --no-db-import`.

To start a worktree from the remote site rather than your local database, create it with
`--db=fresh`, then run `fire build` in the worktree. To reuse a download you already have, pass
`--db=reference/site-db.sql.gz`.

Once [`ddev-fire`](https://github.com/fourkitchens/ddev-fire) is installed, the default build is
already `ddev fire-build --no-db-import`; remove your `WORKTREE_BUILD_COMMAND`.

### Multi-domain and multisite projects

Each `additional_hostnames` entry is rewritten so two projects never claim the same hostname.
`<sub>.<project>` becomes `<sub>.<worktree project>`, wildcards included, and any other hostname `<h>`
becomes `<h>.<worktree project>`. `additional_fqdns` and fixed host ports are left out, because two
running projects can't share them. Drupal Domain records can match both checkouts with patterns such
as `news.*.ddev.site`.

A project with several domains and a FIRE theme build might use:

```yaml
web_environment:
    - WORKTREE_NAME_PREFIX=acme
    - WORKTREE_COPY_FILES=.ddev/config.local.yaml fire.local.yml web/sites/default/settings.local.php
    - WORKTREE_BUILD_COMMAND=ddev drush deploy -y && fire build-theme
```

In a multisite that runs one site at a time in the `db` database, such as one built with
`fire build --site-name=<site>`, the copy holds whichever site your main checkout runs. Switch a
worktree to another site with `--db=fresh` and `fire build --site-name=<site>`. In a multisite with
a database per site, make the build command run `drush deploy` for each site.

## Lando projects

This add-on runs worktrees on DDEV only. It never creates Lando apps.

**Projects that use only Lando** add DDEV first: run `ddev config` (see the
[DDEV Drupal quickstart](https://docs.ddev.com/en/stable/users/quickstart/#drupal)), commit `.ddev/`,
then install this add-on.

**Projects with both `.lando.yml` and `.ddev/`**, where developers switch with `fire env:switch`,
still get DDEV worktrees:

* If your main checkout runs on Lando, its DDEV database may be empty or stale, so `--db=primary`
  has nothing useful to copy. Pass a SQL dump instead:

  ```bash
  lando db-export reference/site-db.sql                          # writes reference/site-db.sql.gz
  ddev fire-worktree-create ABC-123-hero --db=reference/site-db.sql.gz
  ```

  FIRE's `fire local:get-db` writes the same file from Pantheon or Acquia.
* Don't run `lando start` in a worktree. Lando identifies an app by the `name:` in `.lando.yml`,
  which a worktree shares with your main checkout, so it would restart your main checkout's app with
  the worktree's code and share its database.
* FIRE chooses Lando when `.lando.yml` exists and `local_environment` isn't set, and
  `fire env:switch` writes `local_environment: lando` to `fire.local.yml`. Set
  `local_environment: ddev` in `fire.yml`. If `fire.local.yml` is in `WORKTREE_COPY_FILES`, make
  sure it doesn't say `lando`, so FIRE commands in a worktree use the worktree's DDEV project.

## Using it with T3 and other agent tools

Any tool that creates Git worktrees works: run `ddev fire-worktree-start` in the new checkout. A
worktree inside your main checkout, such as Claude Code's `.claude/worktrees/`, works too, but
sibling directories are better: if your main project uses Mutagen, it syncs a nested worktree into
its own container.

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

T3 has no hook for deleting a worktree, so run **Delete worktree environment** before deleting a
thread. If you forget, **Find orphaned worktree environments** lists what's left behind; delete it
with `ddev fire-worktree-prune --yes`. Worktrees that start at the same time take turns at
`ddev start`, so T3 can start several at once.

## Migrating from project-local worktree commands

Some projects carry their own `worktree-create`, `worktree-start` and `worktree-remove` host
commands. To switch:

1. Delete `.ddev/commands/host/worktree-create`, `worktree-start` and, where present, `worktree-remove`.
2. Run `ddev add-on get fourkitchens/ddev-fire-worktrees` and commit.
3. Set `WORKTREE_NAME_PREFIX` to the prefix the old commands used, plus `WORKTREE_COPY_FILES` and
   `WORKTREE_BUILD_COMMAND` as needed.
4. Keep `/.ddev/config.worktree.yaml` in `.gitignore` until every existing worktree has run
   `ddev worktree-start` once.

Existing worktrees keep their DDEV project and database: the next `ddev worktree-start` reads the
name from the old `.ddev/config.worktree.yaml` and replaces that file. T3 actions that call
`ddev worktree-start` keep working through the alias. The installer reminds you about any old
command files it finds.

## How it works

* **Project name.** Startup writes `.ddev/config.worktree.local.yaml` with `override_config: true`
  and a name such as `mysite-abc-123-hero-1234567890`: the prefix, the directory name, and a
  checksum of the checkout's path. The name stays the same when you rename the branch. DDEV
  gitignores the file and loads it after `config.local.yaml`; startup also adds it to
  `.git/info/exclude`.
* **Local files.** Startup copies `WORKTREE_COPY_FILES` from the checkout that ran `create`, else
  from `T3CODE_PROJECT_ROOT`, else from your main checkout. It never overwrites a file.
* **Database.** DDEV seeds a database only when it creates the database volume, so a copy never
  replaces a worktree's data. Only the newest `fire-worktree-seed-*` snapshot is kept in your main
  checkout's `.ddev/db_snapshots`.
* **Parallel starts.** A lock in your temporary directory makes worktrees take turns at `ddev start`.
* **Prune.** Startup records each worktree in `.git/fire-worktrees`. Prune deletes only recorded
  projects whose checkout is gone. It lists, but never deletes, older worktree projects that match
  your prefix, since another clone may own them.
* **Safety.** The commands refuse to run startup in the main checkout, to overwrite a config file
  they didn't write, or to remove a checkout with uncommitted work. They never delete branches.

## Drupal notes

* **Uploaded files.** Worktrees start without `sites/default/files`. Use
  [Stage File Proxy](https://www.drupal.org/project/stage_file_proxy) to fetch them from the remote
  site on demand.
* **Search.** Solr and other service volumes belong to each project, so indexes start empty.
  Reindex with `ddev drush search-api:index`.
* **Branch in the environment indicator.** In a worktree, `.git` is a file that points outside the
  container, so code that reads `../.git/HEAD` must skip the label when that path isn't readable.
* **Hard-coded URLs.** Settings or Drush aliases that name `https://<project>.ddev.site` point a
  worktree at your main checkout. Use `DDEV_PRIMARY_URL` instead.

## Troubleshooting

| Message or symptom | What to do |
| --- | --- |
| `Couldn't snapshot <project>` | Startup used the newest older snapshot instead. Start your main checkout with `ddev start`, or use `--db=fresh` or a SQL dump. |
| `The worktree is running, but the build failed` | The site is up with the copied database. Fix the error, then run the command it prints. Rerunning startup doesn't rebuild. |
| `Waiting for another worktree to finish starting` | Another worktree is running `ddev start`. A lock left by a crashed run is cleared automatically. |
| `has a label longer than 63 characters` | Shorten `WORKTREE_NAME_PREFIX` or the worktree's directory name. |
| `Refusing to overwrite .ddev/config.worktree.local.yaml` | You or another tool wrote that file. Move its settings to `config.local.yaml` and delete it. |
| The computer slows down with several worktrees | Each running worktree uses its own containers. `ddev fire-worktree-list` shows which are running; `ddev stop` the idle ones. |

## Removal

```bash
ddev add-on remove fire-worktrees
```

This removes the commands but not the worktrees' DDEV projects. Run `ddev fire-worktree-remove` in
each worktree first, or delete projects afterwards with `ddev delete <name>`.

## Contributing

```bash
brew install bats-core shellcheck
brew tap bats-core/bats-core && brew install bats-support bats-assert bats-file
shellcheck -x -s bash commands/host/* fire-worktrees/lib.sh
bats ./tests/lib.bats                           # library tests, a few seconds, no Docker
bats ./tests --filter-tags '!release'           # everything, with real DDEV projects
```

The DDEV tests start real projects, including a Drupal 11 site, under `~/tmp`, and delete them
afterwards. They take about four minutes on a laptop. CI runs them on DDEV stable and HEAD, on
every push and pull request, and weekly. The weekly run also installs the latest GitHub release.

## Credits

**Contributed and maintained by [Four Kitchens](https://www.fourkitchens.com/), started by [@mcortes19](https://github.com/mcortes19)**
