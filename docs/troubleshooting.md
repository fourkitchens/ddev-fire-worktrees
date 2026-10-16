# Troubleshooting

| Message or symptom | What to do |
| --- | --- |
| `Branch <name> is already checked out in <path>` | That worktree, or your main checkout, already has the branch. Work there instead, and run `ddev fire-worktree-start` in it if it has no site yet. |
| `Branch <name> is checked out in <path>, which no longer exists` | A tool deleted the worktree's directory without telling Git. Run `git worktree prune`, then `ddev fire-worktree-prune` to delete its DDEV project. |
| `Branch <name> already exists and doesn't have pull request #<n>'s latest commit` | Your branch has diverged from the pull request, for example after a force-push. Pass another branch name, `ddev fire-worktree-create --pr=<n> review-<n>`, or delete the old branch. |
| `Couldn't fetch pull request <n> from origin` | origin has no pull request with that number. `--pr` needs origin to be the GitHub repository the pull request is in. |
| `Couldn't look up pull request <n> with gh` | Sign in with `gh auth login`. Until then the branch is named `pr-<n>`, and `--base` doesn't work. |
| `Couldn't snapshot <project>` | Startup used the last worktree copy instead, or the newest other snapshot if there's none. Start your main checkout with `ddev start`, or use `--db=fresh` or a SQL dump. |
| `No earlier worktree copy to reuse` | `--db=latest` found no `fire-worktree-seed-*` snapshot, so it used the newest other snapshot it names. If that's the wrong data, run `ddev fire-worktree-refresh --db=primary` in the worktree. |
| An agent tool says only that its setup script failed | Read `.ddev/fire-worktree-start.log` in the worktree. Each start adds its output there. |
| `The worktree is running, but the build failed` | The site is up with the copied database, at the URLs printed above the message. Fix the error, then run the command it prints. Rerunning startup doesn't rebuild. To have startup and refresh exit 0 when the build fails, set `WORKTREE_BUILD_FAILURE=warn`. |
| `WORKTREE_BUILD_FAILURE must be fail or warn` | Fix the value in `.ddev/config.yaml` or `.ddev/config.local.yaml`. |
| `The worktree is running, but the import failed` | The site is up, but its database is empty or partly imported. Fix the dump, then run the `ddev import-db` command it prints. |
| `This worktree has no database of its own yet` | `refresh` only replaces a database that startup gave the worktree. Run `ddev fire-worktree-start`, which copies one in. |
| `ddev start failed, and the worktree's database may be empty` | `refresh` deleted the old database, but DDEV couldn't start with the new one. Fix the error, then run the command it prints. |
| `Waiting for another worktree to finish starting` | Another worktree is running `ddev start`. A lock left by a crashed run is cleared automatically. |
| `Timed out waiting for .../fire-worktrees.lock` | A fire-worktree command has held the registry lock for 30 seconds. If none is running, delete the lock directory it names. |
| `This worktree inherits <NAME>=<url> from web_environment` | That value names your main checkout's site, so the worktree uses it too. Build it from `${DDEV_SITENAME}.${DDEV_TLD}` or `$DDEV_PRIMARY_URL`. See [Drupal notes](drupal.md#drupal-notes). |
| `Couldn't create a login link` | `ddev drush uli` failed, for example because Drupal isn't installed in the worktree's database. Run the command it prints to see the error. |
| `has a label longer than 63 characters` | Shorten `WORKTREE_NAME_PREFIX` or the worktree's directory name. |
| `Refusing to overwrite .ddev/config.worktree.local.yaml` | You or another tool wrote that file. Move its settings to `config.local.yaml` and delete it. |
| `Refusing to remove ...; commit, stash or discard these changes first` | Commit, stash or delete the listed files, or use `--keep-checkout` to delete only the DDEV project. |
| `Pass --yes to confirm when not running interactively` | Add `--yes` when no one is at the terminal to answer the prompt. |
| A worktree has old data | Its database was copied when it was created; `ddev fire-worktree-info` shows when. Run `ddev fire-worktree-refresh` in it for [a new copy](databases.md#when-the-database-is-copied). |
| Search finds nothing in a new worktree | Its search server starts empty, but the copied database marks items as indexed. Run `ddev drush search-api:reset-tracker`, then `ddev drush search-api:index`. See [Search](drupal.md#search). |
| `ddev fire-worktree-prune` lists volumes an earlier prune left behind | Versions up to 0.1.1 didn't delete add-on services' volumes, such as `ddev-<name>_solr`. If no other clone uses the project, delete them with `docker volume rm`. |
| The computer slows down with several worktrees | Each running worktree uses its own containers. `ddev fire-worktree-list` shows which are running; `ddev stop` the idle ones. |
