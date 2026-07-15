---
name: dev-team
description: This skill should be used whenever a request is complex enough to require breaking down into multiple tasks — multi-part features, cross-cutting refactors, "build X end to end", audits spanning many files, or when the user asks to break down, parallelize, or split work across agents. Decomposes the request into a dependency-ordered task graph and runs it with a team of up to 10 agents — Sonnet 5 executors, Opus 4.8 reviewers between tasks, and a single Fable 5 advisor/architect for architecture decisions and critical items.
---

# Dev Team — Parallel Multi-Agent Task Orchestration

Run complex work as a managed team: the main session acts as the **manager** (coordinates only, writes no code), multiple **executors** implement in parallel, **reviewers** gate the work between tasks, and exactly **one advisor** owns architecture and critical decisions.

## Team Roles and Model Assignment

Set these via the Agent tool's `model` parameter — these are the only valid values:

| Role | Model param | Model | Count | Job |
|---|---|---|---|---|
| Manager | (main session) | — | 1 | Break down, dispatch, integrate. Never implements. |
| Executor | `model: "sonnet"` | Sonnet 5 | many | Implement one task; run its tests; report a concise summary. |
| Reviewer | `model: "opus"` | Opus 4.8 | many | Review one completed task before dependent work proceeds. |
| Advisor | `model: "fable"` | Fable 5 | **exactly 1** | Architecture decisions, critical items, tie-breaking. |

Hard limits:
- **At most 10 agents running concurrently** across all roles. Track the count; queue excess tasks for the next wave.
- **Never spawn a second advisor.** Spawn the advisor once, record its agent ID/name, and route every later architecture question to it via `SendMessage` so it keeps full context. Multiple concurrent executors and reviewers are expected.

## Communication — caveman mode

Spend tokens on thinking and code, not on talk. Detail lives in the plan file; messages carry deltas and pointers only.

- **Status to user**: one line per event, no prose. Format: `[w2] exec 3/5 done | review 2 ok, 1 must-fix | advisor: 0 open`. Emit only on: wave start, task failure, escalation, wave clear, done. Nothing else mid-run.
- **Questions to user**: normal questions cost one line. Use AskUserQuestion with 2–4 short options, recommended option first; batch related questions into one call. Never restate context the user already has. Example: `Q: reasons table — soft-delete or hard-delete?` — not a paragraph.
- **Agent ↔ manager**: the structured return blocks from `references/role-prompts.md`, hard cap ~10 lines. Anything longer goes in a scratchpad file; the message carries the path.
- **Final report**: compact bullets — built / review findings that mattered / advisor calls / deferred+why. No narrative recap, no restating the plan.

### Step 1 — Break down accurately

Decomposition quality decides everything downstream. Before spawning anything:

1. Scope the request against the actual codebase (run `graphify query "<question>"` first when `graphify-out/graph.json` exists, otherwise targeted search). Never decompose from assumptions.
2. Produce a task list where every task has: an ID, a goal stated as a verifiable outcome, the exact files it owns, its dependencies (task IDs), and a done-check (test command or observable behavior).
3. Enforce **exclusive file ownership**: no two tasks in the same wave may touch the same file. If two tasks need the same file, merge them or sequence them across waves.
4. Group tasks into **waves**: wave 1 = tasks with no dependencies, wave 2 = tasks depending only on wave 1, etc. Maximize wave width — parallelism comes from wide waves, not more waves.
5. Write the full plan to a scratchpad file (e.g. `<scratchpad>/team-plan.md`). Agents receive file paths plus their task ID, not pasted content — this is the token-efficient handoff.

### Step 2 — Advisor kickoff (architecture gate)

Spawn the single Fable 5 advisor **before any executor**, with `run_in_background: false`, passing the plan file path. Ask it to:
- Validate the breakdown: missing tasks, wrong boundaries, hidden coupling between "independent" tasks.
- Make the upfront architecture decisions the tasks depend on (interfaces, data shapes, patterns to follow).
- Flag which tasks are **critical items** that must return to it before merge.

Apply its corrections to the plan file. All later escalations go to this same agent via `SendMessage`.

Skip this step only when the work is purely mechanical with zero design surface (e.g. a mass rename) — then state in the final summary that the advisor was skipped and why.

### Step 3 — Execute in waves (maximize parallelism)

For each wave:

1. Spawn all executors for the wave **in a single message with multiple Agent tool calls** so they run concurrently. Each executor gets `model: "sonnet"`, the plan file path plus its task ID, its owned files, and its done-check. Use the templates in `references/role-prompts.md`.
2. If ownership boundaries are not airtight for a wave that mutates files, give those executors `isolation: "worktree"`; otherwise plain parallel execution in the shared tree is cheaper.
3. Executors run in the background by default — as each one completes, immediately move it to review (Step 4). Do not wait for the whole wave before starting reviews.

### Step 4 — Review between tasks (the gate)

Every completed executor task gets an Opus 4.8 reviewer (`model: "opus"`) before any dependent task starts and before integration:

- Spawn reviewers in parallel as executor results arrive. Respect the 10-agent cap (running executors + running reviewers ≤ 10).
- The reviewer receives the task's done-check and owned-file scope, and returns a verdict: **approve** or **must-fix** with concrete findings.
- **must-fix** → send findings back to an executor (`SendMessage` to the original if still alive, else a fresh Sonnet 5 agent) and re-review. Unreviewed or must-fix work never unblocks dependent tasks.
- Findings that question the design rather than the implementation → escalate to the advisor (Step 5), not back to the executor.

### Step 5 — Escalation to the advisor

Route to the single Fable 5 advisor via `SendMessage` (never a new Agent call):
- Any architecture decision discovered mid-execution.
- Any task the advisor flagged as a critical item, once reviewed.
- Reviewer/executor disagreement that survives one fix round.
- Anything touching data integrity, migrations, auth/security, or public API shape.

The advisor's answer is binding; record it in the plan file so later waves see it.

### Step 6 — Integrate and verify

After the final wave clears review:
1. Run the full test suite (and the project's verify skill, if any) from the manager session.
2. If worktrees were used, merge them back sequentially, running tests after each merge.
3. Run `graphify update .` if the project keeps a knowledge graph.
4. Report to the user: what was built, task-by-task outcomes, review findings that mattered, advisor decisions made, and anything skipped or deferred.
5. If the work is deployable, offer to hand off to the **deploy-team** skill — it picks up the plan file and the verified commit and runs the deployment with the same team model.

## Failure handling

- An executor that returns null (skipped/died) → respawn once with the same spec; a twice-failed task goes to the advisor with the error context.
- A wave where reviewers reject most tasks → stop, re-consult the advisor on the breakdown itself before burning more agents.
- Never silently drop a task: every task ID must end as approved, deferred (with reason, reported to the user), or explicitly cancelled by the user.

## References

- `references/role-prompts.md` — prompt templates for executor, reviewer, and advisor agents. Read it before spawning the first agent of each role.
