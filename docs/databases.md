# Choosing the database

A new worktree copies your main checkout's database by default. `create`, `start` and `refresh` take
`--db=<source>` to choose another source, and `--no-build` to skip the build after the copy. Without
`--db`, they use [`WORKTREE_DB`](configuration.md), else `primary`.

| `--db` | The new worktree's database |
| --- | --- |
| `primary` | A new snapshot of your main checkout's DDEV database. DDEV starts that project for the snapshot if it's stopped. |
| `latest` | The last copy a worktree took: the newest `fire-worktree-seed-*` snapshot in your main checkout's `.ddev/db_snapshots`, without taking a new one. Faster when you create several worktrees in a row. If there's none, it warns and uses the newest other snapshot. |
| `fresh` | An empty database. Fill it with `fire build`, `ddev site-build`, `ddev pull <provider>` or `ddev import-db`. |
| A snapshot file | That `ddev snapshot` file. |
| A SQL dump | Imported with `ddev import-db`. Accepts `.sql`, `.sql.gz`, `.sql.bz2`, `.sql.xz`, `.mysql`, `.mysql.gz`, `.zip`, `.tgz` and `.tar.gz`, for example FIRE's `reference/site-db.sql.gz`. |

For example:

```bash
ddev fire-worktree-create ABC-123-hero                                   # copy your main checkout
ddev fire-worktree-create ABC-123-hero --db=latest                       # reuse the last copy
ddev fire-worktree-create ABC-123-hero --db=reference/site-db.sql.gz     # import a dump
ddev fire-worktree-create ABC-123-hero --db=fresh --no-build             # empty, build it yourself
```

A path is read from the directory you run the command in.

## When the database is copied

Startup copies the database only when the worktree has none yet, so reruns of
`ddev fire-worktree-start` keep its data. After a copy, it runs `WORKTREE_BUILD_COMMAND` so the copy
matches the branch's code and configuration. With `--no-build`, it prints the command instead.

Before the build, startup checks the copy, since a restore can stop partway and still report
success. A copy with no tables looks incomplete, and so does one Drush can't bootstrap Drupal from.
Startup then warns, skips the build and exits 0, so the site stays up; run
`ddev fire-worktree-refresh` to copy the database again. In a project that isn't Drupal, the check
finds only a copy with no tables. On later starts, a kept database with no tables gets the same
warning, unless `--db=fresh` created it empty.

A worktree that lives for days falls behind your main checkout. To replace its database with a new
copy, run this in the worktree:

```bash
ddev fire-worktree-refresh                                    # a new copy of your main checkout
ddev fire-worktree-refresh --db=latest                        # the last copy a worktree took
ddev fire-worktree-refresh --db=reference/site-db.sql.gz      # import a dump
```

`refresh` copies, checks and builds the same way as a first start. It keeps the worktree's DDEV project and
its other volumes, such as search indexes, which `ddev delete` would remove. It doesn't keep the old
database, so it asks first; run `ddev snapshot` before it to keep a copy, and pass `--yes` when no
one is at the terminal. `ddev fire-worktree-info` shows when the database was created.

## Snapshots and dumps

* A snapshot copies every database on your main checkout's server. A SQL dump fills only the `db`
  database.
* Only the newest `fire-worktree-seed-*` snapshot is kept in your main checkout's
  `.ddev/db_snapshots`, so copies don't fill the disk.
* `latest`, and `primary` when it can't snapshot your main checkout, only use a snapshot that matches
  the worktree's database type and version. They prefer the newest `fire-worktree-seed-*` snapshot
  over newer ones you took by hand, such as one saved before a risky migration.
