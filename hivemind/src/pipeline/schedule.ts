export interface Schedulable {
  id: string;
  dependsOn: string[];
}

export interface ScheduleResult {
  done: string[];
  failed: string[];
  /** Tasks that never ran because something they depend on failed. */
  skipped: string[];
}

/**
 * Runs tasks with at most `slots` at a time. A task starts once every task it depends on
 * is done; dependencies on ids outside `tasks` (or in `alreadyDone`) count as done.
 * `work` gets a slot number from 1 to `slots`, so the UI can show "Coder 2" etc.
 */
export async function schedule<T extends Schedulable>(
  tasks: T[],
  slots: number,
  work: (task: T, slot: number) => Promise<void>,
  options: { alreadyDone?: Iterable<string>; signal?: AbortSignal; onFail?: (task: T, error: unknown) => void } = {},
): Promise<ScheduleResult> {
  const ids = new Set(tasks.map((t) => t.id));
  const done = new Set(options.alreadyDone ?? []);
  const result: ScheduleResult = { done: [], failed: [], skipped: [] };
  const pending = tasks.filter((t) => !done.has(t.id));
  const running = new Map<string, Promise<void>>();
  const freeSlots = Array.from({ length: Math.max(1, slots) }, (_, i) => i + 1);
  const blocked = (t: T) => t.dependsOn.some((id) => result.failed.includes(id) || result.skipped.includes(id));
  const ready = (t: T) => t.dependsOn.every((id) => done.has(id) || !ids.has(id));

  while (pending.length || running.size) {
    if (options.signal?.aborted) throw new Error("Abgebrochen.");

    for (const task of pending.filter(blocked)) {
      pending.splice(pending.indexOf(task), 1);
      result.skipped.push(task.id);
    }

    for (const task of pending.filter(ready)) {
      const slot = freeSlots.shift();
      if (slot === undefined) break;
      pending.splice(pending.indexOf(task), 1);
      running.set(
        task.id,
        work(task, slot)
          .then(() => {
            done.add(task.id);
            result.done.push(task.id);
          })
          .catch((error) => {
            result.failed.push(task.id);
            options.onFail?.(task, error);
          })
          .finally(() => {
            running.delete(task.id);
            freeSlots.push(slot);
            freeSlots.sort((a, b) => a - b);
          }),
      );
    }

    if (running.size === 0) {
      // Nothing runs and nothing can start: the rest depends on each other in a cycle.
      result.skipped.push(...pending.map((t) => t.id));
      break;
    }
    await Promise.race(running.values());
  }
  return result;
}
