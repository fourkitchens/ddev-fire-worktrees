#!/usr/bin/env bats

# Fast tests of the T3 actions docs/agent-tools.md publishes. They need Git but
# not Docker, DDEV or T3: stubs stand in for ddev and docker.
#   bats ./tests/t3.bats

bats_require_minimum_version 1.5.0

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  TESTDIR="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/fire-worktrees-t3.XXXXXX")" && pwd -P)"
  # The start lock lives in DDEV's global directory, which DDEV names to the
  # commands it runs.
  export DDEV_GLOBAL_DIR="${TESTDIR}/ddev"
  mkdir -p "${DDEV_GLOBAL_DIR}"

  # Ignore the developer's Git settings, such as commit signing.
  export GIT_CONFIG_GLOBAL="${TESTDIR}/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.com\n\tname = Test\n[init]\n\tdefaultBranch = main\n' >"${GIT_CONFIG_GLOBAL}"

  # A stand-in for DDEV, which runs a project's own host commands and knows no
  # others, and for Docker.
  mkdir -p "${TESTDIR}/bin"
  cat >"${TESTDIR}/bin/ddev" <<'SH'
#!/bin/sh
case $1 in
  fire-worktree-*)
    cmd="$(git rev-parse --show-toplevel)/.ddev/commands/host/$1"
    [ -x "$cmd" ] || { echo "Error: unknown command \"$1\" for \"ddev\"" >&2; exit 1; }
    shift
    exec "$cmd" "$@"
    ;;
esac
exit 0
SH
  printf '#!/bin/sh\nexit 0\n' >"${TESTDIR}/bin/docker"
  chmod +x "${TESTDIR}"/bin/*
  export PATH="${TESTDIR}/bin:${PATH}"

  # The checkout T3 names, on a branch from before the project adopted the
  # add-on.
  SITE="${TESTDIR}/site"
  mkdir -p "${SITE}/.ddev"
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git -C "${SITE}" init -q
  git -C "${SITE}" add -A
  git -C "${SITE}" commit -qm init
  git -C "${SITE}" branch release/old
  unset WORKTREE_SOURCE_ROOT
  export T3CODE_PROJECT_ROOT="${SITE}"
}

teardown() {
  rm -rf "${TESTDIR}"
}

# adopt_addon: install the add-on in the T3 checkout and add the team's
# worktree settings, as a project adopting it does.
adopt_addon() {
  mkdir -p "${SITE}/.ddev/commands/host" "${SITE}/.ddev/fire-worktrees"
  cp "${DIR}"/commands/host/fire-worktree-* "${SITE}/.ddev/commands/host/"
  cp "${DIR}/fire-worktrees/lib.sh" "${SITE}/.ddev/fire-worktrees/"
  printf 'name: mysite\ntype: php\nweb_environment:\n    - WORKTREE_NAME_PREFIX=team\n    - WORKTREE_DB=fresh\n' >"${SITE}/.ddev/config.yaml"
  git -C "${SITE}" add -A
  git -C "${SITE}" commit -qm 'Add ddev-fire-worktrees'
}

# action NAME: the command of the T3 action NAME in docs/agent-tools.md.
action() {
  sed -n "s/.*{ \"name\": \"$1\", \"command\": \"\(.*\)\", \"icon\".*/\1/p" "${DIR}/docs/agent-tools.md" |
    sed 's/\\"/"/g'
}

# project_of DIR: the DDEV project name startup gave DIR.
project_of() {
  awk '$1 == "name:" { print $2; exit }' "$1/.ddev/config.worktree.local.yaml"
}

@test "Start worktree starts a worktree from a branch that predates the add-on with T3's checkout's copy" {
  adopt_addon
  WT="${TESTDIR}/site-release-old"
  git -C "${SITE}" worktree add -q "${WT}" release/old

  cmd=$(action 'Start worktree')
  assert [ -n "${cmd}" ]
  cd "${WT}"
  run sh -c "${cmd}"
  assert_success
  assert_line --regexp '^Configured DDEV project team-release-old-[0-9]+$'
  run project_of "${WT}"
  assert_output --regexp '^team-release-old-[0-9]+$'
}

@test "Start worktree runs the worktree's own copy when its branch has the add-on" {
  adopt_addon
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  # T3's checkout has since moved on to a copy that doesn't work.
  printf '#!/bin/sh\necho "T3 checkout copy" >&2\nexit 99\n' >"${SITE}/.ddev/commands/host/fire-worktree-start"

  cd "${WT}"
  run sh -c "$(action 'Start worktree')"
  assert_success
  assert_line --regexp '^Configured DDEV project team-feature-x-[0-9]+$'
  refute_output --partial "T3 checkout copy"
}
