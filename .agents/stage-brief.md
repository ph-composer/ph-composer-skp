# Stage brief: standing rules for a pr-loop stage subagent

A conductor session runs each pr-loop stage as a background subagent. The brief it writes names the scope
(issue or packet stage), the loop arguments and anything specific. It then points here instead of retyping
these rules. Read this file, then `AGENTS.md`, then the pr-loop skill. Repository rules win over this file
where they differ.

## Checkout and branch

- Start with `git fetch origin && git checkout main && git pull --ff-only`, then branch with the name the
  brief gives. If a sibling stage's PR is still open, branch from main anyway. Before you open your PR, read
  that PR's state once. If it has merged, rebase. If it is still open, say in your PR body that yours follows
  it. Read once per check, never in a loop.
- The stage owns the main checkout; do not use a worktree, because `make ci` in a worktree skips RuboCop.
  Run `git rev-parse --abbrev-ref HEAD` before every commit. Stage named paths only, never `git add -A`.
  After `git mv`, `git add` only the new path.
- Leave the checkout on `main` when the stage ends.

## Gate, commit, push

- Run `pgrep -x SketchUp` before `make ci`. If SketchUp is running, stop and report: the gate and the host
  share port 46110. Do not quit SketchUp yourself.
- `make ci && git commit -s ... && git push --no-thin`, chained with `&&`, never `;`, never `--no-verify`.
- If the push fails twice with HTTP 400 "unexpected disconnect while reading sideband packet", push with
  `git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 push --no-thin ...`.
- Commit messages end with the DCO sign-off and the agent attribution trailer the conductor names. The PR
  body ends with the attribution line, and says `Closes #N` (or `Part of #N` for one stage of a multi-stage
  issue).

## Contract and documentation duties

- A change to a public operation or tool bumps the API minor version in `shell/api.rb` with a change note
  like its neighbours. It updates `context/AGENT_INTERFACE.md`, and `context/CONTRACTS.md` when codes or
  shapes change. `docs/AGENT_GUIDE.md` and the shipped `src/ph_composer/agent_access/guide.md` move together.
  `make fixtures` regenerates `docs/API_REFERENCE.md` and the shipped guide.
- `docs/` is read by external partners: write it in the client-facing register, with no em or en dashes.
- A stage touching `src/ph_composer/html/*.css` or a shared UI kit part runs the `ph-composer-ui-polish`
  Design System re-sync before merge and reports it.
- Update the owning ledger row (sweep ledger or packet status table) in the same PR.

## Review and merge

- Run one Sonnet read-through before the gate, then Codex through the conductor's review command. Use the
  model the brief names: gpt-6.1-sol by default, gpt-6-astra where the plan asks for the stronger lane. On a
  usage-limit refusal, stop and report.
- Under `--merge`, once every thread is answered, run `gh pr merge <N> --auto --squash --delete-branch` and
  stop. Never poll CI.

## Host and control

- Never call `request_full_control`. A stage that needs a native hold prepares it (fixture, helper, recipe),
  then stops and reports "ready for hold"; the conductor runs the hold.
- Never bring SketchUp to the front and never start an action that can raise a macOS permission or System
  Settings window. Report it to the conductor instead.

## Report

Under 150 words: the PR URL; the change in one line; any departure from the plan; tests added; gate result;
review findings and how each was handled; whether auto-merge is armed; what was not run.
