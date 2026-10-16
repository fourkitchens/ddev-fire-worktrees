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

# fake_ddev_fire DIR: install ddev-fire's site-build command and library in DIR.
fake_ddev_fire() {
  mkdir -p "$1/.ddev/commands/host" "$1/.ddev/fire/scripts"
  printf '#!/usr/bin/env bash\n## ProjectTypes: drupal, drupal10, drupal11\n' >"$1/.ddev/commands/host/site-build"
  touch "$1/.ddev/fire/scripts/lib.sh"
}

@test "the project type picks the toolchain's base" {
  printf 'type: drupal11\ndocroot: web\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush deploy -y"
  assert_equal "${FW_TOOLCHAIN_HINT}" "ddev import-db --file=<dump>, or ddev pull <provider>"
  assert_equal "${FW_TOOLCHAIN_ADVICE}" ""
  assert_equal "${FW_TOOLCHAIN_LOGIN}" true
  assert_equal "${FW_TOOLCHAIN_COPY_FILES}" ".ddev/config.local.yaml web/sites/default/settings.local.php"
  printf 'type: drupal\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush deploy -y"
  assert_equal "${FW_TOOLCHAIN_COPY_FILES}" ".ddev/config.local.yaml sites/default/settings.local.php"
  printf 'type: drupal7\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush updb -y"
  assert_equal "${FW_TOOLCHAIN_LOGIN}" true
  printf 'type: php\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "none"
  assert_equal "${FW_TOOLCHAIN_LOGIN}" false
  assert_equal "${FW_TOOLCHAIN_COPY_FILES}" ".ddev/config.local.yaml sites/default/settings.local.php"
}

@test "ddev-fire's overlay builds the site where DDEV offers its site-build" {
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  # A project's own site-build isn't ddev-fire's.
  mkdir -p "${SITE}/.ddev/commands/host"
  printf '#!/usr/bin/env bash\n## ProjectTypes: drupal11\n' >"${SITE}/.ddev/commands/host/site-build"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush deploy -y"
  fake_ddev_fire "${SITE}"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev site-build --skip-db-import"
  assert_equal "${FW_TOOLCHAIN_HINT}" "ddev site-build"
  assert_equal "${FW_TOOLCHAIN_LOGIN}" true

  # DDEV hides site-build from project types it doesn't list.
  printf 'type: drupal7\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush updb -y"
  assert_equal "${FW_TOOLCHAIN_HINT}" "ddev import-db --file=<dump>, or ddev pull <provider>"
}

@test "the FIRE CLI's overlay suggests fire build, and ddev-fire's wins over it" {
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  touch "${SITE}/fire.yml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush deploy -y"
  assert_equal "${FW_TOOLCHAIN_HINT}" "fire build"
  run printf '%s' "${FW_TOOLCHAIN_ADVICE}"
  assert_line --index 0 "This project uses FIRE, and drush deploy doesn't build its theme. To build everything"
  assert_output --partial "set WORKTREE_BUILD_COMMAND=fire build --no-db-import."

  # A project type with no build gets no advice about one.
  printf 'type: php\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_HINT}" "fire build"
  assert_equal "${FW_TOOLCHAIN_ADVICE}" ""

  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  fake_ddev_fire "${SITE}"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev site-build --skip-db-import"
  assert_equal "${FW_TOOLCHAIN_HINT}" "ddev site-build"
  assert_equal "${FW_TOOLCHAIN_ADVICE}" ""
}

@test "the project's settings win over the toolchain" {
  printf 'type: drupal11\nweb_environment:\n  - WORKTREE_BUILD_COMMAND=fire build --no-db-import\n  - WORKTREE_COPY_FILES=.env\n' >"${SITE}/.ddev/config.yaml"
  touch "${SITE}/fire.yml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "fire build --no-db-import"
  assert_equal "${FW_TOOLCHAIN_HINT}" "fire build"
  assert_equal "${FW_TOOLCHAIN_ADVICE}" ""
  assert_equal "${FW_TOOLCHAIN_COPY_FILES}" ".env"

  # A developer can override the team's setting locally.
  printf 'web_environment: [WORKTREE_BUILD_COMMAND=none]\n' >"${SITE}/.ddev/config.local.yaml"
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "none"
}

