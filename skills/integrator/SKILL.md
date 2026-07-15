---
name: integrator
description: This skill should be used to verify that separately built pieces actually work together — after a dev-team run finishes its waves, before a deploy-team ship sequence, or whenever the user asks "does it all work together", "check the integration", or wants an end-to-end gate on multi-agent or multi-branch work. Runs a single Opus 4.8 integrator agent that owns the GO / NO-GO verdict, fixes integration slips the per-task reviewers missed, and briefs the single Fable 5 advisor on structural issues, which come back as fix tasks through the normal dev-team machinery.
---

# Integrator — End-to-End Integration Gate

Per-task reviewers see one task inside its file boundary. Integration bugs live *between* boundaries — mismatched contracts, drifted naming, flows that pass unit tests but break assembled. The integrator is the one agent that looks at the whole: it verifies end to end, fixes seam slips directly, and gives the run its GO / NO-GO.

## Role and model

| Role | Model param | Count | Job |
|---|---|---|---|
| Integrator | `model: "opus"` | **exactly 1 per run** | Seam checks, end-to-end verification, seam-slip fixes, GO/NO-GO, advisor briefs. |

Spawn as `subagent_type: "ziarmy-integrator"` when installed (`~/.claude/agents/` or plugin: `ziarmy:ziarmy-integrator`); fallback `general-purpose` with `model: "opus"` and the standing rules pasted from the agent definition. Like the advisor, **never spawn a second one** — every re-verification round goes back to the same agent via `SendMessage` so it keeps the full seam map. The 10-agent cap includes it.

## When to run

- **dev-team**: automatically, as the first part of Step 6 — after the final wave clears review, before the manager reports done.
- **deploy-team**: at handoff intake when the build came from a multi-agent run — a GO verdict is a prerequisite for starting the ship sequence.
- **Standalone**: on request, over any diff/branch where multiple workstreams merged.

## Workflow

### Step 1 — Spawn with the whole picture

Spawn the single integrator with: the plan file path (it reads task IDs, owned files, advisor decisions), how to run the tests and the app, and the specific cross-task flows worth driving. Caveman: paths and IDs, not pasted content.

### Step 2 — Verify

The integrator checks seams (graphify-first: `graphify path` between task boundaries), runs the full test suite, and **drives the real flows** — build/run the app, hit the endpoints, walk the user path. Exit codes alone are not integration.

### Step 3 — Route the outcome

- **GO** → record the verdict in the plan file's `## Integration` section; proceed (report / handoff / ship).
- **FIXED-GO** → the integrator fixed seam slips itself (only its own findings, minimal diffs, full suite re-run). Record the finding→fix list; proceed. If any fix touched a task's owned files in a way its reviewer should sanity-check, note it in the report.
- **NO-GO** → the integrator returns an **ADVISOR BRIEF**. The manager forwards it **verbatim** via `SendMessage` to the single advisor — the integrator and advisor talk through the manager as a relay, integrator reporting state, advisor deciding.

### Step 4 — Fix round (advisor-driven, dev-team machinery)

The advisor answers the brief the same way it handles a breakdown: binding decisions plus a **fix-task list** — each with ID (`F1…`), owned files, done-check, dependencies. The manager appends them to the plan file and runs them exactly like a dev-team wave: `ziarmy-executor`s implement, `ziarmy-reviewer`s gate, TaskCreate/TaskUpdate mirror progress.

### Step 5 — Re-verify, loop, converge

`SendMessage` the same integrator: fix wave done, re-verify. Loop Steps 2–4 until GO/FIXED-GO. **Two NO-GO rounds on the same seam** → stop; put the decision to the user (ship with the known issue, re-scope, or roll back the offending tasks) — never loop silently past that.

### Step 6 — Record

Update the plan file `## Integration` section (verdict, rounds, seam findings, fix-task IDs) and add one line to the run's retro in `.ziarmy/retro.md`: `integration: {GO|FIXED-GO n fixes|n rounds}, lesson: {one line}`.

## Hard rules

- The integrator's fix authority is **seam slips only** — issues it found, minimal diffs, verification-only afterwards. Structural problems always go through the advisor; the integrator never redesigns.
- The integrator never commits, pushes, or deploys — it is the last gate before the manager does.
- A NO-GO is never overridden silently: it converges to GO or it becomes the user's decision, and the final report says which.
