#!/usr/bin/env bats

# Fast tests of fire-worktrees/lib.sh. They need Git but not Docker or DDEV.
#   bats ./tests/lib.bats

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  # shellcheck source=fire-worktrees/lib.sh
  source "${DIR}/fire-worktrees/lib.sh"
  TESTDIR="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/fire-worktrees-lib.XXXXXX")" && pwd -P)"
  SITE="${TESTDIR}/site"
  mkdir -p "${SITE}/.ddev"
}

teardown() {
  rm -rf "${TESTDIR}"
}

# git_site: make SITE a Git repository with one commit.
git_site() {
  git -C "${SITE}" init -q -b main
  git -C "${SITE}" -c user.email=test@example.com -c user.name=Test add -A
  git -C "${SITE}" -c user.email=test@example.com -c user.name=Test commit -qm init
}

@test "reads the YAML that ddev config writes" {
  cat >"${SITE}/.ddev/config.yaml" <<'EOF'
name: "mysite" # a comment
type: drupal11
docroot: web
database:
    type: mariadb
    version: "10.11"
additional_hostnames:
    - sub.mysite
    - '*.mysite'

    # a comment between items
    - other.example
additional_fqdns: [one.example, "two.example"]
web_environment: []
EOF
  run fw::config_scalar "${SITE}" name
  assert_output "mysite"
  run fw::config_nested "${SITE}" database version
  assert_output "10.11"
  run fw::config_list "${SITE}" additional_hostnames
  assert_output "$(printf 'sub.mysite\n*.mysite\nother.example')"
  run fw::config_list "${SITE}" additional_fqdns
  assert_output "$(printf 'one.example\ntwo.example')"
  run fw::config_list "${SITE}" web_environment
  assert_output ""
}

@test "later config files override earlier ones, and generated files are skipped" {
  printf 'name: mysite\nweb_environment:\n  - WORKTREE_NAME_PREFIX=team\n  - WORKTREE_DB=fresh\n' >"${SITE}/.ddev/config.yaml"
  printf 'web_environment: [WORKTREE_NAME_PREFIX=mine]\n' >"${SITE}/.ddev/config.local.yaml"
  printf '%s\nname: mysite-wt-1\nweb_environment: [WORKTREE_DB=latest]\n' "${FW_MARKER}" >"${SITE}/.ddev/${FW_CONFIG_NAME}"
  run fw::setting "${SITE}" WORKTREE_NAME_PREFIX default
  assert_output "mine"
  run fw::setting "${SITE}" WORKTREE_DB primary
  assert_output "fresh"
  run fw::setting "${SITE}" WORKTREE_BASE_REF fallback
  assert_output "fallback"
  run fw::config_scalar "${SITE}" name
  assert_output "mysite"
  run fw::generated_name "${SITE}"
  assert_output "mysite-wt-1"
}

@test "a single-site project has no hostnames to rewrite" {
  printf 'name: mysite\ntype: drupal11\nadditional_hostnames: []\n' >"${SITE}/.ddev/config.yaml"
  run fw::rewrite_hostnames "${SITE}" mysite mysite-feature-1
  assert_success
  assert_output ""
}

@test "rewrites a multi-domain project's hostnames" {
  printf 'name: mysite\nadditional_hostnames:\n  - mysite\n  - news.mysite\n  - "*.mysite"\n  - other.example\n' >"${SITE}/.ddev/config.yaml"
  run fw::rewrite_hostnames "${SITE}" mysite wt-x-1
  assert_success
  assert_output "$(printf 'news.wt-x-1\n*.wt-x-1\nother.example.wt-x-1')"
}

@test "refuses a hostname label longer than 63 characters" {
  # Generated names stay under the limit; a name kept from older commands may not.
  printf 'name: mysite\nadditional_hostnames: [news.mysite]\n' >"${SITE}/.ddev/config.yaml"
  run fw::rewrite_hostnames "${SITE}" mysite "$(printf 'w%.0s' {1..63})"
  assert_success
  run fw::rewrite_hostnames "${SITE}" mysite "$(printf 'w%.0s' {1..64})"
  assert_failure
  assert_output --partial "longer than 63 characters"
}

