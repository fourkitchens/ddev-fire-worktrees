#!/usr/bin/env bats

# Fast tests of fire-worktrees/lib.sh. They need Git but not Docker or DDEV.
#   bats ./tests/lib.bats

bats_require_minimum_version 1.5.0

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-support

  DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  TESTDIR="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/fire-worktrees-lib.XXXXXX")" && pwd -P)"
  # The start lock lives in DDEV's global directory, which DDEV names to the
  # commands it runs. Keep it here, also for the commands tests run.
  export DDEV_GLOBAL_DIR="${TESTDIR}/ddev"
  mkdir -p "${DDEV_GLOBAL_DIR}"
  # shellcheck source=fire-worktrees/lib.sh
  source "${DIR}/fire-worktrees/lib.sh"
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

@test "settings a worktree's config files lack come from WORKTREE_SOURCE_ROOT" {
  # The checkout that ran create, on a commit with the team's settings.
  SOURCE="${TESTDIR}/source"
  mkdir -p "${SOURCE}/.ddev"
  printf 'name: mysite\ntype: drupal11\nweb_environment:\n  - WORKTREE_NAME_PREFIX=team\n  - WORKTREE_BUILD_COMMAND=team-build\n' >"${SOURCE}/.ddev/config.yaml"
  printf 'web_environment: [WORKTREE_DB=fresh]\n' >"${SOURCE}/.ddev/config.local.yaml"
  # A branch from before them, with a config.local.yaml of its own.
  printf 'name: mysite\ntype: drupal11\nweb_environment: []\n' >"${SITE}/.ddev/config.yaml"
  printf 'web_environment: [WORKTREE_BUILD_COMMAND=my-build]\n' >"${SITE}/.ddev/config.local.yaml"

  unset T3CODE_PROJECT_ROOT
  WORKTREE_SOURCE_ROOT="${SOURCE}"
  run fw::setting "${SITE}" WORKTREE_NAME_PREFIX default
  assert_output "team"
  run fw::setting "${SITE}" WORKTREE_DB primary
  assert_output "fresh"
  run fw::build_command "${SITE}"
  assert_output "my-build"
  run fw::setting "${SITE}" WORKTREE_BASE_REF fallback
  assert_output "fallback"

  unset WORKTREE_SOURCE_ROOT
  run fw::setting "${SITE}" WORKTREE_NAME_PREFIX default
  assert_output "default"
  # A source without a DDEV project adds nothing.
  WORKTREE_SOURCE_ROOT="${TESTDIR}/missing"
  run fw::setting "${SITE}" WORKTREE_DB primary
  assert_success
  assert_output "primary"
}

@test "settings a worktree's config files lack come from T3CODE_PROJECT_ROOT, unless create names a checkout" {
  # The checkout T3 names, and one that ran create, each with its own prefix.
  T3_ROOT="${TESTDIR}/t3-root"
  SOURCE="${TESTDIR}/source"
  mkdir -p "${T3_ROOT}/.ddev" "${SOURCE}/.ddev"
  printf 'name: mysite\ntype: drupal11\nweb_environment:\n  - WORKTREE_NAME_PREFIX=t3\n  - WORKTREE_DB=fresh\n' >"${T3_ROOT}/.ddev/config.yaml"
  printf 'name: mysite\ntype: drupal11\nweb_environment:\n  - WORKTREE_NAME_PREFIX=create\n' >"${SOURCE}/.ddev/config.yaml"
  # A branch from before them.
  printf 'name: mysite\ntype: drupal11\nweb_environment: []\n' >"${SITE}/.ddev/config.yaml"

  unset WORKTREE_SOURCE_ROOT
  T3CODE_PROJECT_ROOT="${T3_ROOT}"
  run fw::setting "${SITE}" WORKTREE_NAME_PREFIX default
  assert_output "t3"
  run fw::setting "${SITE}" WORKTREE_DB primary
  assert_output "fresh"

  WORKTREE_SOURCE_ROOT="${SOURCE}"
  run fw::setting "${SITE}" WORKTREE_NAME_PREFIX default
  assert_output "create"
  # Only one checkout fills in settings, so T3's WORKTREE_DB doesn't apply.
  run fw::setting "${SITE}" WORKTREE_DB primary
  assert_output "primary"
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
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  run fw::start_worktree "${TESTDIR}/site-feature-x" fresh false
  assert_success
  assert_output --partial "Configured DDEV project zz-feature-x-"
  assert_output --partial "Copied notes.txt"
  run fw::yaml_list "${TESTDIR}/site-feature-x/.ddev/${FW_CONFIG_NAME}" additional_hostnames
  assert_output --regexp '^alumni\.zz-feature-x-[0-9]+
extra\.zz-feature-x-[0-9]+$'
}

