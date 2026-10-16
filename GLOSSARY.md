# Fire Worktrees

A DDEV add-on that runs several branches of a site side by side, each Git worktree with its own
DDEV project, database and URLs.

## Language

### Checkouts

**Primary checkout**:
The repository's original clone, whose Git directory every linked worktree shares. Its DDEV project
is the primary project.
_Avoid_: main checkout, root checkout

**Linked worktree**:
A Git worktree of the repository other than the primary checkout, which startup gives its own DDEV
project.
_Avoid_: copy, clone, worktree site

**Generated config**:
The DDEV config file that startup writes into a linked worktree to give it its own project name and
hostnames, marked so the add-on never overwrites a file it didn't write.
_Avoid_: worktree config, local config

### Startup

**Startup**:
Giving a linked worktree its own DDEV project, starting it, copying in a database and building it.
It's safe to rerun.
_Avoid_: setup, prepare, provisioning

**Seed snapshot**:
A DDEV snapshot of the primary project's database that a new worktree's database is created from.
_Avoid_: seed, dump (a SQL dump is imported after the project starts)

**Build**:
The steps that bring a newly copied database in line with the worktree's branch, such as database
updates and the theme build. It runs only after a database copy.
_Avoid_: deploy, rebuild, site build

**Build command**:
The one shell command that runs the build for a checkout, set by the team or chosen by the site
toolchain.
_Avoid_: build script, deploy command

**Start log**:
The file in each linked worktree where every startup appends its output.
_Avoid_: setup log

**Registry**:
The repository-wide record of the worktree projects that startup created and where their checkouts
were, kept so that projects whose checkout is gone can be found and deleted.
_Avoid_: index, worktree list

### Site toolchain

**Site toolchain**:
What a checkout's kind of site means for its worktrees: the build command, how to fill an empty
database, advice after the build, how to make a login link, and which local files to copy.
_Avoid_: site profile (Drupal install profiles are different), builder, project type

**Base**:
The site toolchain's answers for a DDEV project type, such as Drupal 8 and later, before any
overlay applies.
_Avoid_: default toolchain

**Overlay**:
A tool installed in the project that replaces some of the base's answers, such as ddev-fire
replacing the build command. At most one overlay applies.
_Avoid_: plugin, extension

### Fire

**FIRE CLI**:
Four Kitchens' Composer package of local-environment commands, configured by `fire.yml` and run on
the host, as in `fire build`.
_Avoid_: Fire (ambiguous), FIRE launcher (the tool that installs it)

**ddev-fire**:
The DDEV add-on that brings FIRE CLI's Drupal workflows into DDEV commands, such as
`ddev site-build`.
_Avoid_: Fire (ambiguous), the FIRE add-on
