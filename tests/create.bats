#!/usr/bin/env bats

# Fast tests of how fire-worktree-create picks a worktree's branch. They need Git
# but not Docker or DDEV: stubs stand in for ddev, docker and gh.
#   bats ./tests/create.bats

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  CREATE="${DIR}/commands/host/fire-worktree-create"
  TESTDIR="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/fire-worktrees-create.XXXXXX")" && pwd -P)"
  # The start lock lives in DDEV's global directory, which DDEV names to the
  # commands it runs.
  export DDEV_GLOBAL_DIR="${TESTDIR}/ddev"
  mkdir -p "${DDEV_GLOBAL_DIR}"

  # Ignore the developer's Git settings, such as commit signing.
  export GIT_CONFIG_GLOBAL="${TESTDIR}/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.com\n\tname = Test\n[init]\n\tdefaultBranch = main\n' >"${GIT_CONFIG_GLOBAL}"

  # Stand-ins for DDEV and Docker, and for gh pr view NUMBER, which prints the
  # answer in GH_ANSWERS/NUMBER or fails like gh does for an unknown number.
  mkdir -p "${TESTDIR}/bin"
  printf '#!/bin/sh\nexit 0\n' >"${TESTDIR}/bin/ddev"
  printf '#!/bin/sh\nexit 0\n' >"${TESTDIR}/bin/docker"
  cat >"${TESTDIR}/bin/gh" <<'SH'