@test "an existing worktree keeps the name an earlier version gave it" {
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git_site
  # A pull request's base worktree from v0.2.0, which cut -base off long names.
  WT="${TESTDIR}/site-feature-add-retry-logic-to-deploy-base"
  git -C "${SITE}" worktree add -q --detach "${WT}"
  printf '%s\noverride_config: true\nname: mysite-feature-add-retry-logic-2792006950\n' "${FW_MARKER}" >"${WT}/.ddev/${FW_CONFIG_NAME}"

  # Start without Docker or DDEV.
  ddev() { :; }
  docker() { :; }
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  run fw::start_worktree "${WT}" fresh false
  assert_success
  assert_line "Configured DDEV project mysite-feature-add-retry-logic-2792006950"
  assert_equal "$(fw::generated_name "${WT}")" mysite-feature-add-retry-logic-2792006950
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
  unset WORKTREE_SOURCE_ROOT
  T3CODE_PROJECT_ROOT="${T3_ROOT}"
  run fw::start_worktree "${TESTDIR}/site-feature-x" fresh false
  assert_success
  assert_output --partial "Copied .ddev/config.local.yaml"
  assert_output --partial "Copied web/sites/default/settings.local.php"
  run cat "${TESTDIR}/site-feature-x/web/sites/default/settings.local.php"
  assert_output '<?php // from T3'
}

@test "prune lists unregistered projects with the primary checkout's prefix from any checkout" {
  printf 'name: mysite\ntype: php\n' >"${SITE}/.ddev/config.yaml"
  git_site
  # A branch from before the project set its prefix.
  git -C "${SITE}" worktree add -q -b feature/old "${TESTDIR}/site-feature-old"
  printf 'name: mysite\ntype: php\nweb_environment:\n  - WORKTREE_NAME_PREFIX=team\n' >"${SITE}/.ddev/config.yaml"
  git -C "${SITE}" -c user.email=test@example.com -c user.name=Test commit -qam 'Add the prefix'

  # Volumes of projects no registry entry names: one from before the prefix,
  # one created with it, and one whose database prune already deleted.
  docker() {
    case $* in
      'volume ls -q') printf 'mysite-gone-1-mariadb\nteam-gone-2-mariadb\nother-gone-3-mariadb\n' ;;
      'volume ls --filter '*) echo ddev-team-gone-4 ;;
    esac
  }
  ddev() { :; }
  export -f ddev docker
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  cd "${TESTDIR}/site-feature-old"
  run "${DIR}/commands/host/fire-worktree-prune"
  assert_success
  assert_line "No DDEV projects to prune."
  assert_line "  mysite-gone-1"
  assert_line "  team-gone-2"
  assert_line "  team-gone-4"
  refute_output --partial other-gone-3
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

