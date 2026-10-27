# aLLMchemy lab

Config and working notes for developing [aLLMchemy](https://github.com/Teagan42/aLLMchemy).

aLLMchemy's own configuration is hostile to developing it. The package is built for
unattended runs, so it denies `AskUserQuestion` and `ExitPlanMode`, hooks `Stop` to reject
any final message that asks the operator something, and launches under
`bypassPermissions`. Correct for a run nobody is watching; useless when you are sitting
there trying to change it and want to be asked.

So the lab lives one directory up, with its own settings, and `aLLMchemy/` is a checkout
ignored by this repository.

```
aLLMchemy/            the project itself (separate remote, ignored here)
.worktrees/           detached scratch checkouts
claude-findings.md    review of the package — 15 findings
codex-findings.md     second review — 5 findings, one overlapping
run-mlx.py            MLX inference scratch
```
