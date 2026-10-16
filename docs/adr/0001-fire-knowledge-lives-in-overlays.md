# Only the Fire overlays know about Fire

FIRE CLI and ddev-fire may be overhauled or moved into another add-on, and the rest of this add-on
shouldn't notice. So everything that knows about either tool lives in the site toolchain's two
overlays in `fire-worktrees/toolchain-fire.sh`: how to detect it, its commands and flags, and
advice about it. No other code refers to them; the add-on's own `fire-worktree-*` names are a
separate question. Deleting that file and the lines that load it leaves a working add-on that
knows nothing about Fire.

## Considered Options

- **ddev-fire declares its build.** ddev-fire could set `WORKTREE_BUILD_COMMAND` in a config file
  of its own, and this add-on would detect nothing. Deferred until Fire's overhaul: it needs a
  ddev-fire release, and that file would load after `config.yaml`, overriding a team's setting.
- **A setting that names the toolchain.** Rejected: `WORKTREE_BUILD_COMMAND` already lets a
  project bypass detection for the build, the only answer that changes what runs.