@test "starts take turns whatever their TMPDIR" {
  mkdir -p "${TESTDIR}/tmp-login" "${TESTDIR}/tmp-agent"
  # A start from a login shell holds the start lock...
  TMPDIR="${TESTDIR}/tmp-login" bash -c 'source "$1"; fw::lock && touch "$2" && exec sleep 30' \
    _ "${DIR}/fire-worktrees/lib.sh" "${TESTDIR}/held" 3>&- &
  local holder=$!
  while [ ! -e "${TESTDIR}/held" ] && kill -0 "$holder" 2>/dev/null; do sleep 0.1; done
  # ...so one from a cron job or sandboxed agent, with its own TMPDIR, can't take it.
  TMPDIR="${TESTDIR}/tmp-agent" run bash -c 'source "$1"; fw::try_lock "$FW_LOCK"' \
    _ "${DIR}/fire-worktrees/lib.sh"
  kill "$holder"
  assert_failure
  assert [ -d "${DDEV_GLOBAL_DIR}/fire-worktree-start.lock" ]
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
  run "${DIR}/commands/host/fire-worktree-start" --db=latest
  assert_failure
  assert_line "The primary checkout has no database snapshot to copy. Start its project, or use --db=fresh."
  refute_output --partial "Worktree URLs"
  assert_line "Startup log: ${WT}/.ddev/${FW_LOG_NAME}"
  assert [ ! -e "${FW_LOCK}" ]
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

# drupal_site: make SITE a Drupal project with docroot web, the project
# fw::login_link runs in.
drupal_site() {
  printf 'name: mysite\ntype: drupal11\ndocroot: web\n' >"${SITE}/.ddev/config.yaml"
  FW_ROOT="${SITE}"
}

@test "finds the login link after a warning Drupal prints on the same line" {
  drupal_site
  # A warning from settings.php reaches stdout as HTML with no newline at the
  # end, so the link drush prints starts on its last line. The warning can name
  # a URL of its own, and the lines can end in CRLF.
  ddev() {
    printf '%s\r\n%s\r\n%s%s\r\n' \
      '<details class="error-with-backtrace"><summary><em class="placeholder">Warning</em>: file_get_contents(https://example.com/branch.txt): Failed to open stream in <em class="placeholder">include()</em> (line <em class="placeholder">5</em> of <em class="placeholder">sites/default/settings.php</em>).</summary><pre class="backtrace">include() (Line: 5)' \
      'Drupal\Core\Site\Settings::initialize() (Line: 1110)' \
      '</pre></details>' "${4#--uri=}/user/reset/1/1792195923/abc/login"
  }
  run fw::login_link https://mysite-feature-x.ddev.site
  assert_success
  assert_output "https://mysite-feature-x.ddev.site/user/reset/1/1792195923/abc/login"
}

GIT_METADATA_ADVICE="reads Git metadata, which a worktree's container doesn't have, so Drupal prints PHP warnings on every page and Drush command. Skip that code when .git/HEAD isn't readable. See https://github.com/fourkitchens/ddev-fire-worktrees/blob/main/docs/drupal.md#drupal-notes"

# assert_login_link_warns WARNING: in drupal_site, where ddev drush uli prints
# what drush_uli_output prints and then a link, fw::login_link gives the link
# and prints WARNING to stderr, or nothing when WARNING is empty.
assert_login_link_warns() {
  drupal_site
  ddev() {
    drush_uli_output
    echo "${4#--uri=}/user/reset/1/abc/def/login"
  }
  run --separate-stderr fw::login_link https://mysite-feature-x.ddev.site
  assert_success
  assert_output "https://mysite-feature-x.ddev.site/user/reset/1/abc/def/login"
  assert_equal "$stderr" "$1"
}

@test "warns once, naming the settings line, when Drupal's warnings show it reading Git metadata" {
  # What ddev drush uli printed to stdout in a worktree whose settings.php
  # reads ../.git/HEAD.
  drush_uli_output() { cat "${DIR}/tests/testdata/drush-uli-git-head-html.txt"; }
  assert_login_link_warns "Warning: web/sites/default/settings.php line 137 ${GIT_METADATA_ADVICE}"
}

@test "names the line of a file outside the docroot that Drupal's warning shows reading Git metadata" {
  # Drupal names a file under the docroot relative to it, and any other by its
  # container path.
  drush_uli_output() {
    printf '%s\n' '<details class="error-with-backtrace"><summary><em class="placeholder">Warning</em>: file(/var/www/html/.git/HEAD): Failed to open stream: No such file or directory in <em class="placeholder">include()</em> (line <em class="placeholder">4</em> of <em class="placeholder">/var/www/html/config/git.php</em>).</summary><pre class="backtrace">include() (Line: 4)</pre></details>'
  }
  assert_login_link_warns "Warning: config/git.php line 4 ${GIT_METADATA_ADVICE}"
}

@test "names the settings line from PHP's own warning, without the container's project root" {
  drush_uli_output() { cat "${DIR}/tests/testdata/drush-uli-git-head-php.txt" >&2; }
  assert_login_link_warns "Warning: web/sites/default/settings.php line 137 ${GIT_METADATA_ADVICE}"
}

@test "warns generically when settings run git and the container says it's not a repository" {
  drush_uli_output() { cat "${DIR}/tests/testdata/drush-uli-not-a-git-repository.txt" >&2; }
  assert_login_link_warns "Warning: Drupal ${GIT_METADATA_ADVICE}"
}

@test "warns generically about any Git metadata path that comes without a file and line" {
  drush_uli_output() { echo 'file_get_contents(/var/www/html/.git/refs/heads/main): Failed to open stream: No such file or directory'; }
  assert_login_link_warns "Warning: Drupal ${GIT_METADATA_ADVICE}"
}

@test "warns once however many times Drush's output shows Git metadata" {
  drush_uli_output() {
    cat "${DIR}/tests/testdata/drush-uli-git-head-html.txt" "${DIR}/tests/testdata/drush-uli-git-head-html.txt"
    cat "${DIR}/tests/testdata/drush-uli-git-head-php.txt" "${DIR}/tests/testdata/drush-uli-not-a-git-repository.txt" >&2
  }
  assert_login_link_warns "Warning: web/sites/default/settings.php line 137 ${GIT_METADATA_ADVICE}"
}

@test "doesn't warn about Git metadata when Drush's output doesn't show it" {
  drush_uli_output() { :; }
  assert_login_link_warns ""

  # A warning about something else.
  drush_uli_output() {
    printf '%s\n' '<details class="error-with-backtrace"><summary><em class="placeholder">Warning</em>: file_get_contents(https://example.com/branch.txt): Failed to open stream in <em class="placeholder">include()</em> (line <em class="placeholder">5</em> of <em class="placeholder">sites/default/settings.php</em>).</summary><pre class="backtrace">include() (Line: 5)</pre></details>'
  }
  assert_login_link_warns ""
}

@test "warns about Git metadata when Drush fails too, and still says why there's no link" {
  drupal_site
  ddev() {
    cat "${DIR}/tests/testdata/drush-uli-git-head-html.txt"
    cat "${DIR}/tests/testdata/drush-uli-without-users-table.txt" >&2
    return 1
  }
  run --separate-stderr fw::login_link https://mysite-feature-x.ddev.site
  assert_failure
  assert_output "SQLSTATE[42S02]: Base table or view not found: 1146 Table 'db.users' doesn't exist: SELECT \"base\".\"uid\" AS \"uid\", \"base\".\"uuid\" AS \"uuid\", \"base\".\"langcode\" AS \"langcode\""
  assert_equal "$stderr" "Warning: web/sites/default/settings.php line 137 ${GIT_METADATA_ADVICE}"
}

# drupal_worktree: a Drupal project whose Drush URI names the primary site, and
# a worktree of it at WT. Starts run without Docker or DDEV; ddev drush uli
# prints a link to the --uri it gets.
drupal_worktree() {
  printf 'name: mysite\ntype: drupal11\nadditional_hostnames: [news.mysite]\nweb_environment:\n  - DRUSH_OPTIONS_URI=https://mysite.ddev.site\n' >"${SITE}/.ddev/config.yaml"
  git_site
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
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
}

@test "start warns, and logs, when the worktree's Drupal reads Git metadata, and still gives the login link" {
  drupal_worktree
  run fw::start_worktree "${WT}" fresh false
  assert_success
  # On a rerun the database exists, so start makes a login link.
  NAME=$(fw::generated_name "${WT}")
  docker() { echo "${NAME}-mariadb"; }
  ddev() {
    if [[ "$*" == 'drush uli --no-browser --uri='* ]]; then
      cat "${DIR}/tests/testdata/drush-uli-git-head-html.txt"
      echo "${4#--uri=}/user/reset/1/abc/def/login"
    fi
  }
  run fw::start_worktree "${WT}" "" false
  assert_success
  assert_line "Warning: sites/default/settings.php line 137 ${GIT_METADATA_ADVICE}"
  assert_line "One-time login link: https://${NAME}.ddev.site/user/reset/1/abc/def/login"
  run grep -cF "Warning: sites/default/settings.php line 137 reads Git metadata" "${WT}/.ddev/${FW_LOG_NAME}"
  assert_output 1
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

  # The record's modification time is when the database was created. Show it in
  # local time, five hours behind UTC, and in UTC for JSON. A stopped project
  # keeps its database, so ddev start is enough.
  export TZ=EST5 NAME
  touch -t 202610010930 "${SITE}/.git/worktrees/site-feature-x/fire-worktree-db"
  docker() { [[ "$1" != volume ]] || echo "${NAME}-mariadb"; }
  export -f docker
  cd "${WT}/.ddev"
  run "${INFO}"
  assert_success
  assert_output "$(printf 'Project:   %s (stopped)\nURLs:      https://%s.ddev.site\n           https://news.%s.ddev.site\nDatabase:  empty (--db=fresh)\n           created 2026-10-01 09:30\nLogin:     start the project with ddev start, then rerun this command' "${NAME}" "${NAME}" "${NAME}")"

  docker() { [[ "$1" != ps ]] || echo "ddev-${NAME}-web"; }
  export -f docker
  run "${INFO}" --json
  assert_success
  assert_output "$(printf '{\n  "name": "%s",\n  "status": "running",\n  "urls": ["https://%s.ddev.site", "https://news.%s.ddev.site"],\n  "database": {"source": "fresh", "file": null, "created": "2026-10-01T14:30:00Z"},\n  "login_url": "https://%s.ddev.site/user/reset/1/abc/def/login"\n}' "${NAME}" "${NAME}" "${NAME}" "${NAME}")"
  run "${INFO}" --bogus
  assert_failure
  assert_output "Usage: ddev fire-worktree-info [--json]"
}

# started_worktree: drupal_worktree after its first start, with stand-ins from
# with_database.
started_worktree() {
  drupal_worktree
  run fw::start_worktree "${WT}" fresh false
  assert_success
  with_database
}

# with_database: stand-ins for WT's started project NAME and its database
# volume. ddev logs each call to DDEV_LOG, also from child processes such as the
# build, and drush uli prints a link to the --uri it gets.
with_database() {
  NAME=$(fw::generated_name "${WT}")
  DDEV_LOG="${TESTDIR}/ddev.log"
  : >"${DDEV_LOG}"
  ddev() {
    echo "$*" >>"${DDEV_LOG}"
    if [[ "$*" == 'drush uli --no-browser --uri='* ]]; then
      echo "${4#--uri=}/user/reset/1/abc/def/login"
    fi
  }
  docker() { [[ "$1" != volume ]] || echo "${NAME}-mariadb"; }
  export -f ddev docker
  export DDEV_LOG NAME
}

@test "fire-worktree-info points a worktree whose database is gone to fire-worktree-start" {
  started_worktree
  INFO="${DIR}/commands/host/fire-worktree-info"
  cd "${WT}"
  # ddev start would create an empty database, which startup would then keep.
  expected=$(printf 'Project:   %s (not started)\nURLs:      https://%s.ddev.site\n           https://news.%s.ddev.site\nDatabase:  none yet; run ddev fire-worktree-start to copy one in' "${NAME}" "${NAME}" "${NAME}")

  # ddev delete deletes the database volume but leaves startup's record.
  docker() { :; }
  export -f docker
  run "${INFO}"
  assert_success
  assert_output "${expected}"
  run "${INFO}" --json
  assert_success
  assert_output --partial '"status": "not started"'
  assert_output --partial '"database": {"source": "none", "file": null, "created": null}'

  # remove --keep-checkout deletes both.
  run "${DIR}/commands/host/fire-worktree-remove" --keep-checkout --yes
  assert_success
  run "${INFO}"
  assert_success
  assert_output "${expected}"
}

@test "without a login link, a fresh or dumped database gets the populate hint rather than a drush retry" {
  started_worktree
  # A running FIRE project that drush can't log in to, as with an empty database.
  touch "${WT}/fire.yml"
  ddev() {
    echo "$*" >>"${DDEV_LOG}"
    [[ "$1" == drush ]] || return 0
    printf ' [error]  Drush command terminated abnormally.\n' >&2
    return 1
  }
  docker() {
    case $1 in
      ps) echo "ddev-${NAME}-web" ;;
      volume) echo "${NAME}-mariadb" ;;
    esac
  }
  export -f ddev docker
  INFO="${DIR}/commands/host/fire-worktree-info"
  hint="Warning: Couldn't create a login link: Drush command terminated abnormally. To populate the database: fire build"
  retry="Warning: Couldn't create a login link: Drush command terminated abnormally. Try: ddev drush uli --uri=https://${NAME}.ddev.site"

  # A rerun keeps the --db=fresh database.
  run fw::start_worktree "${WT}" "" false
  assert_success
  assert_line "${hint}"
  refute_output --partial "${retry}"
  cd "${WT}"
  run "${INFO}"
  assert_success
  assert_line "${hint}"
  refute_output --partial "${retry}"

  # A dump can leave the database empty or partly restored.
  touch "${TESTDIR}/dump.sql.gz"
  run fw::refresh_worktree "${WT}" "${TESTDIR}/dump.sql.gz" false true
  assert_success
  assert_line "${hint}"
  run "${INFO}"
  assert_line "${hint}"

  # A snapshot restores a whole database, so drush's own error is what to read.
  touch "${TESTDIR}/manual-mariadb_10.11.gz"
  run fw::refresh_worktree "${WT}" "${TESTDIR}/manual-mariadb_10.11.gz" false true
  assert_success
  assert_line "${retry}"
  refute_output --partial "To populate"
  run "${INFO}"
  assert_line "${retry}"
  refute_output --partial "To populate"
}

