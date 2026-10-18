#!/usr/bin/env bats

# Fast tests of the setup and teardown lines docs/agent-tools.md publishes for
# agent tools. They need Git but not Docker, DDEV or an agent tool: stubs stand
# in for ddev and docker.
#   bats ./tests/agent-tools.bats

bats_require_minimum_version 1.5.0

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  PAGE="${DIR}/docs/agent-tools.md"
  TESTDIR="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/fire-worktrees-agent-tools.XXXXXX")" && pwd -P)"
  # The start lock lives in DDEV's global directory, which DDEV names to the
  # commands it runs.
  export DDEV_GLOBAL_DIR="${TESTDIR}/ddev"
  mkdir -p "${DDEV_GLOBAL_DIR}"

  # Ignore the developer's Git settings, such as commit signing.
  export GIT_CONFIG_GLOBAL="${TESTDIR}/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.com\n\tname = Test\n[init]\n\tdefaultBranch = main\n' >"${GIT_CONFIG_GLOBAL}"

  # A stand-in for DDEV, which runs a project's own host commands and knows no
  # others, and for Docker. With DDEV_DELETE_FAILS set, ddev delete fails, as
  # it does when Docker isn't running.
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
  delete)
    if [ -n "${DDEV_DELETE_FAILS:-}" ]; then
      echo 'Could not connect to a Docker provider.' >&2
      exit 1
    fi
    ;;
esac
exit 0
SH
  printf '#!/bin/sh\nexit 0\n' >"${TESTDIR}/bin/docker"
  chmod +x "${TESTDIR}"/bin/*
  export PATH="${TESTDIR}/bin:${PATH}"

  # The main checkout, in a directory with a space in its name, on a branch
  # from before the project adopted the add-on. No agent tool's variable is
  # set.
  SITE="${TESTDIR}/my site"
  mkdir -p "${SITE}/.ddev"
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git -C "${SITE}" init -q
  git -C "${SITE}" add -A
  git -C "${SITE}" commit -qm init
  git -C "${SITE}" branch release/old
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
}

teardown() {
  rm -rf "${TESTDIR}"
}

# adopt_addon: install the add-on in the main checkout and add the team's
# worktree settings, as a project adopting it does.
adopt_addon() {
  mkdir -p "${SITE}/.ddev/commands/host" "${SITE}/.ddev/fire-worktrees"
  cp "${DIR}"/commands/host/fire-worktree-* "${SITE}/.ddev/commands/host/"
  cp "${DIR}/fire-worktrees/lib.sh" "${SITE}/.ddev/fire-worktrees/"
  printf 'name: mysite\ntype: php\nweb_environment:\n    - WORKTREE_NAME_PREFIX=team\n    - WORKTREE_DB=fresh\n' >"${SITE}/.ddev/config.yaml"
  git -C "${SITE}" add -A
  git -C "${SITE}" commit -qm 'Add ddev-fire-worktrees'
}

# old_worktree: a worktree WT on a branch from before the add-on.
old_worktree() {
  WT="${TESTDIR}/my site-release-old"
  git -C "${SITE}" worktree add -q "${WT}" release/old
}

# section TITLE: the page's "## TITLE" section, without its heading.
section() {
  awk -v heading="## $1" '
    /^```/ { fence = !fence }
    !fence && /^## / { inside = ($0 == heading); next }
    inside
  ' "${PAGE}"
}

# shared_line setup|teardown: the line the "Any agent tool" section publishes,
# the first line of the first code block under "### The setup line" or
# "### The teardown line".
shared_line() {
  section 'Any agent tool' | awk -v heading="### The $1 line" '
    inside && fence { print; exit }
    inside && /^```/ { fence = 1; next }
    !fence && /^#/ { inside = ($0 == heading) }
  '
}

# tool_sections: the title of each tool's section, one per line: every "##"
# section but "Any agent tool".
tool_sections() {
  awk '
    /^```/ { fence = !fence }
    !fence && /^## / { title = substr($0, 4); if (title != "Any agent tool") print title }
  ' "${PAGE}"
}

# Tool sections whose tool runs nothing before deleting a worktree, so their
# recipes have no teardown line.
NO_TEARDOWN=(T3)

# tool_line TOOL setup|teardown: the line in TOOL's section of the page, with its
# file format's quoting undone. Each tool section needs a case here: pick out
# the quoted line, then pipe it through unquote with the file's format.
tool_line() {
  case "$1:$2" in
    T3:setup) t3_action 'Start worktree' ;;
    *)
      echo "tool_line has no case for the ${2} line in the ${1} section" >&2
      return 1
      ;;
  esac
}

# t3_action NAME: the command of the action NAME in the T3 section's t3.json.
t3_action() {
  section T3 | grep -F "{ \"name\": \"$1\"," | json_member command | unquote json
}

# json_member KEY: the quoted string value of the first "KEY": member on each
# line of stdin, quotes and escapes included.
json_member() {
  sed -nE 's/.*"'"$1"'": ("([^"\\]|\\.)*").*/\1/p'
}

# unquote FORMAT: undo FORMAT's quoting of the string literal on stdin.
unquote() {
  case $1 in
    # Strip the quotes and the backslash of each escape; the lines need no
    # escapes but \" and \\.
    json) sed -E 's/^"(.*)"$/\1/; s/\\(.)/\1/g' ;;
    *)
      echo "unquote knows no format ${1}" >&2
      return 1
      ;;
  esac
}

