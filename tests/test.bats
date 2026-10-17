#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=fourkitchens/ddev-fire-worktrees

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-fire-worktrees"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(cd "$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")" && pwd -P)"
  export PRIMARY="${TESTDIR}/primary"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  # A small PHP project in its own Git repository, with one subdomain hostname.
  mkdir -p "${PRIMARY}/.ddev" "${PRIMARY}/web/sites/default"
  cd "${PRIMARY}"
  git init -q -b main
  git config user.email test@example.com
  git config user.name Test
  echo '<?php echo "ok";' >web/index.php
  cat >.ddev/config.yaml <<EOF
name: ${PROJNAME}
type: php
docroot: web
project_tld: ddev.site
database:
    type: mariadb
    version: "10.11"
additional_hostnames:
    - sub.${PROJNAME}
web_environment:
    - WORKTREE_NAME_PREFIX=fwtest
    - WORKTREE_BUILD_COMMAND=ddev exec touch /var/www/html/web/built.txt
EOF
  echo '<?php // local' >web/sites/default/settings.local.php
  printf '/web/built.txt\n/web/sites/default/settings.local.php\n' >.gitignore
}

health_checks() {
  run curl -sf "http://${PROJNAME}.ddev.site"
  assert_success
  assert_output "ok"
}

teardown() {
  set -eu -o pipefail
  # Delete every worktree project this test started, then the primary.
  if [ -f "${PRIMARY}/.git/fire-worktrees" ]; then
    cut -f1 "${PRIMARY}/.git/fire-worktrees" | while IFS= read -r name; do
      ddev delete -Oy "${name}" >/dev/null 2>&1 || true
    done
  fi
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >>"${GITHUB_ENV}"
  else
    # Drupal can leave sites/default read-only.
    [ "${TESTDIR}" != "" ] && chmod -R u+w "${TESTDIR}" && rm -rf "${TESTDIR}"
  fi
}

# install_and_start SOURCE: install the add-on, commit, start the primary project
# and give its database a row that worktrees should copy.
install_and_start() {
  run ddev add-on get "$1"
  assert_success
  git add -A
  git commit -qm 'Install ddev-fire-worktrees'
  run ddev start -y
  assert_success
  run ddev mysql -e "CREATE TABLE marker (v VARCHAR(20)); INSERT INTO marker VALUES ('from-primary');"
  assert_success
}

# worktree_name DIR: the DDEV project name startup generated for DIR.
worktree_name() {
  awk '$1 == "name:" { print $2; exit }' "$1/.ddev/config.worktree.local.yaml"
}

@test "install from directory, then create, rerun, list and remove a worktree" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  install_and_start "${DIR}"
  health_checks

  run ddev fire-worktree-create feature/one
  assert_success
  WT="${TESTDIR}/primary-feature-one"
  assert_dir_exists "${WT}"
  NAME=$(worktree_name "${WT}")
  assert_regex "${NAME}" '^fwtest-feature-one-[0-9]+$'

  # Its own project and hostnames, the primary's data, the build, and local files.
  run grep -x "  - sub.${NAME}" "${WT}/.ddev/config.worktree.local.yaml"
  assert_success
  run curl -sf "http://sub.${NAME}.ddev.site"
  assert_output "ok"
  cd "${WT}"
  run ddev mysql -N -e 'SELECT v FROM marker'
  assert_output "from-primary"
  assert_file_exists "${WT}/web/built.txt"
  assert_file_exists "${WT}/web/sites/default/settings.local.php"
  run grep -c "Building with: " "${WT}/.ddev/fire-worktree-start.log"
  assert_output "1"
  run git status --porcelain
  assert_output ""
  health_checks

  # A rerun through the old command name keeps the database and doesn't rebuild.
  ddev mysql -e "INSERT INTO marker VALUES ('worktree-only')"
  rm web/built.txt
  run ddev worktree-start
  assert_success
  assert_equal "$(worktree_name "${WT}")" "${NAME}"
  run ddev mysql -N -e 'SELECT COUNT(*) FROM marker'
  assert_output "2"
  assert_file_not_exists "${WT}/web/built.txt"

  # A kept database that lost its tables gets a warning, not a new copy.
  ddev mysql -e 'DROP TABLE marker'
  run ddev fire-worktree-start
  assert_success
  assert_line "Warning: This worktree's database has no tables. To copy one in, run: ddev fire-worktree-refresh"

  run ddev fire-worktree-info
  assert_success
  assert_line "Project:   ${NAME} (running)"
  assert_line "           https://sub.${NAME}.ddev.site"
  assert_line --regexp "^Database:  ${PRIMARY}/\.ddev/db_snapshots/fire-worktree-seed-[^ ]+ \(--db=primary\)\$"
  refute_output --partial "Login"

  run ddev fire-worktree-list
  assert_success
  assert_output --partial "main (primary)"
  assert_line --regexp "^feature/one +${NAME} +running +0 "

  # Removal refuses uncommitted files and non-interactive runs without --yes.
  touch scratch.txt
  run ddev fire-worktree-remove --yes
  assert_failure
  assert_output --partial "?? scratch.txt"
  rm scratch.txt
  run ddev fire-worktree-remove
  assert_failure
  assert_output --partial "Pass --yes"

  run ddev fire-worktree-remove --yes
  assert_success
  assert_dir_not_exists "${WT}"
  cd "${PRIMARY}"
  run git branch --list feature/one
  assert_output --partial "feature/one"
  run ddev describe "${NAME}"
  assert_failure
  health_checks
}