@test "refresh refuses the primary checkout, a worktree without its own database, and a run without --yes" {
  drupal_worktree
  run fw::refresh_worktree "${SITE}" "" true true
  assert_failure
  assert_output --partial "not the primary checkout"

  # Before its first start, DDEV gives the worktree the primary project's name.
  run fw::refresh_worktree "${WT}" "" true true
  assert_failure
  assert_output "This worktree has no database of its own yet. Run: ddev fire-worktree-start"

  # Started, but its database volume is gone.
  run fw::start_worktree "${WT}" fresh false
  assert_success
  run fw::refresh_worktree "${WT}" "" true true
  assert_failure
  assert_output "This worktree has no database of its own yet. Run: ddev fire-worktree-start"

  # No one at the terminal to confirm.
  with_database
  run fw::refresh_worktree "${WT}" fresh true false </dev/null
  assert_failure
  assert_output --partial "  - Delete the database of DDEV project ${NAME}. To keep a copy, cancel and run ddev snapshot."
  assert_output --partial "Pass --yes to confirm when not running interactively."
  run cat "${DDEV_LOG}"
  assert_output ""

  # A generated config that names the primary project.
  printf '%s\nname: mysite\n' "${FW_MARKER}" >"${WT}/.ddev/config.worktree.local.yaml"
  docker() { echo mysite-mariadb; }
  run fw::refresh_worktree "${WT}" fresh true true
  assert_failure
  assert_output "Refusing to replace the database of the primary DDEV project mysite."
}

