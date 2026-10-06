# Contributing

## Running the tests

```bash
brew install bats-core shellcheck
brew tap bats-core/bats-core && brew install bats-support bats-assert bats-file
shellcheck -x -s bash commands/host/* fire-worktrees/lib.sh
bats ./tests/lib.bats                           # library tests, a few seconds, no Docker
bats ./tests --filter-tags '!release'           # everything, with real DDEV projects
```

The DDEV tests start real projects, including a Drupal 11 site, under `~/tmp`, and delete them
afterwards. They take about four minutes on a laptop.

To try a change in a project before it's released:

```bash
ddev add-on get /path/to/ddev-fire-worktrees                                       # a local checkout
ddev add-on get https://github.com/fourkitchens/ddev-fire-worktrees/tarball/<branch>   # a pushed branch
```

## CI

CI runs shellcheck and the tests on DDEV stable and HEAD, on amd64 and arm64, for every push and
pull request, and weekly. The weekly run also installs the latest GitHub release, so it fails until
the first release exists.

## Releasing

1. Merge to `main` with CI green.
2. Create a GitHub release with a `vX.Y.Z` tag. `ddev add-on get fourkitchens/ddev-fire-worktrees`
   installs the latest release.
3. Check the template with `curl -fsSL https://ddev.com/s/addon-update-checker.sh | bash`.
