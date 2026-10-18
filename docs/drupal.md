# Drupal projects

A standard single-site Drupal project needs no settings. FIRE, multi-domain and multisite projects
need one to three [settings](configuration.md) each.

* [Standard Drupal sites](#standard-drupal-sites)
* [Projects that build with FIRE](#projects-that-build-with-fire)
* [Multi-domain and multisite projects](#multi-domain-and-multisite-projects)
* [Search](#search)
* [Drupal notes](#drupal-notes)

## Standard Drupal sites

With `type: drupal`, `drupal10` or `drupal11` in `.ddev/config.yaml`, each new worktree:

* copies your main checkout's database,
* runs `ddev composer install`,
* runs `ddev drush deploy -y`, which runs database updates, imports configuration, rebuilds caches
  and runs deploy hooks,
* is served at `https://<prefix>-<directory>-<number>.ddev.site`,
* ends startup with a one-time login link to that URL.

`ddev fire-worktree-info` prints a new login link whenever you need one.

Drupal 7 projects get `ddev drush updb -y` instead, because `drush deploy` needs Drupal 8.8 or later.

Some common changes:

* **Compiled theme assets.** If your theme's built CSS and JavaScript are gitignored, add the theme
  build to `WORKTREE_BUILD_COMMAND`. For FIRE projects, see the next section.
* **No configuration management.** `drush deploy` imports configuration and fails when the sync
  directory is empty. Use `WORKTREE_BUILD_COMMAND=ddev drush updb -y && ddev drush cr`.
* **Other local files.** Add files your project keeps out of Git, such as `.env` or `auth.json`, to
  `WORKTREE_COPY_FILES`. List the defaults too if you still want them copied.

## Projects that build with FIRE

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
`--db=reference/site-db.sql.gz`. See [Choosing the database](databases.md).

Once [`ddev-fire`](https://github.com/fourkitchens/ddev-fire) is installed, the default build is
already `ddev site-build --skip-db-import`, which builds the same way inside DDEV and skips the
database download; remove your `WORKTREE_BUILD_COMMAND`. With `--db=fresh`, run `ddev site-build`
in the worktree instead of `fire build`.

If the project also has a `.lando.yml`, read [Lando projects](lando.md) first: FIRE may pick Lando
in a worktree.

## Multi-domain and multisite projects

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
worktree to another site with `ddev fire-worktree-refresh --db=fresh`, then
`fire build --site-name=<site>`. In a multisite with a database per site, make the build command run
`drush deploy` for each site.

## Search

Search servers that run in DDEV, such as Solr, keep their data in volumes that belong to each
project, so a new worktree's search server starts empty. Its database, copied or imported, still
marks items as indexed: `ddev drush search-api:status` shows them indexed, searches find nothing,
and `ddev drush search-api:index` reports the index up to date. Mark every item for reindexing,
then index:

```bash
ddev drush search-api:reset-tracker
ddev drush search-api:index
```

`ddev drush search-api:clear` works too, and also deletes what the server holds. Search API's
Database backend keeps its index in the site's database, so a copy already has it.

`ddev fire-worktree-refresh` keeps the worktree's search server, which still holds items from the
database it replaced. After a refresh, use `search-api:clear` rather than `reset-tracker`, so
deleted content doesn't stay in results.

A new search server has only what its add-on creates when it starts, so a core, collection or index
you added later is missing. With [`ddev/ddev-solr`](https://github.com/ddev/ddev-solr), commit your
configset to `.ddev/solr/configsets` and Solr
[creates its collection](https://github.com/ddev/ddev-solr#create-a-collection) in each worktree. If
you upload the configset from Drupal instead, upload it in the worktree before indexing:

```bash
ddev drush --numShards=1 search-api-solr:upload-configset <server>
```

To reindex after every database copy, add the commands to `WORKTREE_BUILD_COMMAND`. Your setting
replaces the default build, so start with the build your project uses, such as
`ddev drush deploy -y` or `ddev site-build --skip-db-import`:

```yaml
web_environment:
    - WORKTREE_BUILD_COMMAND=ddev drush deploy -y && ddev drush search-api:reset-tracker && ddev drush search-api:index
```

Put the `upload-configset` command, if you need it, before `search-api:reset-tracker`. On a large
site, leave out `search-api:index` and run it when you need search. `search-api:index` exits
successfully even when indexing fails, so look for `Couldn't index items` in the build's output or
in `.ddev/fire-worktree-start.log`.

## Drupal notes

* **Uploaded files.** Worktrees start without `sites/default/files`. Use
  [Stage File Proxy](https://www.drupal.org/project/stage_file_proxy) to fetch them from the remote
  site on demand.
* **Branch in the environment indicator.** In a worktree, `.git` is a file that points outside the
  container, so code that reads `../.git/HEAD` must skip the label when that path isn't readable.
* **Scaffold files in `git status`.** Drupal's Composer scaffold writes files such as
  `web/README.md`, and `.gitignore` files that hide them, but it writes the `.gitignore` files only
  when it can run Git. In a worktree's web container it can't: Mutagen doesn't sync the worktree's
  `.git` file, and without Mutagen that file points at a path in your main checkout that isn't
  mounted. So after `ddev composer install`, startup copies each missing scaffold `.gitignore` from
  your main checkout and prints `Copied <path> from the main checkout`. A worktree you haven't
  edited then has a clean `git status`, and `ddev fire-worktree-remove` deletes it. To clean up a
  worktree an earlier version left with untracked scaffold files, rerun `ddev fire-worktree-start`
  in it.
* **Hard-coded URLs.** Settings or Drush aliases that name `https://<project>.ddev.site` point a
  worktree at your main checkout. Use `DDEV_PRIMARY_URL` instead. Startup warns about
  `web_environment` values that name your main checkout's hostnames, such as
  `DRUSH_OPTIONS_URI=https://www.<project>.ddev.site`. DDEV fills in variables in those values, so
  build them from the project's own name:

  ```yaml
  web_environment:
      - DRUSH_OPTIONS_URI=https://www.${DDEV_SITENAME}.${DDEV_TLD}
  ```

  DDEV already sets `DRUSH_OPTIONS_URI` to `$DDEV_PRIMARY_URL`, so drop a value that only repeats it.
