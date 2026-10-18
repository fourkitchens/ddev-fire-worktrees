# Agent tools share one Git-based recipe

Teams use whichever agent tool their developers prefer, so the scripts name no agent tool: they read
no tool's environment variables, such as T3's `T3CODE_PROJECT_ROOT`, and have no adapters for
particular tools. A worktree finds its source checkout, and a branch older than the add-on finds the
main checkout's copy of the commands, through Git alone, which works from any linked worktree
whatever created it. Every tool's recipe runs the same published setup line and teardown line from
the "Any agent tool" section of `docs/agent-tools.md`, and teams paste those lines into their own
committed config, so keep the lines stable: a change reaches no one until each team edits its
config. `tests/agent-tools.bats` checks that every tool section's copy matches.
