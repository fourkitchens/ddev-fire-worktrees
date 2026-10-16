# Choosing the database

A new worktree copies your main checkout's database by default. `create` and `start` take
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

The database is copied only when the worktree has none yet, so reruns of `ddev fire-worktree-start`
keep its data. To get a new copy, run these in the worktree:

```bash
ddev delete --omit-snapshot --yes
ddev fire-worktree-start
```

After a copy, startup runs `WORKTREE_BUILD_COMMAND` so the copy matches the branch's code and
configuration. With `--no-build`, it prints the command instead.

## Snapshots and dumps

* A snapshot copies every database on your main checkout's server. A SQL dump fills only the `db`
  database.
* Only the newest `fire-worktree-seed-*` snapshot is kept in your main checkout's
  `.ddev/db_snapshots`, so copies don't fill the disk.
* `latest`, and `primary` when it can't snapshot your main checkout, only use a snapshot that matches
  the worktree's database type and version. They prefer the newest `fire-worktree-seed-*` snapshot
  over newer ones you took by hand, such as one saved before a risky migration.