#!/bin/sh
[ -f "$GH_ANSWERS/$3" ] || { echo "GraphQL: Could not resolve to a PullRequest with the number of $3." >&2; exit 1; }
cat "$GH_ANSWERS/$3"
SH
  chmod +x "${TESTDIR}"/bin/*
  export PATH="${TESTDIR}/bin:${PATH}"
  export GH_ANSWERS="${TESTDIR}/gh"
  mkdir -p "${GH_ANSWERS}"

  # origin, a teammate's clone that pushes to it, and the developer's site.
  ORIGIN="${TESTDIR}/origin.git"
  MATE="${TESTDIR}/mate"
  SITE="${TESTDIR}/site"
  git init -q --bare "${ORIGIN}"
  git init -q "${MATE}"
  mkdir -p "${MATE}/.ddev"
  printf 'name: mysite\ntype: php\n' >"${MATE}/.ddev/config.yaml"
  git -C "${MATE}" add -A
  git -C "${MATE}" commit -qm init
  git -C "${MATE}" remote add origin "${ORIGIN}"
  git -C "${MATE}" push -q -u origin main
  git clone -q "${ORIGIN}" "${SITE}"
  cd "${SITE}"
}

teardown() {
  rm -rf "${TESTDIR}"
}

# mate_commit BRANCH: as the teammate, add a commit to BRANCH, starting it from
# main if origin doesn't have it, push it, and print the commit.
mate_commit() {
  git -C "${MATE}" fetch -q origin
  if git -C "${MATE}" show-ref --verify --quiet "refs/remotes/origin/$1"; then
    git -C "${MATE}" checkout -q -B "$1" "origin/$1"
  else
    git -C "${MATE}" checkout -q -B "$1" origin/main
  fi
  echo "$1" >>"${MATE}/change.txt"
  git -C "${MATE}" add change.txt
  git -C "${MATE}" commit -qm "Change $1"
  git -C "${MATE}" push -q origin "$1"
  git -C "${MATE}" rev-parse HEAD
}

# open_pr NUMBER COMMIT: point origin's pull request ref, as GitHub does.
open_pr() {
  git -C "${MATE}" push -q -f origin "$2:refs/pull/$1/head"
}

# head_of DIR
head_of() {
  git -C "$1" rev-parse HEAD
}

@test "checks out an existing local branch, and refuses one checked out elsewhere" {
  git checkout -q -b feature/local
  echo local >local.txt
  git add local.txt
  git commit -qm 'Local work'
  git checkout -q main

  run "${CREATE}" feature/local --db=fresh
  assert_success
  assert_output --partial "Checked out branch feature/local in:"
  WT="${TESTDIR}/site-feature-local"
  assert_equal "$(git -C "${WT}" symbolic-ref --short HEAD)" feature/local
  [ -f "${WT}/local.txt" ]

  run "${CREATE}" feature/local
  assert_failure
  assert_output "Branch feature/local is already checked out in ${WT}."
  run "${CREATE}" main
  assert_failure
  assert_output "Branch main is already checked out in ${SITE}."

  # A checkout deleted without Git still holds its branch.
  rm -rf "${WT}"
  run "${CREATE}" feature/local
  assert_failure
  assert_output --partial "which no longer exists. Run git worktree prune"

  git branch other
  run "${CREATE}" other main
  assert_failure
  assert_output --partial "Branch other already exists, so it can't start from main."
}

@test "tracks a branch that only origin has, and warns about a stale local branch" {
  PUSHED=$(mate_commit feature/remote)
  # The site hasn't fetched the teammate's branch yet.
  run "${CREATE}" --fetch feature/remote --db=fresh
  assert_success
  assert_output --partial "Created branch feature/remote from origin/feature/remote, which it tracks, in:"
  WT="${TESTDIR}/site-feature-remote"
  assert_equal "$(head_of "${WT}")" "${PUSHED}"
  assert_equal "$(git -C "${WT}" rev-parse --abbrev-ref '@{upstream}')" origin/feature/remote

  # origin/<branch> means origin's branch, and a start point can't override it.
  PUSHED=$(mate_commit feature/other)
  mate_commit feature/third >/dev/null
  git fetch -q origin
  run "${CREATE}" feature/third main
  assert_failure
  assert_output --partial "origin has branch feature/third, so it can't start from main."
  run "${CREATE}" origin/feature/other --db=fresh
  assert_success
  assert_equal "$(git -C "${TESTDIR}/site-feature-other" symbolic-ref --short HEAD)" feature/other
  assert_equal "$(head_of "${TESTDIR}/site-feature-other")" "${PUSHED}"

  # A local branch is checked out as it is, with a warning when it's behind.
  mate_commit feature/behind >/dev/null
  git fetch -q origin
  git branch -q --track feature/behind origin/feature/behind
  mate_commit feature/behind >/dev/null
  mate_commit feature/behind >/dev/null
  run "${CREATE}" --fetch feature/behind --db=fresh
  assert_success
  assert_output --partial "Checked out branch feature/behind in:"
  assert_output --partial "Warning: Branch feature/behind is 2 commits behind origin/feature/behind. To update it, run git pull in the worktree."
}

@test "--fetch starts a new branch from origin's copy of the default branch" {
  NEWEST=$(mate_commit main)
  run "${CREATE}" feature/new --db=fresh
  assert_success
  assert_output --partial "Created branch feature/new from main in:"
  assert_equal "$(head_of "${TESTDIR}/site-feature-new")" "$(git rev-parse main)"

  run "${CREATE}" --fetch feature/newer --db=fresh
  assert_success
  assert_output --partial "Created branch feature/newer from origin/main in:"
  assert_equal "$(head_of "${TESTDIR}/site-feature-newer")" "${NEWEST}"
}

@test "checks out a pull request's branch, fast-forwards it later, and adds its base" {
  FIRST=$(mate_commit feature/pr)
  open_pr 7 "${FIRST}"
  BASE=$(mate_commit main)
  printf 'feature/pr\nmain\nfalse\nfourkitchens\n' >"${GH_ANSWERS}/7"

  run "${CREATE}" --pr=7 --base --db=fresh
  assert_success
  assert_output --partial "Checked out pull request #7 as branch feature/pr in:"
  assert_output --partial "Checked out its base, origin/main, in:"
  WT="${TESTDIR}/site-feature-pr"
  assert_equal "$(head_of "${WT}")" "${FIRST}"
  assert_equal "$(git -C "${WT}" rev-parse --abbrev-ref '@{upstream}')" origin/feature/pr
  assert_equal "$(head_of "${WT}-base")" "${BASE}"
  run git -C "${WT}-base" symbolic-ref -q HEAD
  assert_failure

  # After the pull request gains a commit, a new checkout picks it up.
  git worktree remove "${WT}"
  git worktree remove "${WT}-base"
  SECOND=$(mate_commit feature/pr)
  open_pr 7 "${SECOND}"
  run "${CREATE}" --pr 7 --db=fresh
  assert_success
  assert_equal "$(head_of "${WT}")" "${SECOND}"

  # A rewritten pull request doesn't move a branch that lacks its commits.
  git worktree remove "${WT}"
  git -C "${MATE}" commit -q --amend -m 'Rewritten'
  git -C "${MATE}" push -q -f origin feature/pr
  open_pr 7 "$(git -C "${MATE}" rev-parse HEAD)"
  run "${CREATE}" --pr=7
  assert_failure
  assert_output --partial "Branch feature/pr already exists and doesn't have pull request #7's latest commit."
  assert_equal "$(git rev-parse feature/pr)" "${SECOND}"

  # A branch name of your own avoids that.
  run "${CREATE}" --pr=7 review-7 --db=fresh
  assert_success
  assert_output --partial "Checked out pull request #7 as branch review-7 in:"
  assert_equal "$(head_of "${TESTDIR}/site-review-7")" "$(git -C "${MATE}" rev-parse HEAD)"
  assert_equal "$(git -C "${TESTDIR}/site-review-7" rev-parse --abbrev-ref '@{upstream}')" origin/feature/pr
}

@test "checks out a fork's pull request, or one gh can't look up, through its pull ref" {
  # A fork's main, which only the pull request ref reaches.
  git -C "${MATE}" checkout -q -b fork origin/main
  echo fork >"${MATE}/fork.txt"
  git -C "${MATE}" add fork.txt
  git -C "${MATE}" commit -qm 'Fork work'
  open_pr 8 "$(git -C "${MATE}" rev-parse HEAD)"
  printf 'main\nmain\ntrue\nsomeone\n' >"${GH_ANSWERS}/8"

  run "${CREATE}" --pr=8 --db=fresh
  assert_success
  assert_output --partial "Checked out pull request #8 as branch someone/main in:"
  WT="${TESTDIR}/site-someone-main"
  assert_equal "$(head_of "${WT}")" "$(git -C "${MATE}" rev-parse HEAD)"
  # git pull follows the pull request.
  echo more >>"${MATE}/fork.txt"
  git -C "${MATE}" commit -qam 'More fork work'
  open_pr 8 "$(git -C "${MATE}" rev-parse HEAD)"
  git -C "${WT}" pull -q --ff-only
  assert_equal "$(head_of "${WT}")" "$(git -C "${MATE}" rev-parse HEAD)"

  open_pr 9 "$(git -C "${MATE}" rev-parse HEAD)"
  run "${CREATE}" --pr=9 --db=fresh
  assert_success
  assert_output --partial "Warning: Couldn't look up pull request 9 with gh, so naming its branch pr-9."
  assert_equal "$(head_of "${TESTDIR}/site-pr-9")" "$(git -C "${MATE}" rev-parse HEAD)"

  run "${CREATE}" --pr=9 --base
  assert_failure
  assert_output --partial "--base needs gh to look up pull request 9's base branch."
  run "${CREATE}" --pr=99
  assert_failure
  assert_output --partial "Couldn't fetch pull request 99 from origin."
  run git for-each-ref refs/fire-worktrees
  assert_output ""
}

@test "rejects --base without --pr, and a pull request number that isn't one" {
  run "${CREATE}" --base feature/x
  assert_failure
  assert_output "--base works only with --pr."
  run "${CREATE}" --pr=abc
  assert_failure
  assert_output "--pr takes a pull request number; got abc."
  run "${CREATE}" --pr=7 name main
  assert_failure
  assert_output --partial "Usage:"
}