@test "imports a SQL dump, and prune deletes projects whose checkout is gone" {
  set -eu -o pipefail
  # An add-on service with a named volume, as ddev-solr and ddev-redis have.
  cat >.ddev/docker-compose.cache.yaml <<'EOF'
services:
  cache:
    container_name: ddev-${DDEV_SITENAME}-cache
    image: busybox:stable
    command: sleep infinity
    labels:
      com.ddev.site-name: ${DDEV_SITENAME}
      com.ddev.approot: ${DDEV_APPROOT}
    volumes:
      - cache:/data
volumes:
  cache:
EOF
  install_and_start "${DIR}"

  # A dump such as FIRE's reference/site-db.sql.gz, given relative to the caller.
  mkdir reference
  run ddev export-db --file=reference/site-db.sql.gz
  assert_success
  run ddev fire-worktree-create feature/dump --db=reference/site-db.sql.gz --no-build
  assert_success
  assert_output --partial "Importing ${PRIMARY}/reference/site-db.sql.gz"
  assert_output --partial "Skipped the build"
  run bash -c "cd '${TESTDIR}/primary-feature-dump' && ddev mysql -N -e 'SELECT v FROM marker'"
  assert_output "from-primary"

  # A failed build leaves the site running, and warn lets startup exit 0.
  printf 'web_environment: [WORKTREE_BUILD_COMMAND=false, WORKTREE_BUILD_FAILURE=warn]\n' >.ddev/config.local.yaml
  run ddev fire-worktree-create feature/broken --db=reference/site-db.sql.gz
  rm .ddev/config.local.yaml
  assert_success
  BROKEN="${TESTDIR}/primary-feature-broken"
  assert_output --partial "Warning: The worktree is running, but the build failed. Fix the error, then run: false"
  assert_output --partial "Startup log: ${BROKEN}/.ddev/fire-worktree-start.log"
  run curl -sf "http://$(worktree_name "${BROKEN}").ddev.site"
  assert_output "ok"
  run grep -c "Building with: false" "${BROKEN}/.ddev/fire-worktree-start.log"
  assert_output "1"

  # A copy with no tables isn't built, and startup exits 0.
  : >"${TESTDIR}/empty.sql"
  run ddev fire-worktree-create feature/empty --db="${TESTDIR}/empty.sql"
  assert_success
  assert_line "Warning: The database copy looks incomplete: it has no tables. Skipped the build. To copy it again, run: ddev fire-worktree-refresh"
  refute_output --partial "Building with"

  run ddev fire-worktree-create feature/two --db=fresh
  assert_success
  assert_output --partial "To populate the database"
  WT="${TESTDIR}/primary-feature-two"
  NAME=$(worktree_name "${WT}")
  run bash -c "cd '${WT}' && ddev mysql -N -e 'SHOW TABLES'"
  assert_output ""

  # Remove the checkout without the add-on, as T3 does when it deletes a thread.
  git worktree remove --force "${WT}"
  run ddev fire-worktree-prune
  assert_success
  assert_output --partial "${NAME}"
  assert_output --partial "Dry run"
  # Without the checkout, ddev delete alone would leave the service's volume.
  run docker volume inspect "ddev-${NAME}_cache"
  assert_success
  run ddev fire-worktree-prune --yes
  assert_success
  assert_output --partial "Deleted volume ddev-${NAME}_cache"
  run docker volume inspect "${NAME}-mariadb"
  assert_failure
  run docker volume ls -q --filter "label=com.docker.compose.project=ddev-${NAME}"
  assert_output ""
  run ddev fire-worktree-prune
  assert_output --partial "No DDEV projects to prune."

  # Volumes an earlier prune left behind are listed, never deleted.
  docker volume create --label com.docker.compose.project=ddev-fwtest-gone-1 ddev-fwtest-gone-1_solr >/dev/null
  run ddev fire-worktree-prune --yes
  docker volume rm ddev-fwtest-gone-1_solr >/dev/null
  assert_success
  assert_line "  fwtest-gone-1"
  assert_line "    ddev-fwtest-gone-1_solr"
}

