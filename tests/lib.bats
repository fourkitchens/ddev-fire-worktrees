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

  # ddev-fire, when installed, builds the site. A project's own site-build
  # command isn't ddev-fire's.
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  mkdir -p "${SITE}/.ddev/commands/host" "${SITE}/.ddev/fire/scripts"
  printf '#!/usr/bin/env bash\n## ProjectTypes: drupal, drupal10, drupal11\n' >"${SITE}/.ddev/commands/host/site-build"
  run fw::build_command "${SITE}"
  assert_output "ddev drush deploy -y"
  touch "${SITE}/.ddev/fire/scripts/lib.sh"
  run fw::build_command "${SITE}"
  assert_output "ddev site-build --skip-db-import"

  # DDEV hides site-build from project types it doesn't list.
  printf 'type: drupal7\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "ddev drush updb -y"

  # The project setting wins, and a developer can override it locally.
  printf 'type: drupal11\nweb_environment:\n  - WORKTREE_BUILD_COMMAND=fire build --no-db-import\n' >"${SITE}/.ddev/config.yaml"
  run fw::build_command "${SITE}"
  assert_output "fire build --no-db-import"
  printf 'web_environment: [WORKTREE_BUILD_COMMAND=none]\n' >"${SITE}/.ddev/config.local.yaml"
  run fw::build_command "${SITE}"
  assert_output "none"
}

