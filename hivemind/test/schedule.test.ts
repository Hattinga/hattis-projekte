import assert from "node:assert/strict";
import { test } from "node:test";
import { schedule } from "../src/pipeline/schedule.js";

const task = (id: string, ...dependsOn: string[]) => ({ id, dependsOn });
const tick = () => new Promise((r) => setTimeout(r, 5));

test("never runs more tasks at once than there are slots", async () => {
  let running = 0;
  let peak = 0;
  const slotsSeen = new Set<number>();
  await schedule([task("a"), task("b"), task("c"), task("d"), task("e")], 2, async (_t, slot) => {
    slotsSeen.add(slot);
    peak = Math.max(peak, ++running);
    await tick();
    running--;
  });
  assert.equal(peak, 2);
  assert.deepEqual([...slotsSeen].sort(), [1, 2]);
});

test("starts a task only after its dependencies are done", async () => {
  const order: string[] = [];
  const result = await schedule([task("c", "a", "b"), task("a"), task("b", "a")], 3, async (t) => {
    order.push(`start ${t.id}`);
    await tick();
    order.push(`end ${t.id}`);
  });
  assert.deepEqual(order, ["start a", "end a", "start b", "end b", "start c", "end c"]);
  assert.deepEqual(result, { done: ["a", "b", "c"], failed: [], skipped: [] });
});

test("skips everything downstream of a failed task but keeps the rest going", async () => {
  const failures: string[] = [];
  const result = await schedule(
    [task("a"), task("b", "a"), task("c", "b"), task("d")],
    2,
    async (t) => {
      await tick();
      if (t.id === "a") throw new Error("kaputt");
    },
    { onFail: (t) => failures.push(t.id) },
  );
  assert.deepEqual(result.done, ["d"]);
  assert.deepEqual(result.failed, ["a"]);
  assert.deepEqual(result.skipped.sort(), ["b", "c"]);
  assert.deepEqual(failures, ["a"]);
});

test("does not rerun tasks finished in an earlier run, and treats them as done", async () => {
  const ran: string[] = [];
  const result = await schedule([task("a"), task("b", "a")], 1, async (t) => void ran.push(t.id), { alreadyDone: ["a"] });
  assert.deepEqual(ran, ["b"]);
  assert.deepEqual(result.done, ["b"]);
});

test("ignores dependencies on tasks that are not in the plan", async () => {
  const result = await schedule([task("a", "gibts-nicht")], 1, async () => {});
  assert.deepEqual(result.done, ["a"]);
});

test("gives up on tasks that wait for each other instead of hanging", async () => {
  const result = await schedule([task("a", "b"), task("b", "a"), task("c")], 2, async () => {});
  assert.deepEqual(result.done, ["c"]);
  assert.deepEqual(result.skipped.sort(), ["a", "b"]);
});

test("stops when aborted", async () => {
  const abort = new AbortController();
  await assert.rejects(
    schedule([task("a"), task("b", "a")], 1, async () => abort.abort(), { signal: abort.signal }),
    /Abgebrochen/,
  );
});
