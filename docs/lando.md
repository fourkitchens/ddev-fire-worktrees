# Lando projects

This add-on runs worktrees on DDEV only. It never creates Lando apps.

## Projects that use only Lando

Add DDEV to the project first: run `ddev config` (see the
[DDEV Drupal quickstart](https://docs.ddev.com/en/stable/users/quickstart/#drupal)), commit `.ddev/`,
then install this add-on.

## Projects with both `.lando.yml` and `.ddev/`

Developers who switch between the two with `fire env:switch` still get DDEV worktrees.

* **Copy your Lando data with a dump.** If your main checkout runs on Lando, its DDEV database may
  be empty or stale, so `--db=primary` has nothing useful to copy. Pass a SQL dump instead:

  ```bash
  lando db-export reference/site-db.sql                          # writes reference/site-db.sql.gz
  ddev fire-worktree-create ABC-123-hero --db=reference/site-db.sql.gz
  ```

  FIRE's `fire local:get-db` writes the same file from Pantheon or Acquia. See
  [Choosing the database](databases.md).
* **Don't run `lando start` in a worktree.** Lando identifies an app by the `name:` in `.lando.yml`,
  which a worktree shares with your main checkout, so it would restart your main checkout's app with
  the worktree's code and share its database.
* **Make FIRE use DDEV in worktrees.** FIRE chooses Lando when `.lando.yml` exists and
  `local_environment` isn't set, and `fire env:switch` writes `local_environment: lando` to
  `fire.local.yml`. Set `local_environment: ddev` in `fire.yml`. If `fire.local.yml` is in
  `WORKTREE_COPY_FILES`, make sure it doesn't say `lando`, so FIRE commands in a worktree use the
  worktree's DDEV project.
