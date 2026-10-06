# Drupal projects

A standard single-site Drupal project needs no settings. FIRE, multi-domain and multisite projects
need one to three [settings](configuration.md) each.

* [Standard Drupal sites](#standard-drupal-sites)
* [Projects that build with FIRE](#projects-that-build-with-fire)
* [Multi-domain and multisite projects](#multi-domain-and-multisite-projects)
* [Drupal notes](#drupal-notes)

## Standard Drupal sites

With `type: drupal`, `drupal10` or `drupal11` in `.ddev/config.yaml`, each new worktree:

* copies your main checkout's database,
* runs `ddev composer install`,
* runs `ddev drush deploy -y`, which runs database updates, imports configuration, rebuilds caches
  and runs deploy hooks,
* is served at `https://<prefix>-<directory>-<number>.ddev.site`.

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
already `ddev fire-build --no-db-import`; remove your `WORKTREE_BUILD_COMMAND`.

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
worktree to another site with `--db=fresh` and `fire build --site-name=<site>`. In a multisite with
a database per site, make the build command run `drush deploy` for each site.

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
