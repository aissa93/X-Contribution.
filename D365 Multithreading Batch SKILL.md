---
name: d365-multithreaded-batch
description: Use when designing, reviewing, or debugging any X++/D365FO batch job that fans work out across N parallel SysOperation batch tasks (partitioning a backlog table across worker threads). Covers safe partition-key assignment and correct task sequencing via the batch framework.
---

# Multi-threaded X++ batch processing pattern

This pattern comes from a real bug chain in an invoice-integration batch job (`EZ_MultiThreadingCreateTasksService` / `EZ_ProcessInoiceIntegrationWorkItem_Service`). Apply it whenever a batch job needs to split a backlog of records across N parallel worker tasks.

## When not to bother

Multithreading adds real overhead: an extra marking task, a `BatchDependency` row, and the marking loop's own `while select forUpdate` pass over the backlog before any worker starts. For a backlog that's small or bursty (a few hundred rows, sub-minute processing time), that overhead can exceed whatever parallelism buys you. Reach for this pattern when the backlog is large or steady enough that serial processing has a measurable wall-clock cost — not by default for every batch job that happens to process a table.

## Pitfall 1: never partition on `RecId mod totalThreads`

It looks like a clean hash, but D365FO's RecId allocator hands out IDs in fixed-size blocks per table (often a step of 4, 8, etc., depending on the table's record-ID sequence configuration). If every RecId in a table is `≡ 0 mod 4`, then `RecId mod 4` is degenerate — 100% of rows land in bucket 0, and the other N-1 "threads" run and find nothing, forever. This isn't rare or table-specific; check any real table's actual RecId sequence before trusting a raw `mod` on it.

**Diagnostic:** before trusting a partition key, take a real sample of RecIds from the table and compute `RecId mod totalThreads` by hand. If they don't spread roughly evenly across `0..totalThreads-1`, the key is broken.

## Pitfall 2: `pessimisticlock` + `readPast` alone gives correctness, not parallelism

Dropping the partition filter entirely and letting every worker `select pessimisticlock firstOnly ... readPast` race for "the next unlocked row" is tempting — `readPast` correctly makes losers skip a locked row instead of blocking, so you never get double-processing. But it does **not** guarantee even distribution. If worker tasks don't all start at exactly the same instant (they never do — batch task dispatch has real skew), a fast-starting worker can keep re-winning the race and drain the entire backlog before the other workers get their first `select` in. Symptom: N-1 tasks start and end almost instantly having processed nothing, while one task does everything serially. This is a correct-but-useless outcome — you get zero speedup and it looks like a bug (it effectively is one, just not a correctness bug).

## The fix: explicit partition assignment stamped at marking time

1. Add a persisted `ThreadIndex` (or similar) int field on the backlog table.
2. When marking rows eligible (e.g. flipping status to `InProcessing`), don't use a set-based `update_recordset` — it can't assign a per-row computed value. Use a counted `while select forUpdate` loop in a fixed, stable order (`order by RecId asc` or similar) and assign the bucket as `counter mod totalThreads` (round-robin), incrementing `counter` each row:
   ```
   int counter;
   ttsBegin;
   while select forUpdate Invoicetable
       order by Invoicetable.RecId asc
       where <eligibility filter>
   {
       Invoicetable.IntegrationStatus = EZ_IntegrationStatus::InProcessing;
       Invoicetable.ThreadIndex        = counter mod totalThreads;   // or +1 for 1-based numbering
       Invoicetable.update();
       counter++;
   }
   ttsCommit;
   ```
   Round-robin (`counter mod N`), not contiguous chunking (`counter div rowsPerThread`) — round-robin keeps every bucket busy even when the row count doesn't divide evenly; chunking can leave the last bucket starved.