@test "refresh gives a worktree a new copy of the database and keeps its other volumes" {
  set -eu -o pipefail
  # An add-on service with a named volume, such as a search index.
  cat >.ddev/docker-compose.cache.yaml <<'EOF'
services:
  cache:
    container_name: ddev-${DDEV_SITENAME}-cache
    image: busybox:stable
    command: sleep infinity
    labels:
      com.ddev.site-name: ${DDEV_SITENAME}
      com.ddev.approot: ${DDEV_APPROOT}
    volumes:
      - cache:/data
volumes:
  cache:
EOF
  install_and_start "${DIR}"
  run ddev fire-worktree-create feature/refresh
  assert_success
  WT="${TESTDIR}/primary-feature-refresh"
  NAME=$(worktree_name "${WT}")

  # The worktree has its own data, and the primary moves on.
  cd "${WT}"
  ddev mysql -e "INSERT INTO marker VALUES ('worktree-only')"
  docker exec "ddev-${NAME}-cache" touch /data/index
  ddev exec rm /var/www/html/web/built.txt
  (cd "${PRIMARY}" && ddev mysql -e "UPDATE marker SET v = 'primary-later'")

  run ddev fire-worktree-refresh
  assert_failure
  assert_output --partial "Pass --yes"
  run ddev fire-worktree-refresh --yes
  assert_success
  assert_output --partial "Seeding the new database from ${PRIMARY}/.ddev/db_snapshots/fire-worktree-seed-"
  run ddev mysql -N -e 'SELECT v FROM marker'
  assert_output "primary-later"
  # The build ran. Check in the container, since Mutagen syncs to the checkout later.
  run ddev exec test -f /var/www/html/web/built.txt
  assert_success
  run docker exec "ddev-${NAME}-cache" ls /data/index
  assert_success
  # Neither the replaced database nor older copies are kept as snapshots.
  run bash -c "ls '${WT}/.ddev/db_snapshots' 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
  run bash -c "ls '${PRIMARY}/.ddev/db_snapshots' | grep -c '^fire-worktree-seed-'"
  assert_output "1"
  run ddev fire-worktree-info
  assert_line --regexp '^           created [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
  run curl -sf "http://${NAME}.ddev.site"
  assert_output "ok"

  # A SQL dump replaces the database the same way, and the primary keeps its data.
  ddev mysql -e "CREATE TABLE extra (v INT)"
  run bash -c "cd '${PRIMARY}' && ddev export-db --file='${TESTDIR}/site-db.sql.gz'"
  assert_success
  run ddev fire-worktree-refresh --db="${TESTDIR}/site-db.sql.gz" --no-build --yes
  assert_success
  assert_output --partial "Importing ${TESTDIR}/site-db.sql.gz into the new database"
  run ddev mysql -N -e 'SHOW TABLES'
  assert_output "marker"
  cd "${PRIMARY}"
  run ddev mysql -N -e 'SELECT v FROM marker'
  assert_output "primary-later"
  health_checks
}