@test "without the Fire overlays, a FIRE project gets the Drupal base" {
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  touch "${SITE}/fire.yml"
  fake_ddev_fire "${SITE}"
  FW_TOOLCHAIN_OVERLAYS=()
  fw::toolchain "${SITE}"
  assert_equal "${FW_TOOLCHAIN_BUILD}" "ddev drush deploy -y"
  assert_equal "${FW_TOOLCHAIN_HINT}" "ddev import-db --file=<dump>, or ddev pull <provider>"
  assert_equal "${FW_TOOLCHAIN_ADVICE}" ""
  assert_equal "${FW_TOOLCHAIN_LOGIN}" true
}

@test "only a toolchain that can log in makes a login link" {
  ddev() { echo "${4#--uri=}/user/reset/1/abc/def/login"; }
  printf 'type: php\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  run fw::toolchain_login_link https://x.ddev.site
  assert_failure
  assert_output ""
  printf 'type: drupal11\n' >"${SITE}/.ddev/config.yaml"
  fw::toolchain "${SITE}"
  run fw::toolchain_login_link https://x.ddev.site
  assert_success
  assert_output "https://x.ddev.site/user/reset/1/abc/def/login"
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

@test "copies local files from T3CODE_PROJECT_ROOT rather than the primary" {
  printf 'name: mysite\ntype: php\ndocroot: web\n' >"${SITE}/.ddev/config.yaml"
  printf '/.ddev/config.local.yaml\n/web/sites/default/settings.local.php\n' >"${SITE}/.gitignore"
  git_site
  git -C "${SITE}" worktree add -q -b feature/x "${TESTDIR}/site-feature-x"
  # The checkout T3 names has both files on the default WORKTREE_COPY_FILES
  # list. The primary has only an older settings.local.php.
  T3_ROOT="${TESTDIR}/t3-root"
  mkdir -p "${T3_ROOT}/.ddev" "${T3_ROOT}/web/sites/default" "${SITE}/web/sites/default"
  printf 'xdebug_enabled: true\n' >"${T3_ROOT}/.ddev/config.local.yaml"
  echo '<?php // from T3' >"${T3_ROOT}/web/sites/default/settings.local.php"
  echo '<?php // from the primary' >"${SITE}/web/sites/default/settings.local.php"

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT
  T3CODE_PROJECT_ROOT="${T3_ROOT}"
  run fw::start_worktree "${TESTDIR}/site-feature-x" fresh false
  assert_success
  assert_output --partial "Copied .ddev/config.local.yaml"
  assert_output --partial "Copied web/sites/default/settings.local.php"
  run cat "${TESTDIR}/site-feature-x/web/sites/default/settings.local.php"
  assert_output '<?php // from T3'
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
  run grep -cxF "/.ddev/${FW_LOG_NAME}" "${SITE}/.git/info/exclude"
  assert_output 1
}

@test "reads WORKTREE_BUILD_FAILURE" {
  printf 'type: php
' >"${SITE}/.ddev/config.yaml"
  run fw::build_failure "${SITE}"
  assert_output "fail"
  printf 'web_environment: [WORKTREE_BUILD_FAILURE=warn]\n' >"${SITE}/.ddev/config.local.yaml"
  run fw::build_failure "${SITE}"
  assert_output "warn"
  printf 'web_environment: [WORKTREE_BUILD_FAILURE=ignore]\n' >"${SITE}/.ddev/config.local.yaml"
  run fw::build_failure "${SITE}"
  assert_failure
  assert_output "WORKTREE_BUILD_FAILURE must be fail or warn; got ignore."
}

@test "a failed build prints the URLs and the log, and warn exits 0" {
  cat >"${SITE}/.ddev/config.yaml" <<'YAML'
name: mysite
type: php
web_environment:
    - WORKTREE_BUILD_COMMAND=echo deploy-error && false
YAML
  git_site
  WT="${TESTDIR}/site-feature-x"
  LOG="${WT}/.ddev/${FW_LOG_NAME}"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  # A dump, so every start imports it and builds.
  touch "${TESTDIR}/site-db.sql.gz"

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true
  assert_failure
  NAME=$(fw::yaml_scalar "${WT}/.ddev/${FW_CONFIG_NAME}" name)
  local n=${#lines[@]}
  assert_equal "${lines[n-4]}" "Worktree URLs:"
  assert_equal "${lines[n-3]}" "  https://${NAME}.ddev.site"
  assert_equal "${lines[n-2]}" "The worktree is running, but the build failed. Fix the error, then run: echo deploy-error && false"
  assert_equal "${lines[n-1]}" "Startup log: ${LOG}"
  run cat "${LOG}"
  assert_line --index 0 --regexp '^=== [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}: fire-worktree-start$'
  assert_line "deploy-error"
  assert_line "The worktree is running, but the build failed. Fix the error, then run: echo deploy-error && false"
  run git -C "${WT}" status --porcelain
  assert_output ""

  printf 'web_environment: [WORKTREE_BUILD_FAILURE=warn]\n' >"${WT}/.ddev/config.local.yaml"
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true
  assert_success
  n=${#lines[@]}
  assert_equal "${lines[n-3]}" "  https://${NAME}.ddev.site"
  assert_equal "${lines[n-2]}" "Warning: The worktree is running, but the build failed. Fix the error, then run: echo deploy-error && false"
  assert_equal "${lines[n-1]}" "Startup log: ${LOG}"
  # Each start adds to the log, so a rerun keeps the failure it follows.
  run grep -c '^=== ' "${LOG}"
  assert_output 2
}

@test "start prints the toolchain's advice after a database copy" {
  printf 'name: mysite\ntype: drupal11\n' >"${SITE}/.ddev/config.yaml"
  git_site
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  touch "${WT}/fire.yml" "${TESTDIR}/site-db.sql.gz"

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" false
  assert_success
  assert_line "Skipped the build. To run it: ddev drush deploy -y"
  assert_line "This project uses FIRE, and drush deploy doesn't build its theme. To build everything"
  assert_line --partial "in the add-on's docs/drupal.md."
}

@test "startup stops at the first error and points to the log" {
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git_site
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"

  # Run the command itself, which sets -e, without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  export -f ddev docker
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  cd "${WT}"
  # The primary checkout has no snapshot for --db=latest to reuse.
  TMPDIR="${TESTDIR}" run "${DIR}/commands/host/fire-worktree-start" --db=latest
  assert_failure
  assert_line "The primary checkout has no database snapshot to copy. Start its project, or use --db=fresh."
  refute_output --partial "Worktree URLs"
  assert_line "Startup log: ${WT}/.ddev/${FW_LOG_NAME}"
  assert [ ! -e "${TESTDIR}/ddev-fire-worktrees.lock" ]
  run cat "${WT}/.ddev/${FW_LOG_NAME}"
  assert_line "Configured DDEV project $(fw::yaml_scalar "${WT}/.ddev/${FW_CONFIG_NAME}" name)"
  assert_line "The primary checkout has no database snapshot to copy. Start its project, or use --db=fresh."
}

@test "finds web_environment URLs that point a worktree at the primary site" {
  cat >"${SITE}/.ddev/config.yaml" <<'YAML'
name: mysite
additional_hostnames:
    - news.mysite
    - other.example
web_environment:
    - DRUSH_OPTIONS_URI=https://mysite.ddev.site
    - SIMPLETEST_BASE_URL=http://news.mysite.ddev.site:8080/
    - PARTNER_URL=https://other.example.ddev.site
    - FIXED_URI=https://www.mysite.ddev.site
    - PORTABLE_URI=https://www.${DDEV_SITENAME}.${DDEV_TLD}
    - LOOKALIKES=https://mysite.ddev.site.example https://wt-mysite.ddev.site
YAML
  # A developer's override replaces the team's value, as in DDEV.
  printf 'web_environment: [FIXED_URI=$DDEV_PRIMARY_URL]\n' >"${SITE}/.ddev/config.local.yaml"
  run fw::primary_url_settings "${SITE}" mysite
  assert_success
  assert_output "$(printf '%s\n' DRUSH_OPTIONS_URI=https://mysite.ddev.site SIMPLETEST_BASE_URL=http://news.mysite.ddev.site:8080/ PARTNER_URL=https://other.example.ddev.site)"

  printf 'name: mysite\n' >"${SITE}/.ddev/config.yaml"
  rm "${SITE}/.ddev/config.local.yaml"
  run fw::primary_url_settings "${SITE}" mysite
  assert_success
  assert_output ""
}

# drupal_worktree: a Drupal project whose Drush URI names the primary site, and
# a worktree of it at WT. Starts run without Docker or DDEV; ddev drush uli
# prints a link to the --uri it gets.
drupal_worktree() {
  printf 'name: mysite\ntype: drupal11\nadditional_hostnames: [news.mysite]\nweb_environment:\n  - DRUSH_OPTIONS_URI=https://mysite.ddev.site\n' >"${SITE}/.ddev/config.yaml"
  git_site
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  FW_LOCK="${TESTDIR}/lock"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  ddev() {
    if [[ "$*" == 'drush uli --no-browser --uri='* ]]; then
      echo "${4#--uri=}/user/reset/1/abc/def/login"
    fi
  }
  docker() { :; }
}

@test "start ends with a login link to the worktree when the site has a database" {
  drupal_worktree
  run fw::start_worktree "${WT}" fresh false
  assert_success
  assert_output --partial "Warning: This worktree inherits DRUSH_OPTIONS_URI=https://mysite.ddev.site from web_environment"
  assert_output --partial "To populate the database"
  refute_output --partial "login link"

  # On a rerun the database exists.
  NAME=$(fw::generated_name "${WT}")
  docker() { echo "${NAME}-mariadb"; }
  run fw::start_worktree "${WT}" "" false
  assert_success
  assert_line --index 0 "Configured DDEV project ${NAME}"
  assert_output --partial "$(printf 'Worktree URLs:\n  https://%s.ddev.site\n  https://news.%s.ddev.site\n' "${NAME}" "${NAME}")"
  assert_line "One-time login link: https://${NAME}.ddev.site/user/reset/1/abc/def/login"

  # Drush fails, for example because the site isn't installed.
  ddev() { [[ "$1" != drush ]]; }
  run fw::start_worktree "${WT}" "" false
  assert_success
  assert_output --partial "Warning: Couldn't create a login link. Try: ddev drush uli --uri=https://${NAME}.ddev.site"
}

@test "records where a worktree's database came from" {
  drupal_worktree
  fw::context "${WT}"
  run fw::db_source
  assert_output "$(printf 'unknown\t')"

  run fw::start_worktree "${WT}" fresh false
  assert_success
  run fw::db_source
  assert_output "$(printf 'fresh\t')"

  # A rerun keeps the database, so the record stays.
  NAME=$(fw::generated_name "${WT}")
  docker() { echo "${NAME}-mariadb"; }
  touch "${TESTDIR}/dump.sql.gz"
  run fw::start_worktree "${WT}" "${TESTDIR}/dump.sql.gz" false
  assert_success
  run fw::db_source
  assert_output "$(printf 'fresh\t')"

  fw::record_db "${TESTDIR}/dump.sql.gz" "${TESTDIR}/dump.sql.gz"
  run fw::db_source
  assert_output "$(printf 'dump\t%s' "${TESTDIR}/dump.sql.gz")"
  fw::record_db primary "${SITE}/.ddev/db_snapshots/fire-worktree-seed-1-mariadb_10.11.gz"
  run fw::db_source
  assert_output "$(printf 'primary\t%s' "${SITE}/.ddev/db_snapshots/fire-worktree-seed-1-mariadb_10.11.gz")"
}

@test "fire-worktree-info describes a worktree as text and JSON" {
  drupal_worktree
  run fw::start_worktree "${WT}" fresh false
  assert_success
  NAME=$(fw::generated_name "${WT}")
  INFO="${DIR}/commands/host/fire-worktree-info"

  # The command runs in its own process, so export the stand-ins.
  docker() { :; }
  export -f ddev docker
  cd "${SITE}"
  run "${INFO}"
  assert_failure
  assert_output --partial "is the primary checkout"
  git -C "${SITE}" worktree add -q -b feature/y "${TESTDIR}/site-feature-y"
  cd "${TESTDIR}/site-feature-y"
  run "${INFO}"
  assert_failure
  assert_output --partial "Run: ddev fire-worktree-start"

  cd "${WT}/.ddev"
  run "${INFO}"
  assert_success
  assert_output "$(printf 'Project:   %s (not started)\nURLs:      https://%s.ddev.site\n           https://news.%s.ddev.site\nDatabase:  empty (--db=fresh)\nLogin:     start the project with ddev start, then rerun this command' "${NAME}" "${NAME}" "${NAME}")"

  docker() { [[ "$1" != ps ]] || echo "ddev-${NAME}-web"; }
  export -f docker
  export NAME
  run "${INFO}" --json
  assert_success
  assert_output "$(printf '{\n  "name": "%s",\n  "status": "running",\n  "urls": ["https://%s.ddev.site", "https://news.%s.ddev.site"],\n  "database": {"source": "fresh", "file": null},\n  "login_url": "https://%s.ddev.site/user/reset/1/abc/def/login"\n}' "${NAME}" "${NAME}" "${NAME}" "${NAME}")"
  run "${INFO}" --bogus
  assert_failure
  assert_output "Usage: ddev fire-worktree-info [--json]"
}
