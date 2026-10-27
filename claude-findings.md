# Code review findings — 2026-10-26

Effort: high. Scope: whole tree (no `.git`, so no diff to narrow to). All 15 findings
verified against the files; the detector suite was run and probed directly.

---

## 1. Failed webhook can never be retried — critical

`playbook/subscription-billing.md:121`

`insertIgnore` into `billing_events` happens *before* `applyEvent`. On the error path only
`error` is written, so the provider's retry hits an existing `provider_event_id`, gets
`fresh === false`, and returns `200 "duplicate"`.

A `subscription.activated` whose transaction fails on a transient DB blip is silently
dropped forever: the customer paid, the entitlement is never granted, nobody is watching.
The inline comment claims "Clear `processed_at` so the provider's retry re-runs it" — the
code never clears it and the duplicate check never consults it.

**Fix:** treat a row with `processed_at IS NULL` as re-processable in the duplicate check.

## 2. Annual subscribers get zero capabilities

`playbook/addon-design.md:74`

The catalog declares `base_annual` as a purchasable plan with `capabilities: same as base`
(a prose string, not a list), and the `CAPABILITIES` registry at line 18 has no
`base_annual` key. `can()` does `CAPABILITIES[e.planKey] ?? []`, so an active annual
subscriber resolves to `[]` and every capability check returns false.

Minimum-viable-stretch item 2 requires the annual plan to be purchasable, so this is the
normal path, not an edge case.

## 3. Secret-scan gate is both inert and inverted

`playbook/acceptance-gates.md:58`, `playbook/autonomy-contract.md:119`,
`playbook/roles/release-captain.md:44`

`git diff --staged | grep -Ei '(sk_live|...)' && exit 1` inspects only staged changes, so
during a `verify.sh` run (nothing staged) it can never find anything — and it cannot see
secrets already committed, which AGENTS.md lists as a never-downgradable failure. All
three sites share the staged-only blindness.