@test "keeps legacy worktree names, handles nested worktrees, and refuses the primary" {
  set -eu -o pipefail
  install_and_start "${DIR}"

  run ddev fire-worktree-start
  assert_failure
  assert_output --partial "not the primary checkout"

  # A worktree started by the project-local commands this add-on replaces.
  git worktree add -q -b legacy/x ../primary-legacy-x main
  LEGACY="${TESTDIR}/primary-legacy-x"
  printf '# Generated by ddev worktree-start.\noverride_config: true\nname: fwtest-legacy-1\n' >"${LEGACY}/.ddev/config.worktree.yaml"
  cd "${LEGACY}"
  run ddev worktree-start --no-build
  assert_success
  assert_equal "$(worktree_name "${LEGACY}")" "fwtest-legacy-1"
  assert_file_not_exists "${LEGACY}/.ddev/config.worktree.yaml"

  # A worktree inside the primary checkout, like Claude Code's .claude/worktrees.
  cd "${PRIMARY}"
  git worktree add -q -b nested/n1 .claude/worktrees/n1 main
  cd .claude/worktrees/n1
  run ddev fire-worktree-start --no-build
  assert_success
  NESTED=$(worktree_name "$(pwd)")
  run ddev describe -j
  assert_output --partial "\"name\":\"${NESTED}\""
  run ddev mysql -N -e 'SELECT v FROM marker'
  assert_output "from-primary"
  cd "${PRIMARY}"
  health_checks

  run ddev fire-worktree-create legacy/x
  assert_failure
  assert_output --partial "Branch legacy/x is already checked out in ${LEGACY}."
}

@test "creates worktrees for a pull request and its base from one database copy" {
  set -eu -o pipefail
  install_and_start "${DIR}"

  # A pull request on origin that changes the page.
  git init -q --bare "${TESTDIR}/origin.git"
  git remote add origin "${TESTDIR}/origin.git"
  git push -q origin main
  git checkout -q -b feature/pr
  echo '<?php echo "pr";' >web/index.php
  git commit -qam 'Change the page'
  git push -q origin feature/pr feature/pr:refs/pull/7/head
  git checkout -q main
  git branch -q -D feature/pr
  # gh's answer for a pull request from this repository.
  mkdir "${TESTDIR}/bin"
  cat >"${TESTDIR}/bin/gh" <<'SH'
#!/bin/sh
printf 'feature/pr\nmain\nfalse\nfourkitchens\n'
SH
  chmod +x "${TESTDIR}/bin/gh"

  PATH="${TESTDIR}/bin:${PATH}"
  run ddev fire-worktree-create --pr 7 --base
  assert_success
  assert_output --partial "Checked out pull request #7 as branch feature/pr in:"
  # Both seed from the same snapshot.
  assert_equal "$(printf '%s\n' "${output}" | grep -c '^Seeding the new database from')" 2
  assert_equal "$(printf '%s\n' "${output}" | grep '^Seeding the new database from' | sort -u | wc -l | tr -d ' ')" 1
  WT="${TESTDIR}/primary-feature-pr"
  run curl -sf "http://$(worktree_name "${WT}").ddev.site"
  assert_output "pr"
  run curl -sf "http://$(worktree_name "${WT}-base").ddev.site"
  assert_output "ok"
  run bash -c "cd '${WT}-base' && ddev mysql -N -e 'SELECT v FROM marker'"
  assert_output "from-primary"
  run git -C "${WT}" rev-parse --abbrev-ref '@{upstream}'
  assert_output "origin/feature/pr"
}