# project_of DIR: the DDEV project name startup gave DIR.
project_of() {
  awk '$1 == "name:" { print $2; exit }' "$1/.ddev/config.worktree.local.yaml"
}

@test "the setup line starts a worktree on a branch older than the add-on with the main checkout's copy and the team's prefix" {
  adopt_addon
  old_worktree

  line=$(shared_line setup)
  assert [ -n "${line}" ]
  cd "${WT}"
  run sh -c "${line}"
  assert_success
  assert_line --regexp '^Configured DDEV project team-release-old-[0-9]+$'
  run project_of "${WT}"
  assert_output --regexp '^team-release-old-[0-9]+$'
}

@test "the setup line runs the worktree's own copy when its branch has the add-on" {
  adopt_addon
  WT="${TESTDIR}/my site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  # The main checkout has since moved on to a copy that doesn't work.
  printf '#!/bin/sh\necho "main checkout copy" >&2\nexit 99\n' >"${SITE}/.ddev/commands/host/fire-worktree-start"

  cd "${WT}"
  run sh -c "$(shared_line setup)"
  assert_success
  assert_line --regexp '^Configured DDEV project team-feature-x-[0-9]+$'
  refute_output --partial "main checkout copy"
}

@test "the teardown line runs the main checkout's copy on a branch older than the add-on, and exits 0 when it fails" {
  adopt_addon
  old_worktree
  cd "${WT}"
  sh -c "$(shared_line setup)" >/dev/null

  line=$(shared_line teardown)
  assert [ -n "${line}" ]
  DDEV_DELETE_FAILS=1 run sh -c "${line}"
  assert_success
  assert_line --regexp '^  - Delete DDEV project team-release-old-[0-9]+, including its database and volumes\.$'
  assert_line 'Could not connect to a Docker provider.'
}

@test "T3CODE_PROJECT_ROOT naming another checkout changes nothing" {
  adopt_addon
  old_worktree
  # Another checkout with its own prefix and copies of the commands that don't
  # work, as T3 names when its project folder isn't the main checkout.
  OTHER="${TESTDIR}/other checkout"
  git -C "${SITE}" worktree add -q -b other "${OTHER}"
  printf 'name: mysite\ntype: php\nweb_environment:\n    - WORKTREE_NAME_PREFIX=other\n' >"${OTHER}/.ddev/config.yaml"
  for cmd in "${OTHER}"/.ddev/commands/host/fire-worktree-*; do
    printf '#!/bin/sh\necho "other checkout copy" >&2\nexit 99\n' >"${cmd}"
  done
  export T3CODE_PROJECT_ROOT="${OTHER}"

  cd "${WT}"
  run sh -c "$(shared_line setup)"
  assert_success
  assert_line --regexp '^Configured DDEV project team-release-old-[0-9]+$'
  refute_output --partial "other checkout copy"
  run sh -c "$(shared_line teardown)"
  assert_line --regexp '^  - Delete DDEV project team-release-old-[0-9]+, including its database and volumes\.$'
  refute_output --partial "other checkout copy"
}

@test "the lines run in sh, bash and zsh, under set -e and joined with &&" {
  adopt_addon
  old_worktree
  cd "${WT}"
  for shell in sh bash zsh; do
    command -v "${shell}" >/dev/null || continue
    echo "In ${shell}"
    run "${shell}" -c "set -e; $(shared_line setup) && echo 'setup done'"
    assert_success
    assert_line --regexp '^Configured DDEV project team-release-old-[0-9]+$'
    assert_line 'setup done'
    DDEV_DELETE_FAILS=1 run "${shell}" -c "set -e; $(shared_line teardown) && echo 'teardown done'"
    assert_success
    assert_line 'Could not connect to a Docker provider.'
    assert_line 'teardown done'
  done
}

@test "T3's manual actions run the main checkout's copy on a branch older than the add-on" {
  adopt_addon
  old_worktree
  cd "${WT}"
  sh -c "$(t3_action 'Start worktree')" >/dev/null

  # T3 runs actions in a terminal; here the confirmation prompt has none.
  run sh -c "$(t3_action 'Delete worktree environment')"
  assert_line --regexp '^  - Delete DDEV project team-release-old-[0-9]+, including its database and volumes\.$'
  run sh -c "$(t3_action 'Find orphaned worktree environments')"
  assert_success
  assert_line 'No DDEV projects to prune.'
}

@test "every tool section has the setup and teardown lines exactly as the Any agent tool section does" {
  setup_line=$(shared_line setup)
  teardown_line=$(shared_line teardown)
  assert [ -n "${setup_line}" ]
  assert [ -n "${teardown_line}" ]
  tools=$(tool_sections)
  assert [ -n "${tools}" ]

  while IFS= read -r tool; do
    echo "Checking the ${tool} section"
    run tool_line "${tool}" setup
    assert_success
    assert_output "${setup_line}"
    if [[ " ${NO_TEARDOWN[*]} " != *" ${tool} "* ]]; then
      run tool_line "${tool}" teardown
      assert_success
      assert_output "${teardown_line}"
    fi
  done <<<"${tools}"
}