Worse, the check is inverted. `acceptance-gates.md:11` says `./verify.sh` exits 0 only if
all gates pass, so a gate whose command is `grep -Ei ... && exit 1` returns grep's exit 1
on a *clean* scan: a clean repo fails Gate 5. (`set -e` appears nowhere in the repo, so
the abort-on-no-match path is not the mechanism — the gate's own exit status is.)

**Fix:** `git grep -I -E ... $(git rev-list --all)` or a working-tree scan, and invert
explicitly with `if grep -q ...; then exit 1; fi`.

## 4. Cancellation revokes access immediately

`playbook/subscription-billing.md:98`

`live` is true only for `active`, or `past_due` inside grace; `can()` never reads
`current_period_end`. The `subscription.canceled` event carries `effectiveAt` and nothing
defers the status write, so setting `status='canceled'` on receipt cuts the user off at
once — contradicting line 180 ("Access runs to `current_period_end`") and failing matrix
test 7, which is in Gate 4's non-negotiable subset.

## 5. `can()` drops free capabilities for paying users

`playbook/subscription-billing.md:100`

`CAPABILITIES.free` is returned only on the `!live` branch. `base` grants
`watch:10`/`history:90d` but not `watch:1`/`history:7d`, so any feature gated on a
free-tier capability string is denied to every active subscriber while a
logged-out-of-grace user keeps it.

**Fix:** union `CAPABILITIES.free` into the live result, or make the registry inclusive.

## 6. `Stop` and `SubagentStop` share one block counter

`.claude/hooks/no-questions.sh:28`

`session_id` does not change for a subagent (`agent_id`/`agent_type` are what distinguish
them), and the same script is wired to both events in `settings.json`.

With seven role subagents dispatched per `00-kickoff.md`, three blocked subagent stops
exhaust `MAX_BLOCKS=3` and the orchestrator's interrogative final message then passes
unchecked; conversely one clean subagent stop `rm -f`s the counter and resets the parent's
budget, so the runaway guard no longer bounds anything.

**Fix:** include `agent_id` in the counter filename.

## 7. Hook reads a transcript that may lag the turn it is judging

`.claude/hooks/no-questions.sh:32`

Claude Code's hook docs explicitly warn that `transcript_path` is written asynchronously
and may lag the in-memory conversation, and direct Stop/SubagentStop hooks to use the
`last_assistant_message` input field instead.

As written the hook can evaluate the *previous* turn's text: it blocks a stop over an
already-rewritten question, or lets the current interrogative closing message through —
the exact deadlock it exists to prevent.

**Fix:** switch to `.last_assistant_message` with the transcript scan as fallback.

## 8. Apostrophe stripping deletes real questions

`bin/detect-question.sh:20`

`s/'[^']*'//g` treats contractions as quote delimiters, so two contractions bracketing a
question erase it. Verified against the shipped script:

- `I can't confirm: which host do you want? That's the open item.` → CLEAN
- `It isn't done. Should we ship? Here's the state.` → CLEAN
- (the no-contraction control is correctly flagged QUESTION)

Agent prose is full of contractions, so this is a common miss, and a miss is a permanent
hang.

**Fix:** strip only balanced backticks/double quotes, or require a non-word char before
the opening `'`.

## 9. Last retry's result is never evaluated

`bin/run-codex.sh:62`

The clean-check lives inside the loop, so after the third correction the loop condition
fails and the script prints "still interrogating after 3 retries" and exits 1 even when
that correction produced a clean message. With `MAX_RETRIES=0` the loop never runs and a
clean first turn also exits 1.

**Fix:** re-check after the final correction, or restructure as check-then-correct.

## 10. Detector is fed the tail of the whole event stream

`bin/run-codex.sh:59`

`tail -200` of `codex exec` output includes tool calls and file contents. The playbooks and
`bin/question-patterns.txt` themselves contain question-shaped lines (`Which billing
provider would you prefer?`), so an agent that merely read those files near the end of a
turn triggers a spurious correction cycle — up to three, then a false exit 1.

**Fix:** use `codex exec --output-last-message <file>` where available.

## 11. Resume fallback silently starts a brand-new run

`bin/run-codex.sh:50`

If `codex exec resume` is unsupported (the file's own comment says flags move between
versions), the `else` branch sends `$CORRECTION` as a fresh `codex exec` with no prior
context. The agent is told "Continue the run now" with nothing to continue, so the whole
product run restarts from the correction text and the earlier work is orphaned.

**Fix:** probe once up front and hard-fail, or re-send `$PROMPT` plus the correction when
resume is unavailable.

## 12. `QUOTAS` has no merge rule, and the merge drops a limit

`playbook/addon-design.md:27`

`can()` defines capability union across plan and add-ons, but nothing specifies how
`QUOTAS` combine. A `QUOTAS[planKey]` lookup ignores add-ons, so a user who bought
"Unlimited watches" is still capped at 10 while matrix test 9 passes (the
`watch:unlimited` capability is present).

A naive override is worse: `QUOTAS['addon.unlimited']` has no `notifications` key, so the
notification quota becomes `undefined` — an unbounded spend, which is precisely the Gate 8
hole the doc warns about.

## 13. Preflight collapses "absent" into "FAIL"

`playbook/deploy-pipeline.md:20`

`[ -n "$X" ] && curl ... && probe X OK || probe X FAIL` prints `FAIL` when the variable is
simply unset, but the `CAPABILITIES.md` format at line 50 and `roles/infra-provisioner.md:30`
distinguish `FAIL` (present but broken) from `ABSENT`/`UNKNOWN`, and the fallback tiers and
blocker text key off that distinction.

Separately, line 16 `. "${CREDENTIALS_FILE:-./.env.intake}"` aborts the whole preflight
under `set -e` when the operator skipped the credentials file — which README step 2 allows.
Also the intake field is `credentials_file` with no documented mapping to
`CREDENTIALS_FILE`.

## 14. False positive on the closing prose the contract mandates

`bin/question-patterns.txt:22`

`\b(i|we) (need|require) (you|your) (to|input|guidance|decision)\b` needs no question
mark, and `autonomy-contract.md:62` instructs the agent to state "what a human should do
next". Verified: `HANDOFF.md lists what we need you to do: rotate the Stripe key and
verify the domain.` → QUESTION. The hook then burns up to three rewrite cycles on a
correct handoff report.

**Fix:** require a trailing `?` or an imperative framing on this pattern.

## 15. "gate 8" refers to two different gates

`playbook/addon-design.md:58`

Here and at `playbook/roles/billing-engineer.md:41`, "gate 8" is cited for instant
cancellability, but `acceptance-gates.md` gate 8 is *cost*; cancellability is
`product-selection.md`'s **G8**. (`deploy-pipeline.md:149` has the mirror problem: "the G4
ceiling" means product-selection G4, while acceptance gate 4 is billing.) An agent
resolving an ambiguity at ladder rung 2 follows the reference to the wrong gate.

**Fix:** prefix one scheme, e.g. `G8` for selection gates and `gate 8` for acceptance
gates, and fix these three sites.

---

## Checked and clean

- `permissions.deny` for `AskUserQuestion`/`ExitPlanMode` **is** enforced under
  `--permission-mode bypassPermissions` (deny rules block in every mode; only `allow` is
  inert), so `run-claude.sh`'s default does not defeat the permission layer.
- `{"decision":"block","reason":...}` on stdout with exit 0 is a supported way to block a
  `Stop`/`SubagentStop`.
- `bin/test-detect-question.sh` passes all 19 cases; the runaway-guard assertions
  (block 1-3, allow on 4) match the implementation.
- `intake.schema.json` defaults agree with `intake.example.yaml` and `QUESTIONNAIRE.md`;
  agent and skill frontmatter is well-formed.
- `.claude/skills/*/SKILL.md` and `.claude/agents/*.md` are thin pointers (~600 bytes) to
  the authoritative `playbook/` text, not copies of it. No content is duplicated, so every
  playbook finding above has exactly one site to fix.
