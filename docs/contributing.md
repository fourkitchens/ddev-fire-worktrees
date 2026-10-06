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

CI runs shellcheck and the tests on DDEV stable and HEAD, on amd64 and arm64, for every pull
request, every push to `main`, and weekly. The weekly run and each published release also install
the latest GitHub release.

`main` only takes squash-merged pull requests. shellcheck and the DDEV stable tests must pass; the
DDEV HEAD tests don't block a merge, because a DDEV change can break them for every pull request.

Dependabot opens a pull request when a GitHub Action has a new version.

## Labels

Give each pull request one label. The release notes group pull requests by it:

| Label | Release notes section | Version bump |
| --- | --- | --- |
| `breaking-change` | Breaking changes | minor before v1.0, major after |
| `enhancement` | Features | minor |
| `bug` | Bug fixes | patch |
| `ddev-compat` | DDEV compatibility | patch, or minor if it raises `ddev_version_constraint` |
| `documentation` | Documentation | none on its own |
| `maintenance`, `dependencies` | Maintenance | none on its own |
| `skip-changelog` | left out | none |

## Releasing

Releases are manual. `ddev add-on get fourkitchens/ddev-fire-worktrees` installs the latest
release, so publishing one ships it to every project that installs or updates the add-on.

1. Merge to `main` with CI green.
2. Draft a GitHub release with a new `vX.Y.Z` tag on `main`. Pick the version from the largest bump
   in the table above.
3. Click **Generate release notes**, then add a short summary above them. Call out anything that
   changes what existing worktrees or new worktrees do.
4. Publish. CI runs again on the release, including the `install from release` test.
5. Check the template with `curl -fsSL https://ddev.com/s/addon-update-checker.sh | bash`.
