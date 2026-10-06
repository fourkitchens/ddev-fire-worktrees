# Troubleshooting

| Message or symptom | What to do |
| --- | --- |
| `Couldn't snapshot <project>` | Startup used the newest older snapshot instead. Start your main checkout with `ddev start`, or use `--db=fresh` or a SQL dump. |
| `The worktree is running, but the build failed` | The site is up with the copied database. Fix the error, then run the command it prints. Rerunning startup doesn't rebuild. |
| `The worktree is running, but the import failed` | The site is up, but its database is empty or partly imported. Fix the dump, then run the `ddev import-db` command it prints. |
| `Waiting for another worktree to finish starting` | Another worktree is running `ddev start`. A lock left by a crashed run is cleared automatically. |
| `has a label longer than 63 characters` | Shorten `WORKTREE_NAME_PREFIX` or the worktree's directory name. |
| `Refusing to overwrite .ddev/config.worktree.local.yaml` | You or another tool wrote that file. Move its settings to `config.local.yaml` and delete it. |
| `Refusing to remove ...; commit, stash or discard these changes first` | Commit, stash or delete the listed files, or use `--keep-checkout` to delete only the DDEV project. |
| `Pass --yes to confirm when not running interactively` | Add `--yes` when no one is at the terminal to answer the prompt. |
| A worktree has old data | Its database was copied when it was created. [Get a new copy](databases.md#when-the-database-is-copied). |
| The computer slows down with several worktrees | Each running worktree uses its own containers. `ddev fire-worktree-list` shows which are running; `ddev stop` the idle ones. |
