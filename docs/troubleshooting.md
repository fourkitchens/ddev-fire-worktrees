# Troubleshooting

| Message or symptom | What to do |
| --- | --- |
| `Couldn't snapshot <project>` | Startup used the last worktree copy instead, or the newest other snapshot if there's none. Start your main checkout with `ddev start`, or use `--db=fresh` or a SQL dump. |
| `No earlier worktree copy to reuse` | `--db=latest` found no `fire-worktree-seed-*` snapshot, so it used the newest other snapshot it names. If that's the wrong data, run `ddev delete --omit-snapshot --yes` in the worktree, then `ddev fire-worktree-start --db=primary`. |
| `The worktree is running, but the build failed` | The site is up with the copied database. Fix the error, then run the command it prints. Rerunning startup doesn't rebuild. |
| `The worktree is running, but the import failed` | The site is up, but its database is empty or partly imported. Fix the dump, then run the `ddev import-db` command it prints. |
| `Waiting for another worktree to finish starting` | Another worktree is running `ddev start`. A lock left by a crashed run is cleared automatically. |
| `Timed out waiting for .../fire-worktrees.lock` | A fire-worktree command has held the registry lock for 30 seconds. If none is running, delete the lock directory it names. |
| `This worktree inherits <NAME>=<url> from web_environment` | That value names your main checkout's site, so the worktree uses it too. Build it from `${DDEV_SITENAME}.${DDEV_TLD}` or `$DDEV_PRIMARY_URL`. See [Drupal notes](drupal.md#drupal-notes). |
| `Couldn't create a login link` | `ddev drush uli` failed, for example because Drupal isn't installed in the worktree's database. Run the command it prints to see the error. |
| `has a label longer than 63 characters` | Shorten `WORKTREE_NAME_PREFIX` or the worktree's directory name. |
| `Refusing to overwrite .ddev/config.worktree.local.yaml` | You or another tool wrote that file. Move its settings to `config.local.yaml` and delete it. |
| `Refusing to remove ...; commit, stash or discard these changes first` | Commit, stash or delete the listed files, or use `--keep-checkout` to delete only the DDEV project. |
| `Pass --yes to confirm when not running interactively` | Add `--yes` when no one is at the terminal to answer the prompt. |
| A worktree has old data | Its database was copied when it was created. [Get a new copy](databases.md#when-the-database-is-copied). |
| `ddev fire-worktree-prune` lists volumes an earlier prune left behind | Versions up to 0.1.1 didn't delete add-on services' volumes, such as `ddev-<name>_solr`. If no other clone uses the project, delete them with `docker volume rm`. |
| The computer slows down with several worktrees | Each running worktree uses its own containers. `ddev fire-worktree-list` shows which are running; `ddev stop` the idle ones. |