@test "refresh resets the worktree's database by project name, records its source and builds" {
  started_worktree
  SEED="${SITE}/.ddev/db_snapshots/fire-worktree-seed-20261001000000-mariadb_10.11.gz"
  mkdir -p "$(dirname "${SEED}")"
  touch "${SEED}"
  RECORD="${SITE}/.git/worktrees/site-feature-x/fire-worktree-db"
  touch -t 202601010000 "${RECORD}"

  run fw::refresh_worktree "${WT}/.ddev" latest true true
  assert_success
  assert_line "  - Replace it with the last copy a worktree took of the mysite database. Other volumes, such as search indexes, are kept."
  assert_line "  - Run ddev drush deploy -y."
  assert_line "Seeding the new database from ${SEED}"
  assert_line "Building with: ddev drush deploy -y"
  assert_line "One-time login link: https://${NAME}.ddev.site/user/reset/1/abc/def/login"
  # Leave out the check of the copy's tables.
  run grep -v '^mysql ' "${DDEV_LOG}"
  assert_output "$(printf '%s\n' \
    "start --reset-database --omit-snapshot --skip-confirmation --seed-snapshot=${SEED} ${NAME}" \
    'drush deploy -y' \
    "drush uli --no-browser --uri=https://${NAME}.ddev.site")"
  fw::context "${WT}"
  run fw::db_source
  assert_output "$(printf 'latest\t%s' "${SEED}")"
  # The record is new, so it dates the new database.
  run fw::db_created +%Y%m%d%H%M
  refute_output 202601010000

  # A SQL dump is imported once the database is reset. Without the build, it's printed.
  touch "${TESTDIR}/site-db.sql.gz"
  : >"${DDEV_LOG}"
  run fw::refresh_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" false true
  assert_success
  refute_line --partial "  - Run "
  assert_line "Importing ${TESTDIR}/site-db.sql.gz into the new database"
  assert_line "Skipped the build. To run it: ddev drush deploy -y"
  run cat "${DDEV_LOG}"
  assert_line --index 0 "start --reset-database --omit-snapshot --skip-confirmation ${NAME}"
  assert_line --index 1 "import-db --file=${TESTDIR}/site-db.sql.gz"
  run fw::db_source
  assert_output "$(printf 'dump\t%s' "${TESTDIR}/site-db.sql.gz")"

  # An empty database isn't built.
  : >"${DDEV_LOG}"
  run fw::refresh_worktree "${WT}" fresh true true
  assert_success
  assert_line "  - Replace it with an empty database. Other volumes, such as search indexes, are kept."
  assert_line "To populate the database: ddev import-db --file=<dump>, or ddev pull <provider>"
  run cat "${DDEV_LOG}"
  assert_output "start --reset-database --omit-snapshot --skip-confirmation ${NAME}"
}

