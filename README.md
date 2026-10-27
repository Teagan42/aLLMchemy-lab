# aLLMchemy lab

Config and working notes for developing [aLLMchemy](https://github.com/Teagan42/aLLMchemy).

aLLMchemy's own configuration is hostile to developing it: it is built for unattended runs,
so it disarms every way an agent could stop and ask. Correct for a run nobody is watching;
useless when you are sitting there trying to change it and want to be asked.

The guards themselves are listed once, authoritatively, in
`aLLMchemy/DEVELOPING.md` under "Asking questions is correct here" — including why none of
them may be weakened. This file does not restate them; a second copy only drifts.

So the lab lives one directory up, with its own settings, and `aLLMchemy/` is a checkout
ignored by this repository.

```
.claude/settings.json the inverse config: questions and plan mode permitted
aLLMchemy/            the project itself (separate remote, ignored here)
.worktrees/           detached scratch checkouts
```

## What `.claude/settings.json` inverts

Point by point against `aLLMchemy/.claude/settings.json`:

| aLLMchemy | here |
|---|---|
| `AskUserQuestion`, `ExitPlanMode` denied | both allowed |
| `Stop`/`SubagentStop` -> `no-questions.sh` | no hooks at all |
| `bypassPermissions` via `bin/run-claude.sh` | `defaultMode: default` |
| allowlist covers deploy and billing CLIs | allowlist covers git reads, `make`, `node`, the repo's own test scripts |

**The allowlist is not a sandbox and must not be relied on as one.** It exists so a
development session is not prompt-spammed on `make test`. It is narrow in *shape* — 28
command prefixes, no `Bash(*)` — and `git commit`, `git push`, `rm` and every provider CLI
are absent and will prompt. But it is not a confinement boundary, and reading it as one is
the mistake to avoid:

- `Bash(node:*)` permits `node -e '<anything>'`, which is unrestricted local code execution.
- `Edit` plus `Bash(make:*)` permits rewriting `aLLMchemy/dev/test.sh` and then running it.
  Same for the explicit `./dev/*.sh` entries.

That is acceptable here because a human is watching — which is the whole premise of the lab.
Narrow it to specific invocations (`Bash(node --check:*)`, `Bash(node --test:*)`) only if
that premise ever stops holding.

### Does `aLLMchemy/.claude/settings.json` still apply here?

No. Measured, not assumed, on Claude Code 2.1.311: a nested `.claude/settings.json` is not
a settings source. This is the entire source list for a session rooted at the lab, and the
package's file is not on it.

```
[DEBUG] Watching for changes in setting files /Users/teagan/.claude/settings.json,
        <lab>/.claude/settings.json, <lab>/.claude/settings.local.json,
        /Library/Application Support/ClaudeCode/managed-settings.json
```

The control: a throwaway `_probe/.claude/settings.json` holding `Bash(npm run:*)` — a
pattern Claude Code logs as `Ignoring dangerous permission` whenever it does read it —
produced no such line, while the same entry in `~/.claude/settings.json` did. The nested
walk had run: `[skills] Dynamically discovered 1 skills from 1 directories` picked up
`_probe/.claude/skills` in the same session. So the walk finds nested directories, and
takes skills from them but not settings.

Skills are the part that is directory-scoped, and the `aLLMchemy/` line in `.gitignore`
keeps even those out: `[skills] Skipped gitignored skills dir:
<lab>/aLLMchemy/.claude/skills`. Commit the checkout and the package's six run-mode skills
start loading into development sessions.

This is undocumented behaviour of one version, so re-measure after a Claude Code upgrade
rather than trusting this section. Starting a session *inside* `aLLMchemy/` is the case
that definitely loads the production config — that directory is then the project root, and
its settings are the project settings.

## Starting a development session

Open the lab, not the package. Edit files under `aLLMchemy/`; run the harness from inside it:

```sh
cd aLLMchemy
make setup        # bootstrap and doctor; idempotent, installs nothing globally
make check        # lint then test. The one command to run before a commit
```

`aLLMchemy/DEVELOPING.md` is the authoritative development contract — seams, TDD loop,
portability floor, atomic-commit rules, and the full `make` target list. This file only
covers the lab's own configuration.

Never run `bin/run-claude.sh`, `bin/run-codex.sh` or `bin/run-factory.sh` to try something
out. They provision real infrastructure and spend real money, and there is no dry-run flag.

## `.worktrees/opencode-multi-backend`

Plain files, not a git worktree — a detached copy of another session's in-flight work adding
an OpenCode backend to the package. Kept on purpose; do not clean it up or commit it. Backup
tarball: `/Users/teagan/src/opencode-multi-backend-backup-20261026-225211.tar.gz`.