@test "starts worktrees in parallel, and --db=latest reuses the last copy over a newer snapshot" {
  set -eu -o pipefail
  install_and_start "${DIR}"

  # Agent tools start several worktrees at once.
  local i
  local -a pids=()
  for i in 1 2 3; do
    git worktree add -q -b "parallel/$i" "../primary-parallel-$i" main
  done
  for i in 1 2 3; do
    (cd "${TESTDIR}/primary-parallel-$i" && ddev fire-worktree-start) >"${TESTDIR}/start-$i.log" 2>&1 &
    pids+=("$!")
  done
  for i in 1 2 3; do
    wait "${pids[i - 1]}" || fail "$(printf 'Starting primary-parallel-%s failed:\n' "$i" && cat "${TESTDIR}/start-$i.log")"
  done

  # Each has its own running project with the primary's data, and a registry entry.
  local expected=
  for i in 1 2 3; do
    WT="${TESTDIR}/primary-parallel-$i"
    NAME=$(worktree_name "${WT}")
    expected+=$(printf '%s\t%s' "${NAME}" "${WT}")$'\n'
    run curl -sf "http://${NAME}.ddev.site"
    assert_output "ok"
    run bash -c "cd '${WT}' && ddev mysql -N -e 'SELECT v FROM marker'"
    assert_output "from-primary"
  done
  run sort .git/fire-worktrees
  assert_output "$(printf '%s' "${expected}" | sort)"
  run bash -c 'ls .ddev/db_snapshots | grep -c "^fire-worktree-seed-"'
  assert_output "1"

  # A snapshot taken by hand after the last copy doesn't replace it.
  run ddev mysql -e "UPDATE marker SET v = 'by-hand'"
  assert_success
  run ddev snapshot --name=before-experiment
  assert_success
  run ddev fire-worktree-create feature/latest --db=latest --no-build
  assert_success
  assert_output --partial "Seeding the new database from ${PRIMARY}/.ddev/db_snapshots/fire-worktree-seed-"
  run bash -c "cd '${TESTDIR}/primary-feature-latest' && ddev mysql -N -e 'SELECT v FROM marker'"
  assert_output "from-primary"
}

@test "a Postgres project's worktree copies its database and keeps it on rerun" {
  set -eu -o pipefail
  sed -i.bak -e 's/type: mariadb/type: postgres/' -e 's/version: "10.11"/version: "17"/' .ddev/config.yaml
  rm .ddev/config.yaml.bak
  run ddev add-on get "${DIR}"
  assert_success
  git add -A
  git commit -qm 'Install ddev-fire-worktrees'
  run ddev start -y
  assert_success
  run ddev psql -c "CREATE TABLE marker (v VARCHAR(20)); INSERT INTO marker VALUES ('from-primary');"
  assert_success

  run ddev fire-worktree-create feature/pg
  assert_success
  assert_output --partial "Seeding the new database from ${PRIMARY}/.ddev/db_snapshots/fire-worktree-seed-"
  cd "${TESTDIR}/primary-feature-pg"
  run ddev psql -tA -c 'SELECT v FROM marker'
  assert_output "from-primary"

  # A rerun finds the postgres volume, so it doesn't copy the database again.
  run ddev psql -c "INSERT INTO marker VALUES ('worktree-only')"
  assert_success
  run ddev fire-worktree-start
  assert_success
  refute_output --partial "Seeding the new database"
  run ddev psql -tA -c 'SELECT COUNT(*) FROM marker'
  assert_output "2"

  run ddev psql -c 'DROP TABLE marker'
  assert_success
  run ddev fire-worktree-start
  assert_success
  assert_line "Warning: This worktree's database has no tables. To copy one in, run: ddev fire-worktree-refresh"
}