@test "refresh says how to recover when ddev start fails, and releases the start lock" {
  started_worktree
  ddev() { [[ "$1" != start ]]; }
  run fw::refresh_worktree "${WT}" fresh true true
  assert_failure
  assert_line "ddev start failed, and the worktree's database may be empty. Fix the error, then run: ddev fire-worktree-refresh --db=fresh"
  [ ! -e "${FW_LOCK}" ]
}

@test "fire-worktree-refresh parses its options" {
  started_worktree
  REFRESH="${DIR}/commands/host/fire-worktree-refresh"
  cd "${WT}"
  run "${REFRESH}" --bogus
  assert_failure
  assert_output "Usage: ddev fire-worktree-refresh [--db=primary|latest|fresh|<snapshot or dump>] [--no-build] [--yes]"
  run "${REFRESH}" --db=missing.sql.gz --yes
  assert_failure
  assert_output --partial "--db must be primary, latest, fresh"
  run "${REFRESH}" --db fresh --no-build -y
  assert_success
  run cat "${DDEV_LOG}"
  assert_output "start --reset-database --omit-snapshot --skip-confirmation ${NAME}"
}

@test "refresh follows WORKTREE_BUILD_FAILURE after printing the URLs" {
  started_worktree
  printf 'web_environment:\n  - WORKTREE_BUILD_COMMAND=echo deploy-error && false\n' >"${WT}/.ddev/config.local.yaml"
  touch "${TESTDIR}/site-db.sql.gz"
  run fw::refresh_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true true
  assert_failure
  local n=${#lines[@]}
  assert_equal "${lines[n-2]}" "One-time login link: https://${NAME}.ddev.site/user/reset/1/abc/def/login"
  assert_equal "${lines[n-1]}" "The worktree is running, but the build failed. Fix the error, then run: echo deploy-error && false"

  # warn exits 0. Refresh doesn't write the start log, so it names none.
  printf '  - WORKTREE_BUILD_FAILURE=warn\n' >>"${WT}/.ddev/config.local.yaml"
  run fw::refresh_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true true
  assert_success
  assert_line "Warning: The worktree is running, but the build failed. Fix the error, then run: echo deploy-error && false"
  refute_line --partial "Startup log"

  # A bad value stops before anything is deleted.
  printf '  - WORKTREE_BUILD_FAILURE=ignore\n' >>"${WT}/.ddev/config.local.yaml"
  : >"${DDEV_LOG}"
  run fw::refresh_worktree "${WT}" fresh true true
  assert_failure
  assert_output "WORKTREE_BUILD_FAILURE must be fail or warn; got ignore."
  run cat "${DDEV_LOG}"
  assert_output ""
}

@test "refresh keeps the database when there's no snapshot to copy" {
  started_worktree
  run fw::refresh_worktree "${WT}" latest true true
  assert_failure
  assert_output --partial "The primary checkout has no database snapshot to copy."
  run cat "${DDEV_LOG}"
  assert_output ""
  [ ! -e "${FW_LOCK}" ]
}

# copied_worktree: a PHP project whose build prints "built", a worktree of it at
# WT, and a dump that every start imports, since no database volume exists.
# ddev mysql prints TABLES as the copy's table count.
copied_worktree() {
  printf 'name: mysite\ntype: php\nweb_environment:\n  - WORKTREE_BUILD_COMMAND=echo built\n' >"${SITE}/.ddev/config.yaml"
  git_site
  WT="${TESTDIR}/site-feature-x"
  git -C "${SITE}" worktree add -q -b feature/x "${WT}"
  DUMP="${TESTDIR}/site-db.sql.gz"
  touch "${DUMP}"
  unset WORKTREE_SOURCE_ROOT T3CODE_PROJECT_ROOT
  ddev() { [[ "$1" != mysql ]] || echo "${TABLES}"; }
  docker() { :; }
}

@test "start warns that a copy with no tables looks incomplete, and skips the build" {
  copied_worktree
  TABLES=0
  run fw::start_worktree "${WT}" "${DUMP}" true
  assert_success
  assert_line "Warning: The database copy looks incomplete: it has no tables. Skipped the build. To copy it again, run: ddev fire-worktree-refresh"
  refute_line "built"

  TABLES=12
  run fw::start_worktree "${WT}" "${DUMP}" true
  assert_success
  refute_output --partial "looks incomplete"
  assert_line "built"
}

@test "start warns when Drush can't bootstrap Drupal from a copy, and skips drush deploy" {
  drupal_worktree
  touch "${TESTDIR}/site-db.sql.gz"
  # The build runs in its own process, so export the stand-in.
  ddev() {
    case $* in
      mysql\ *) echo 16 ;;
      'drush status --field=bootstrap')
        printf '%s\n' "${BOOTSTRAP}"
        return "${DRUSH_STATUS:-0}"
        ;;
      'drush deploy -y') echo deployed ;;
    esac
  }
  export -f ddev
  # As when the key_value table is missing.
  BOOTSTRAP=
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true
  assert_success
  assert_line "Warning: The database copy looks incomplete: Drush can't bootstrap Drupal from it. Skipped the build. To copy it again, run: ddev fire-worktree-refresh"
  refute_line "deployed"

  # Drupal can print warnings before Drush's answer, on the same line.
  BOOTSTRAP='<details>Warning: file(../.git/HEAD)</details>Successful'
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true
  assert_success
  refute_output --partial "looks incomplete"
  assert_line "deployed"

  # When Drush itself fails, the check can't tell, so the build runs.
  BOOTSTRAP=
  DRUSH_STATUS=1
  run fw::start_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true
  assert_success
  refute_output --partial "looks incomplete"
  assert_line "deployed"
}