@test "picks a build command for each kind of project" {
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "ddev drush deploy -y"
  printf 'type: drupal\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "ddev drush deploy -y"
  printf 'type: drupal7\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "ddev drush updb -y"
  printf 'type: php\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "none"

  # ddev-fire, when installed, builds the site.
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  mkdir -p "${SITE}/.ddev/commands/host"
  touch "${SITE}/.ddev/commands/host/fire-build"
  run fw::build_command "${SITE}"
  assert_output "ddev fire-build --no-db-import"

  # The project setting wins, and a developer can override it locally.
  printf 'type: drupal11\nweb_environment:\n  - WORKTREE_BUILD_COMMAND=fire build --no-db-import\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "fire build --no-db-import"
  printf 'web_environment: [WORKTREE_BUILD_COMMAND=none]\n' >"${SITE}/.ddev/config.local.yaml"
  run fw::build_command "${SITE}"
  assert_output "none"
}

@test "names the primary project from the primary checkout" {
  # Without name:, DDEV names each checkout after its directory.
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  git_site
  git -C "${SITE}" worktree add -q -b feature/x "${TESTDIR}/site-feature-x"
  fw::context "${TESTDIR}/site-feature-x"
  assert_equal "${FW_IS_PRIMARY}" false
  assert_equal "${FW_PRIMARY_ROOT}" "${SITE}"
  assert_equal "$(fw::primary_name)" "site"
  assert_equal "$(fw::project_name_of "${FW_ROOT}")" "site-feature-x"
}

@test "tells SQL dumps from ddev snapshots" {
  run fw::is_dump /x/reference/site-db.sql.gz
  assert_success
  run fw::is_dump /x/dump.sql
  assert_success
  run fw::is_dump /x/db.zip
  assert_success
  run fw::is_dump /x/.ddev/db_snapshots/fire-worktree-seed-20261006-mariadb_10.11.gz
  assert_failure
  run fw::is_dump /x/.ddev/db_snapshots/seed-mariadb_10.11.zst
  assert_failure
}

@test "makes DNS-safe slugs" {
  run fw::slug "Feature/ABC-123_Hero Banner" 80
  assert_output "feature-abc-123-hero-banner"
  run fw::slug "a-longer-project-name" 12
  assert_output "a-longer-pro"
  run fw::slug "abcdefghijk-xyz" 12
  assert_output "abcdefghijk"
}

@test "resolves a --db file from the caller's directory" {
  mkdir -p "${TESTDIR}/here/reference"
  touch "${TESTDIR}/here/reference/site-db.sql.gz"
  cd "${TESTDIR}/here"
  run fw::db_arg reference/site-db.sql.gz
  assert_output "${TESTDIR}/here/reference/site-db.sql.gz"
  run fw::db_arg latest
  assert_output "latest"
  run fw::db_arg missing.sql.gz
  assert_failure
  assert_output --partial "--db must be primary, latest, fresh"
}

@test "the first start honors the config.local.yaml it copies in" {
  # The team's settings, committed.
  cat >"${SITE}/.ddev/config.yaml" <<'YAML'
name: widener
type: php
additional_hostnames:
    - alumni.widener
web_environment:
    - WORKTREE_NAME_PREFIX=wid
YAML
  printf '/.ddev/config.local.yaml\n/notes.txt\n' >"${SITE}/.gitignore"
  git_site
  git -C "${SITE}" worktree add -q -b feature/x "${TESTDIR}/site-feature-x"
  # A developer's own settings, which only the primary checkout has so far.
  cat >"${SITE}/.ddev/config.local.yaml" <<'YAML'
web_environment:
    - WORKTREE_NAME_PREFIX=zz
    - WORKTREE_COPY_FILES=.ddev/config.local.yaml notes.txt
additional_hostnames:
    - extra.widener
YAML
  echo notes >"${SITE}/notes.txt"

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  run fw::start_worktree "${TESTDIR}/site-feature-x" fresh false
  assert_success
  assert_output --partial "Configured DDEV project zz-feature-x-"
  assert_output --partial "Copied notes.txt"
  run fw::yaml_list "${TESTDIR}/site-feature-x/.ddev/${FW_CONFIG_NAME}" additional_hostnames
  assert_output --regexp '^alumni\.zz-feature-x-[0-9]+
extra\.zz-feature-x-[0-9]+$'
}
