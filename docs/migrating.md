# Migrating from project-local worktree commands

Some projects carry their own `worktree-create`, `worktree-start` and `worktree-remove` host
commands. To switch to this add-on:

1. Delete `.ddev/commands/host/worktree-create`, `worktree-start` and, where present, `worktree-remove`.
2. Run `ddev add-on get fourkitchens/ddev-fire-worktrees` and commit.
3. Set `WORKTREE_NAME_PREFIX` to the prefix the old commands used, plus `WORKTREE_COPY_FILES` and
   `WORKTREE_BUILD_COMMAND` as needed. See [Configuration](configuration.md).
4. Keep `/.ddev/config.worktree.yaml` in `.gitignore` until every existing worktree has run
   `ddev worktree-start` once.

Existing worktrees keep their DDEV project and database: the next `ddev worktree-start` reads the
name from the old `.ddev/config.worktree.yaml` and replaces that file. Tool actions that call
`ddev worktree-start`, such as T3's, keep working through the alias. The installer reminds you about
any old command files it finds.