@test "start warns when the database it keeps has no tables, unless it was created empty" {
  copied_worktree
  TABLES=12
  run fw::start_worktree "${WT}" "${DUMP}" true
  assert_success
  # Reruns keep the database.
  NAME=$(fw::generated_name "${WT}")
  docker() { echo "${NAME}-mariadb"; }
  TABLES=0
  run fw::start_worktree "${WT}" "" true
  assert_success
  assert_line "Warning: This worktree's database has no tables. To copy one in, run: ddev fire-worktree-refresh"

  # fire-worktree-remove --keep-checkout deletes the record, and ddev start then
  # creates an empty database.
  RECORD="${SITE}/.git/worktrees/site-feature-x/fire-worktree-db"
  rm "${RECORD}"
  run fw::start_worktree "${WT}" "" true
  assert_success
  assert_line "Warning: This worktree's database has no tables. To copy one in, run: ddev fire-worktree-refresh"

  printf 'fresh\t\n' >"${RECORD}"
  run fw::start_worktree "${WT}" "" true
  assert_success
  refute_output --partial "no tables"
}

@test "refresh warns when its copy looks incomplete, and skips the build" {
  started_worktree
  touch "${TESTDIR}/site-db.sql.gz"
  ddev() {
    echo "$*" >>"${DDEV_LOG}"
    [[ "$1" != mysql ]] || echo 0
  }
  export -f ddev
  run fw::refresh_worktree "${WT}" "${TESTDIR}/site-db.sql.gz" true true
  assert_success
  assert_line "Warning: The database copy looks incomplete: it has no tables. Skipped the build. To copy it again, run: ddev fire-worktree-refresh"
  run grep -c '^drush deploy' "${DDEV_LOG}"
  assert_output 0
}

