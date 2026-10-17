# Choosing the branch

`create` checks out a new branch, an existing branch or a pull request in a directory beside your
main checkout, named after the branch, such as `../mysite-abc-123-hero`.

```bash
ddev fire-worktree-create ABC-123-hero                  # a new branch, or the one you or origin already have
ddev fire-worktree-create ABC-123-hero origin/release   # a new branch from origin/release
ddev fire-worktree-create --fetch ABC-124-footer        # fetch first, to see a teammate's new branch
ddev fire-worktree-create --pr=123                      # a pull request
ddev fire-worktree-create --pr=123 --base               # a pull request, and its base branch beside it
```

Whichever commit a branch is on, its worktree runs your checkout's copy of startup, and takes your
checkout's value for any [setting](configuration.md) the branch's own config doesn't set. A branch
or pull request from before your project added the add-on or its settings gets the same name
prefix, copied files and build as a new branch.

## Branches

`ddev fire-worktree-create <branch>`:

* Checks out your local `<branch>` as it is. If the branch is behind its upstream, `create` says
  so; run `git pull` in the worktree to update it.
* Creates a local `<branch>` that tracks `origin/<branch>` when only origin has it. Writing
  `origin/<branch>` does the same.
* Otherwise creates a new branch from the start point: the second argument, else
  `WORKTREE_BASE_REF`, else your remote's default branch.

A start point applies only to a new branch, so `create` refuses one for a branch that you or origin
already have. It also refuses a branch that's checked out in another worktree or your main
checkout, and says where.

## Fetching first

`create` uses branches as they stand locally, so a branch pushed since your last fetch looks new.
`--fetch` runs `git fetch origin` first. A new branch then starts from origin's copy of its start
point, such as `origin/main`, rather than your local one. An explicit start point is used as you
give it.

## Pull requests

`ddev fire-worktree-create --pr=123` fetches pull request 123 from origin and checks it out,
including a pull request from a fork. It reads GitHub's `refs/pull/<number>/head`, so origin must
be the GitHub repository the pull request is in.

With the [GitHub CLI](https://cli.github.com/) installed and signed in, `create` names the branch
after the pull request's branch:

* A pull request from your repository gets its own branch name, such as `ABC-123-hero`, tracking
  origin's copy. You can push fixes to it.
* A pull request from a fork gets the fork owner's name in front, such as `someone/main`, so it
  can't take the name of one of your branches.

Without `gh`, the branch is `pr-123`. To choose the name yourself, pass it:
`ddev fire-worktree-create --pr=123 review-123`.

To update the worktree after the pull request changes, run `git pull` in it. If you removed the
worktree and kept the branch, running `create --pr` again fast-forwards the branch. If the branch
has commits the pull request doesn't have, such as after a force-push, `create` stops rather than
move it; pass another branch name.

## Comparing before and after

`--base` also creates a worktree on the pull request's base branch, as origin has it, beside the
first: `../mysite-abc-123-hero-base`. It needs `gh` to find the base branch. Its HEAD is detached,
so your main checkout keeps the base branch.

When the pull request's worktree copies your main checkout's database, the base worktree reuses
that copy (`--db=latest`), so both start from the same data. Run `ddev fire-worktree-remove` in
each worktree when you're done.