@test "suggests how to fill an empty database" {
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  run fw::populate_hint "${SITE}"
  assert_output "ddev import-db --file=<dump>, or ddev pull <provider>"
  touch "${SITE}/fire.yml"
  run fw::populate_hint "${SITE}"
  assert_output "fire build"
  mkdir -p "${SITE}/.ddev/commands/host" "${SITE}/.ddev/fire/scripts"
  printf '#!/usr/bin/env bash\n## ProjectTypes: drupal, drupal10, drupal11\n' >"${SITE}/.ddev/commands/host/site-build"
  touch "${SITE}/.ddev/fire/scripts/lib.sh"
  run fw::populate_hint "${SITE}"
  assert_output "ddev site-build"
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

# snapshot_dirs: a primary checkout with a db_snapshots directory, and a
# worktree on the same database server.
snapshot_dirs() {
  FW_PRIMARY_ROOT="${SITE}"
  FW_ROOT="${TESTDIR}/site-feature-x"
  SNAPS="${SITE}/.ddev/db_snapshots"
  mkdir -p "${SNAPS}" "${FW_ROOT}/.ddev"
  printf 'name: mysite\ndatabase:\n  type: mariadb\n  version: "10.11"\n' >"${SITE}/.ddev/config.yaml"
  cp "${SITE}/.ddev/config.yaml" "${FW_ROOT}/.ddev/config.yaml"
}

@test "--db=latest reuses the last worktree copy, not a newer snapshot taken by hand" {
  snapshot_dirs
  touch -t 202610010000 "${SNAPS}/fire-worktree-seed-20261001000000-mariadb_10.11.gz"
  touch -t 202610020000 "${SNAPS}/before-experiment-mariadb_10.11.gz"
  run fw::seed_snapshot latest
  assert_success
  assert_output "${SNAPS}/fire-worktree-seed-20261001000000-mariadb_10.11.gz"
}

@test "--db=latest falls back to another snapshot, and names it" {
  snapshot_dirs
  touch -t 202610010000 "${SNAPS}/old-mariadb_10.11.gz"
  touch -t 202610020000 "${SNAPS}/before-experiment-mariadb_10.11.gz"
  # A seed snapshot for another database server doesn't count.
  touch -t 202610030000 "${SNAPS}/fire-worktree-seed-20261003000000-mysql_8.0.gz"
  touch -t 202610040000 "${SNAPS}/newer-mysql_8.0.gz"
  run fw::seed_snapshot latest
  assert_success
  assert_output --partial "No earlier worktree copy to reuse, so using the snapshot before-experiment-mariadb_10.11.gz."
  assert_line --index 1 "${SNAPS}/before-experiment-mariadb_10.11.gz"

  rm -f "${SNAPS}"/*mariadb*
  run fw::seed_snapshot latest
  assert_failure
  assert_output --partial "no database snapshot to copy"
}

@test "--db=primary falls back to the last worktree copy when it can't snapshot" {
  snapshot_dirs
  ddev() { return 1; }
  touch -t 202610010000 "${SNAPS}/fire-worktree-seed-20261001000000-mariadb_10.11.gz"
  touch -t 202610020000 "${SNAPS}/before-experiment-mariadb_10.11.gz"
  run fw::seed_snapshot primary
  assert_success
  assert_output --partial "Couldn't snapshot mysite."
  assert_output --partial "Using the older snapshot fire-worktree-seed-20261001000000-mariadb_10.11.gz instead."
  assert_line --index 3 "${SNAPS}/fire-worktree-seed-20261001000000-mariadb_10.11.gz"

  rm -f "${SNAPS}"/fire-worktree-seed-*
  run fw::seed_snapshot primary
  assert_success
  assert_output --partial "Using the older snapshot before-experiment-mariadb_10.11.gz instead."
}

@test "makes DNS-safe slugs" {
  run fw::slug "Feature/ABC-123_Hero Banner" 80
  assert_output "feature-abc-123-hero-banner"
  run fw::slug "a-longer-project-name" 12
  assert_output "a-longer-pro"
  run fw::slug "abcdefghijk-xyz" 12
  assert_output "abcdefghijk"
}

@test "names the Compose project whose label marks a project's volumes" {
  run fw::compose_project "fwtest-feature-one-123"
  assert_output "ddev-fwtest-feature-one-123"
  run fw::compose_project "My.Site"
  assert_output "ddev-mysite"
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
name: mysite
type: php
additional_hostnames:
    - alumni.mysite
web_environment:
    - WORKTREE_NAME_PREFIX=team
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
    - extra.mysite
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

@test "parallel registry writes keep every entry" {
  printf 'name: mysite\n' >"${SITE}/.ddev/config.yaml"
  git_site
  fw::context "${SITE}"
  local i
  for i in $(seq 1 10); do
    fw::registry_add "old-$i" "/old/$i"
  done
  # Starts add entries while removes and prunes drop others.
  for i in $(seq 1 10); do
    fw::registry_add "new-$i" "/new/$i" &
    fw::registry_remove "old-$i" &
  done
  wait
  run sort "$(fw::registry_file)"
  assert_output "$(for i in $(seq 1 10); do printf 'new-%s\t/new/%s\n' "$i" "$i"; done | sort)"
}

@test "clears a registry lock left by a crashed run" {
  printf 'name: mysite\n' >"${SITE}/.ddev/config.yaml"
  git_site
  fw::context "${SITE}"
  # A pid that has exited.
  sh -c 'exit 0' &
  local pid=$!
  wait "$pid"
  mkdir "$(fw::registry_file).lock"
  echo "$pid" >"$(fw::registry_file).lock/pid"
  run fw::registry_add one /one
  assert_success
  run cat "$(fw::registry_file)"
  assert_output "$(printf 'one\t/one')"
  assert [ ! -e "$(fw::registry_file).lock" ]
}

@test "parallel starts record every worktree" {
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git_site
  local i
  for i in 1 2 3 4; do
    git -C "${SITE}" worktree add -q -b "feature/$i" "${TESTDIR}/site-feature-$i"
  done

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  for i in 1 2 3 4; do
    (fw::start_worktree "${TESTDIR}/site-feature-$i" fresh false >/dev/null) &
  done
  wait
  cut -f2 "${SITE}/.git/fire-worktrees" | sort >"${TESTDIR}/recorded"
  run cat "${TESTDIR}/recorded"
  assert_output "$(printf '%s\n' "${TESTDIR}"/site-feature-{1,2,3,4} | sort)"
  run grep -cxF "/.ddev/${FW_CONFIG_NAME}" "${SITE}/.git/info/exclude"
  assert_output 1
}