@test "a failed login link says why, with the first line of Drush's error" {
  drupal_worktree
  # A copy rather than --db=fresh, which gets the populate hint instead of the drush retry.
  touch "${TESTDIR}/copy-mariadb_10.11.gz"
  run fw::start_worktree "${WT}" "${TESTDIR}/copy-mariadb_10.11.gz" false
  assert_success
  NAME=$(fw::generated_name "${WT}")
  docker() { echo "${NAME}-mariadb"; }
  # What ddev drush uli printed to stderr for a copy without the users table.
  ddev() {
    [[ "$1" == drush ]] || return 0
    cat "${DIR}/tests/testdata/drush-uli-without-users-table.txt" >&2
    return 1
  }
  run fw::start_worktree "${WT}" "" false
  assert_success
  assert_line "Warning: Couldn't create a login link: SQLSTATE[42S02]: Base table or view not found: 1146 Table 'db.users' doesn't exist: SELECT \"base\".\"uid\" AS \"uid\", \"base\".\"uuid\" AS \"uuid\", \"base\".\"langcode\" AS \"langcode\". Try: ddev drush uli --uri=https://${NAME}.ddev.site"

  # Drush's log messages carry a label.
  ddev() {
    [[ "$1" == drush ]] || return 0
    printf ' [error]  Drush command terminated abnormally.\n' >&2
    return 1
  }
  docker() { [[ "$1" != ps ]] || echo "ddev-${NAME}-web"; }
  export -f ddev docker
  export NAME
  cd "${WT}"
  run "${DIR}/commands/host/fire-worktree-info" --json
  assert_success
  assert_line "Warning: Couldn't create a login link: Drush command terminated abnormally. Try: ddev drush uli --uri=https://${NAME}.ddev.site"
  assert_line '  "login_url": null'
}
