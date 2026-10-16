#!/usr/bin/env bash
#ddev-generated
# Site toolchain overlays for ddev-fire and the FIRE CLI. lib.sh sources this
# file, and no other code knows about either tool: see
# docs/adr/0001-fire-knowledge-lives-in-overlays.md. Deleting this file and the
# lines that load it leaves an add-on that works without Fire.
# shellcheck disable=SC2034 # fw::toolchain reads the FW_TOOLCHAIN_* values.

# fw::toolchain_ddev_fire DIR: applies when DIR has ddev-fire's site-build
# command, not a project's own one, and DDEV offers it for DIR's project type.
fw::toolchain_ddev_fire() {
  local file="$1/.ddev/commands/host/site-build" types
  [[ -f "$file" && -f "$1/.ddev/fire/scripts/lib.sh" ]] || return 1
  types=$(sed -n 's/^## ProjectTypes:[[:space:]]*//p' "$file" | tr -d ' \t\r')
  [[ -z "$types" || ",$types," == *",$(fw::config_scalar "$1" type),"* ]] || return 1
  # --skip-db-import also skips the database download.
  FW_TOOLCHAIN_BUILD='ddev site-build --skip-db-import'
  FW_TOOLCHAIN_HINT='ddev site-build'
}

# fw::toolchain_fire_cli DIR: applies when DIR has a fire.yml. The base's build
# doesn't build the theme the way fire build does, so say how to switch.
fw::toolchain_fire_cli() {
  [[ -f "$1/fire.yml" ]] || return 1
  FW_TOOLCHAIN_HINT='fire build'
  if [[ "$FW_TOOLCHAIN_BUILD" != none ]]; then
    FW_TOOLCHAIN_ADVICE="This project uses FIRE, and drush deploy doesn't build its theme. To build everything
after each copy, set WORKTREE_BUILD_COMMAND=fire build --no-db-import. See \"Projects that
build with FIRE\" in the add-on's docs/drupal.md."
  fi
}

FW_TOOLCHAIN_OVERLAYS+=(fw::toolchain_ddev_fire fw::toolchain_fire_cli)