@test "a standard Drupal site needs no settings: the worktree copies the database and runs drush deploy" {
  set -eu -o pipefail
  # One Drupal site, no extra hostnames and no WORKTREE_* settings, like most projects.
  # Some pin Drush's URI to the primary site, which every worktree inherits.
  rm -rf web .gitignore
  printf 'name: %s\ntype: drupal11\ndocroot: web\nweb_environment:\n  - DRUSH_OPTIONS_URI=https://%s.ddev.site\n' "${PROJNAME}" "${PROJNAME}" >.ddev/config.yaml
  run ddev add-on get "${DIR}"
  assert_success
  run ddev start -y
  assert_success
  run ddev composer create-project drupal/recommended-project:^11
  assert_success
  run ddev composer require drush/drush
  assert_success
  run ddev drush site:install minimal -y --site-name=Primary
  assert_success
  chmod u+w web/sites/default web/sites/default/settings.php
  echo "\$settings['config_sync_directory'] = '../config/sync';" >>web/sites/default/settings.php
  run ddev drush config:export -y
  assert_success
  printf '/vendor/\n/recipes/\n/web/core/\n/web/libraries/\n/web/*/contrib/\n/web/sites/*/files/\n' >.gitignore
  git add -A
  git commit -qm 'Install Drupal'

  # Data that only the database has, and a config change the database hasn't imported.
  run ddev drush state:set fire_worktrees_marker from-primary
  assert_success
  sed -i.bak 's/^name: Primary$/name: Branch config/' config/sync/system.site.yml
  rm config/sync/system.site.yml.bak
  git commit -qam 'Rename the site in config'

  run ddev fire-worktree-create feature/drupal
  assert_success
  assert_output --partial "Building with: ddev drush deploy -y"
  assert_output --partial "inherits DRUSH_OPTIONS_URI=https://${PROJNAME}.ddev.site from web_environment"
  WT="${TESTDIR}/primary-feature-drupal"
  NAME=$(worktree_name "${WT}")
  # The login link is the worktree's, despite DRUSH_OPTIONS_URI, and logs in.
  assert_line --regexp "^One-time login link: https://${NAME}\.ddev\.site/user/reset/1/"
  link=$(printf '%s\n' "${output}" | sed -n 's/^One-time login link: https:/http:/p')
  run curl -s -o /dev/null -w '%{url_effective}' -L "${link}"
  assert_output --regexp "^http://${NAME}\.ddev\.site/user/1/edit"
  run grep -x 'additional_hostnames: \[\]' "${WT}/.ddev/config.worktree.local.yaml"
  assert_success

  cd "${WT}"
  run ddev drush state:get fire_worktrees_marker
  assert_output "from-primary"
  run ddev drush config:get system.site name --format=string
  assert_output "Branch config"
  run curl -sfL "http://${NAME}.ddev.site/"
  assert_success
  assert_output --partial "Branch config"
  run git status --porcelain
  assert_output ""

  run ddev fire-worktree-info --json
  assert_success
  assert_line "  \"name\": \"${NAME}\","
  assert_line '  "status": "running",'
  assert_line --regexp "^  \"database\": \\{\"source\": \"primary\", \"file\": \"${PRIMARY}/\\.ddev/db_snapshots/fire-worktree-seed-[^\"]+\", \"created\": \"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\"\\},\$"
  assert_line --regexp "^  \"login_url\": \"https://${NAME}\\.ddev\\.site/user/reset/1/[^\"]+\"\$"

  # A copy whose restore stopped partway: the tables up to config, alphabetically,
  # and no cached user entities.
  drop=$(ddev mysql -N -e "SELECT GROUP_CONCAT(table_name) FROM information_schema.tables WHERE table_schema = 'db' AND (table_name > 'config' OR table_name = 'cache_entity')")
  ddev mysql -e "DROP TABLE ${drop}"
  run ddev snapshot --name=partial
  assert_success
  run ddev fire-worktree-refresh --db="$(echo .ddev/db_snapshots/partial-*)" --yes
  assert_success
  assert_line "Warning: The database copy looks incomplete: Drush can't bootstrap Drupal from it. Skipped the build. To copy it again, run: ddev fire-worktree-refresh"
  refute_output --partial "Building with"
  assert_line --regexp "^Warning: Couldn't create a login link: .*'db\.users' doesn't exist"

  cd "${PRIMARY}"
  run ddev drush config:get system.site name --format=string
  assert_output "Primary"
  run ddev fire-worktree-remove --yes "${WT}"
  assert_success
  assert_dir_not_exists "${WT}"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  install_and_start "${GITHUB_REPO}"
  health_checks
  run ddev fire-worktree-create feature/release
  assert_success
  run ddev fire-worktree-list
  assert_line --regexp "^feature/release +fwtest-feature-release-[0-9]+ +running "
}
