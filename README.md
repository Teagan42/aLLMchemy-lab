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
setup.sh              clone aLLMchemy and bootstrap its dev tooling
.claude/settings.json the inverse config: questions and plan mode permitted
aLLMchemy/            the project itself (separate remote, ignored here)
.worktrees/           detached scratch checkouts
```

## From a bare clone

```sh
git clone git@github.com:Teagan42/aLLMchemy-lab.git && cd aLLMchemy-lab
./setup.sh              # clone aLLMchemy, pin authorship, run its bootstrap
./setup.sh --hooks      # ...and install its pre-commit hook
./setup.sh --check      # ...and run the full suite (~70s)
```

It checks the required tools before touching anything, names what each optional one buys,
then delegates the package's own bootstrap to `aLLMchemy/dev/setup.sh` rather than
reimplementing it — a second copy would drift from the first.

Authorship is pinned per-repository on both this repo and the clone, because a fresh clone
otherwise inherits the machine's global git identity and commits land attributed to an
unrelated address.

It is deliberately timid about an existing `aLLMchemy/`: it fetches and reports whether the
tree is dirty or behind, and never resets, cleans, pulls or force-updates. It refuses
outright if the directory is not a git repository or points at an unexpected remote, since
this directory also holds detached scratch work that must not be clobbered.

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

## Making changes

Both repositories use the same flow, and neither takes commits straight to `main`.

```sh
git fetch origin
git switch -c docs/short-slug origin/main    # from origin/main, not a stale local main
...change, commit...
git push -u origin HEAD
gh pr create --fill
```

Branch from `origin/main` rather than local `main`: a branch cut from a stale ref carries
already-merged commits, and in `aLLMchemy` the `commits` workflow then validates a range
that is not what you changed.

In `aLLMchemy` the PR title must be a conventional subject (`feat:`, `fix:`, `docs:` …)
because a squash merge uses it as the commit subject and `release-please` reads it to pick
the next version. This repository has no such gate, but the same shape keeps the two
histories readable side by side.

`aLLMchemy/DEVELOPING.md` is the authoritative contract for changes to the package. This
file covers only the lab.

**Both repos enforce this with a GitHub ruleset**, so it is not a convention you can forget:
a direct push to `main` is rejected with "Changes must be made through a pull request". Both
allow squash merges only, take the PR title as the commit subject, and delete the branch on
merge. The repository-admin bypass is scoped to `pull_request`, meaning an admin can merge a
PR that is missing a check but still cannot push to `main` directly.

`aLLMchemy` additionally requires three checks to pass: `conventional`,
`check (ubuntu-latest)` and `check (macos-latest)`. This repo has no CI, so it requires none
— requiring a check that never runs would block every PR forever.

## `.worktrees/opencode-multi-backend`

Plain files, not a git worktree — a detached copy of another session's in-flight work adding
an OpenCode backend to the package. Kept on purpose; do not clean it up or commit it. Backup
tarball: `/Users/teagan/src/opencode-multi-backend-backup-20261026-225211.tar.gz`.
