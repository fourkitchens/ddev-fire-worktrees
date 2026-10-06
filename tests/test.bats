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
  run ddev fire-worktree-prune --yes
  assert_success
  run docker volume inspect "${NAME}-mariadb"
  assert_failure
  run ddev fire-worktree-prune
  assert_output --partial "No DDEV projects to prune."
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
  assert_output --partial "already exists"
}

@test "a standard Drupal site needs no settings: the worktree copies the database and runs drush deploy" {
  set -eu -o pipefail
  # One Drupal site, no extra hostnames and no WORKTREE_* settings, like most projects.
  rm -rf web .gitignore
  printf 'name: %s\ntype: drupal11\ndocroot: web\n' "${PROJNAME}" >.ddev/config.yaml
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
  WT="${TESTDIR}/primary-feature-drupal"
  NAME=$(worktree_name "${WT}")
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