3. Each worker task's select filters on the **stamped field**, not a derived hash: `Invoicetable.ThreadIndex == threadIndex`. This guarantees an even, deterministic split regardless of what the underlying RecId allocation looks like, and each worker owns a disjoint slice — no race, no readPast reliance needed for balance (keep `readPast` anyway as a cheap defensive measure).
4. Watch for stale data: any row already sitting in the "eligible" state *before* this field existed will have whatever the column's default backfill gave it (`0` or possibly SQL `NULL` depending on how the sync applied the new column). `NULL == threadIndex` is never true in SQL, so such rows can go permanently invisible to every worker. Either let the marking loop's own where-clause revisit them next cycle (if it's inclusive of the current status), or do a one-time backfill.
5. The worker controller's parameter class carries the assigned `threadIndex` (set by the spawn loop below); the service method filters on it directly, alongside the status set by marking:
   ```
   while select forUpdate Invoicetable
       where Invoicetable.IntegrationStatus == EZ_IntegrationStatus::InProcessing
          && Invoicetable.ThreadIndex      == this.parmThreadIndex()
   {
       // process row
   }
   ```
6. The spawn loop that creates the N worker tasks must use the *same* numbering base as the stamping loop. If stamping wrote `counter mod totalThreads` (0-based, values `0..N-1`), the spawn loop must iterate `for (i = 0; i < totalThreads; i++)` and call `worker.parmThreadIndex(i)` — not `1..N`. A silent off-by-one here (stamping 0-based but spawning 1-based, or vice versa) leaves bucket `N-1` (or `0`) permanently unclaimed by any worker — a distribution bug that looks identical to Pitfall 1's symptom but has a different root cause, so check this before re-diagnosing the RecId allocator.

## Sequencing: don't assume "marking already committed" is enough — use a real batch dependency

Even with marking and worker-spawning in the same method, in the same order, with the marking transaction committed first, do not assume that guarantees workers won't start before the marked data is visible. Batch task dispatch timing is the framework's business, not yours to reason about via code ordering. Use the framework's actual sequencing primitive:

- Split the job into two tiers: a dedicated **marking task** (its own controller + service method, containing the stamping loop) and the **N worker tasks**.
- Add the marking task to the batch header first: `batchHeader.addTask(markController)`.
- For every worker task, after adding it, wire an explicit dependency: `batchHeader.addDependency(workerController, markController, BatchDependencyStatus::Finished)`.
- This creates a real `BatchDependency` row — the batch framework itself withholds each worker from leaving `Waiting` until the marking task's `Batch.Status == Finished`. That's deterministic; commit-timing assumptions are not.
- **Gotcha:** `BatchHeader.addDependency(taskToRun, dependsOnTask, ...)` requires *both* tasks to already be in that `BatchHeader` instance's `addedTasks` set (i.e., both added via `addTask()` in the same call). You cannot make new tasks depend on the *currently-executing parent* controller (the one that's running `process()` right now) — it isn't part of that set. That's exactly why marking needs to be its own separate task added alongside the workers, not inline logic in the parent.

## Verifying the fix actually worked

Don't just trust that the code compiles — confirm real parallelism happened after a run:
- Query the backlog table grouped by `ThreadIndex` for the rows just marked (`select count(RecId) ... group by ThreadIndex`). Counts should be roughly even (within 1 of each other for round-robin). A lopsided distribution means the stamping loop or the numbering base is still wrong.
- Check the `Batch`/`BatchJob` history for the worker tasks: all N should show comparable start/end timestamps and comparable elapsed duration. One task finishing in milliseconds while another runs the full expected duration is the signature of Pitfall 1 or 2 recurring — one worker got everything, the rest got nothing.
- Confirm the marking task's `Batch.Status` reached `Finished` strictly before any worker task's status left `Waiting`. If a worker started earlier, the `addDependency` wiring is missing or wrong.

## Worker retries: make re-processing safe, not just "shouldn't happen"

The batch framework can retry a worker task (a manual restart from Batch job history, or an infrastructure-level retry) after it has already partially processed its slice. Partitioning only guarantees *which* rows a worker owns — it does not guarantee a worker never runs twice.
- Update each row's status away from `InProcessing` (to `Processed`/`Error`) in the same transaction as the business logic, so a retried worker's `where IntegrationStatus == InProcessing` filter skips already-completed rows instead of redoing them.
- If the business logic itself isn't naturally idempotent (e.g. it calls an external API that isn't safe to call twice), flip the status — or write a distinct "claimed" sub-state — before the external call, not after, so a retry sees the row as already in flight rather than eligible again.

## Recurring-job re-entrancy guard

If the batch job is recurring, remember: D365FO resets a finished recurring `BatchJob` back to `Waiting` rather than creating a new `BatchJob` row each occurrence. So:
- Don't count *all* `Batch` rows ever created under that header (across all historical cycles) to decide whether a new cycle can spawn tasks — that guard trips forever after the very first cycle.
- Scope the count to still-active tasks only: `Status != Finished && Status != Error && Status != Canceled`.
- The currently-running task itself is always one of those active rows, so the guard threshold is `> 1` (self + at least one other still-active task), not `> 0`.

## Quick checklist when reviewing/designing one of these jobs

- [ ] Partition key is a value you assign yourself (stamped field), never a raw `mod` on an existing ID column.
- [ ] Stamping uses round-robin over a stable-ordered scan, not contiguous chunking.
- [ ] Worker selects filter on the stamped field, and the numbering scheme (0-based vs 1-based) matches exactly between the stamping code and the spawn loop that sets each worker's `threadIndex` parameter.
- [ ] Marking and worker dispatch are sequenced via `BatchDependency` (`addTask` + `addDependency(..., BatchDependencyStatus::Finished)`), not implicit ordering/commit-timing assumptions.
- [ ] Recurring-cycle guard counts only non-terminal `Batch` rows under the header, with threshold `> 1` to account for the currently-running task itself.
- [ ] If adding a new persisted field to an existing table, check whether pre-existing rows get a real default (`0`) vs `NULL`, since `NULL == x` is never true in SQL and can silently orphan old rows.
- [ ] After a test run, `ThreadIndex` row counts and per-worker `Batch` durations are checked to confirm real parallelism occurred, not just that the code compiled.
- [ ] Worker logic updates each row's status (away from the "in progress" state) in the same transaction as the business logic, so a framework-retried worker task doesn't reprocess already-completed rows.
- [ ] The backlog is large/steady enough that the marking task + dependency overhead is worth it — this pattern isn't the default for every batch job.
