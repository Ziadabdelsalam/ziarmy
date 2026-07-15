# Workflow Mode

Use the Workflow tool instead of hand-dispatched Agent calls when the run is big enough that deterministic orchestration pays: **≥6 tasks, or ≥2 waves, or the user set a token budget ("+500k") or asked for scale**. Invoking dev-team is the user's opt-in to orchestration; still keep the advisor kickoff and all gated/user-facing decisions in the manager session — the workflow only runs the execute→review pipeline.

Why: `pipeline()` starts each task's review the moment its executor finishes (no wave barrier waste), the concurrency cap is enforced by the runtime, a killed/crashed run resumes with `resumeFromRunId` (completed agents replay from cache), and `budget` honors the user's token target.

## Skeleton

Build `TASKS` from the plan file (id, ownedFiles, doneCheck, specPath), then:

```javascript
export const meta = {
  name: 'ziarmy-dev-run',
  description: 'Execute plan tasks with executor→reviewer pipeline',
  phases: [{ title: 'Execute' }, { title: 'Review' }],
}
const RESULT = { type: 'object', properties: { status: {type:'string'}, files: {type:'array', items:{type:'string'}}, doneCheck: {type:'string'}, notes: {type:'string'} }, required: ['status'] }
const REVIEW = { type: 'object', properties: { verdict: {type:'string', enum:['approve','fixed','must-fix']}, findings: {type:'array', items:{type:'string'}}, escalate: {type:'array', items:{type:'string'}} }, required: ['verdict'] }

// Waves: run ready tasks, gate dependents on approved/fixed verdicts.
const done = {}
let ready = args.tasks.filter(t => t.depends.length === 0)
while (ready.length) {
  const results = await pipeline(
    ready,
    t => agent(`Task ${t.id}: spec in ${args.planPath} under "${t.id}". Owned files: ${t.owns}. Done-check: ${t.doneCheck}.`,
      { label: `exec:${t.id}`, phase: 'Execute', agentType: args.executorType, schema: RESULT }),
    (r, t) => agent(`Review task ${t.id}: spec in ${args.planPath}, scope ${t.owns}, done-check ${t.doneCheck}. Executor report: ${JSON.stringify(r)}.`,
      { label: `review:${t.id}`, phase: 'Review', agentType: args.reviewerType, schema: REVIEW })
      .then(v => ({ id: t.id, exec: r, review: v }))
  )
  results.filter(Boolean).forEach(x => { done[x.id] = x })
  ready = args.tasks.filter(t => !done[t.id] && t.depends.every(d => done[d] && done[d].review.verdict !== 'must-fix'))
  const blocked = Object.values(done).filter(x => x.review?.verdict === 'must-fix')
  if (blocked.length) log(`must-fix: ${blocked.map(b => b.id).join(', ')} — manager handles fix round`)
  if (!ready.length) break
}
return done
```

Pass via `args`: `{ planPath, tasks, executorType, reviewerType }` — agent types are `ziarmy-executor` / `ziarmy-reviewer` (or `ziarmy:ziarmy-executor` / `ziarmy:ziarmy-reviewer` when installed via the plugin); if unavailable, omit `agentType` and put the full role template in the prompt with `model: 'sonnet'` / `'opus'`.

Manager duties around the workflow: must-fix rounds, ESCALATE items → advisor via SendMessage, plan-file status updates, TaskUpdate mirroring, and the final integrate-and-verify — those stay in the main session. With a user budget, guard extra rounds with `budget.remaining()`.
