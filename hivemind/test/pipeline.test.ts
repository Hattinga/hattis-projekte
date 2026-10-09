import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, afterEach, before, test } from "node:test";
import { setAgentImplementation, type AgentRun, type AgentResult } from "../src/agent.js";
import { bus, type HiveEvent } from "../src/bus.js";
import { DEFAULT_CONFIG, DEFAULT_ROLES, type Config } from "../src/config.js";
import { git } from "../src/git.js";
import { memoryFile } from "../src/pipeline/memory.js";
import { runHivemind } from "../src/pipeline/run.js";
import { listRuns, runsRoot } from "../src/state.js";

// A whole run without a single real agent: fake agents answer like the real ones would,
// so the pipeline around them (planning, scheduling, worktrees, merges, fixes, memory) runs for real.

const dirs: string[] = [];
let home: string;

before(() => {
  home = mkdtempSync(join(tmpdir(), "hivemind-home-"));
  dirs.push(home);
  process.env.HIVEMIND_HOME = home;
});

afterEach(() => setAgentImplementation(null));

after(() => {
  delete process.env.HIVEMIND_HOME;
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

function newRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "hivemind-pipeline-"));
  dirs.push(dir);
  git(dir, "init", "-q", "-b", "main");
  git(dir, "config", "user.name", "Test");
  git(dir, "config", "user.email", "test@example.com");
  writeFileSync(join(dir, "README.md"), "# Test\n");
  git(dir, "add", "-A");
  git(dir, "commit", "-qm", "init");
  return git(dir, "rev-parse", "--show-toplevel");
}

const PLAN = {
  summary: "Drei Dateien anlegen.",
  decisions: ["einfach halten"],
  tasks: [
    { id: "t1", title: "eins", description: "leg eins an", files: ["shared.txt"], dependsOn: [], difficulty: "easy" },
    { id: "t2", title: "zwei", description: "leg zwei an", files: ["shared.txt"], dependsOn: [], difficulty: "normal" },
    { id: "t3", title: "drei", description: "leg drei an", files: ["drei.txt"], dependsOn: ["t1"], difficulty: "hard" },
  ],
};

interface Call {
  name: string;
  model?: string;
  prompt: string;
  resume?: string;
}

/** Fake agents keyed by name. Coders write `<task>.txt` into their worktree; hivemind commits it. */
function fakeTeam(calls: Call[], options: { costPerAgent?: number } = {}) {
  let testerRuns = 0;
  return async (run: AgentRun<unknown>): Promise<AgentResult<unknown>> => {
    calls.push({ name: run.name, model: run.model, prompt: run.prompt, resume: run.resume });
    if (options.costPerAgent) bus.emitEvent({ type: "cost", agent: run.name, usd: options.costPerAgent });
    const reply = (data: unknown, text = "ok"): AgentResult<unknown> => ({ text, data, costUsd: options.costPerAgent ?? 0, sessionId: `s-${calls.length}`, spoke: false });

    if (run.name === "Optimizer") return reply({ brief: "Baue drei Dateien.", size: "M", overview: "Leeres Testprojekt mit README.", questions: [] });
    if (run.name === "Moderatorin") return reply(PLAN);
    if (run.name.startsWith("Reviewer")) return reply({ approved: true, feedback: "" });
    if (run.name === "Testerin") {
      testerRuns++;
      return testerRuns === 1
        ? reply({ report: "fix.txt fehlt", passed: false, problems: ["Leg fix.txt an"] })
        : reply({ report: "alles gut", passed: true, problems: [] });
    }
    if (run.name === "Chronistin") return reply({ memory: "- Dateien heißen <task>.txt" });
    if (run.name.startsWith("Coder")) {
      // The prompt lists the whole plan; the coder's own task follows "Deine Task".
      const id = /Deine Task \[([^\]]+)\]/.exec(run.prompt)?.[1] ?? "unbekannt";
      writeFileSync(join(run.cwd, id.startsWith("fix") ? "fix.txt" : `${id}.txt`), `${id}\n`);
      return reply(undefined, `${id} erledigt`);
    }
    // Planners: free text in round 1, agreement afterwards.
    return run.schema ? reply({ message: "passt", agrees: true }) : reply(undefined, "Vorschlag");
  };
}

/** Answers every question the way a happy customer would. */
function autoAnswer(answers: (question: string, choices?: string[]) => string) {
  return bus.onEvent((event) => {
    if (event.type === "ask") setImmediate(() => bus.answer(event.id, answers(event.question, event.choices)));
  });
}

function collect(): { events: HiveEvent[]; stop: () => void } {
  const events: HiveEvent[] = [];
  return { events, stop: bus.onEvent((e) => events.push(e)) };
}

const config = (): Config => ({ ...DEFAULT_CONFIG, roles: { ...DEFAULT_ROLES }, coders: 3 });

test("a full run: plan, parallel coders without clashes, a fix round, memory", async () => {
  const repo = newRepo();
  const calls: Call[] = [];
  setAgentImplementation(fakeTeam(calls));
  const { events, stop } = collect();
  const stopAnswering = autoAnswer((question) => {
    if (question.startsWith("Plan freigeben")) {
      bus.emitEvent({ type: "note", text: "bitte UTF-8 verwenden" });
      return "freigeben";
    }
    return "fertig";
  });

  try {
    await runHivemind({ request: "drei Dateien", cwd: repo, config: config(), planOnly: false, signal: new AbortController().signal });
  } finally {
    stop();
    stopAnswering();
  }

  const run = listRuns(runsRoot(repo))[0]!;
  assert.equal(run.status, "done", JSON.stringify(events.filter((e) => e.type === "error")));
  const errors = events.filter((e) => e.type === "error");
  assert.deepEqual([...run.doneTasks].filter((id) => id.startsWith("t")).sort(), ["t1", "t2", "t3"], JSON.stringify(errors));

  // Everything landed on the run's branch, nothing in your checkout.
  const files = git(repo, "ls-tree", "--name-only", run.branch!).split("\n").map((f) => f.trim());
  for (const file of ["t1.txt", "t2.txt", "t3.txt", "fix.txt"]) assert.ok(files.includes(file), `${file} fehlt auf ${run.branch}`);
  assert.equal(existsSync(join(repo, "t1.txt")), false);
  assert.equal(git(repo, "worktree", "list").split("\n").length, 1, "all worktrees are cleaned up");

  // t1 and t2 both touch shared.txt, so they ran one after the other.
  assert.ok(events.some((e) => e.type === "info" && /\[t2\] wartet auf \[t1\]/.test(e.text)));

  // The tester found a problem, a coder fixed it, the tester checked again in her own session.
  const testerCalls = calls.filter((c) => c.name === "Testerin");
  assert.equal(testerCalls.length, 2);
  assert.ok(testerCalls[1]!.resume, "the re-check continues the tester's session");

  // Routing: the easy task went to Haiku, the hard one to Opus, planners on Sonnet for a medium request.
  const coderModel = (task: string) => calls.find((c) => c.name.startsWith("Coder") && c.prompt.includes(`Deine Task [${task}]`))?.model;
  assert.equal(coderModel("t1"), "claude-haiku-5-5");
  assert.equal(coderModel("t3"), "claude-opus-5-5");
  assert.equal(calls.find((c) => c.name === "Architektin")?.model, "claude-sonnet-5-5");
  assert.equal(calls.find((c) => c.name === "Moderatorin")?.model, "claude-opus-5-5");

  // Every agent got the optimizer's overview; agents after your note got the note.
  assert.ok(calls.filter((c) => c.name !== "Optimizer" && !c.resume).every((c) => c.prompt.includes("Leeres Testprojekt mit README.")));
  assert.ok(calls.filter((c) => c.name.startsWith("Coder")).every((c) => c.prompt.includes("bitte UTF-8 verwenden")));

  // The historian wrote the memory, and the next run starts with it.
  assert.equal(readFileSync(memoryFile(repo), "utf8").trim(), "- Dateien heißen <task>.txt");
  const next: Call[] = [];
  setAgentImplementation(fakeTeam(next));
  const stopAgain = autoAnswer(() => "freigeben");
  try {
    await runHivemind({ request: "nochmal", cwd: repo, config: config(), planOnly: true, signal: new AbortController().signal });
  } finally {
    stopAgain();
  }
  assert.ok(next[0]!.prompt.includes("Dateien heißen <task>.txt"), "the optimizer of the next run knows the memory");
});

test("the budget stops the run cleanly and it can be resumed with more", async () => {
  const repo = newRepo();
  const calls: Call[] = [];
  setAgentImplementation(fakeTeam(calls, { costPerAgent: 1 }));
  const stopAnswering = autoAnswer((question) => (question.startsWith("Plan") ? "freigeben" : "fertig"));
  try {
    await runHivemind({ request: "teuer", cwd: repo, config: { ...config(), budgetUsd: 2.5 }, planOnly: false, signal: new AbortController().signal });
  } finally {
    stopAnswering();
  }
  const run = listRuns(runsRoot(repo))[0]!;
  assert.equal(run.status, "aborted");
  assert.equal(calls.length, 3, "optimizer and two planners, then the budget is used up");
  assert.ok(run.brief, "what was done so far is kept for --resume");
});

test("an empty repo gets a start commit before anyone works", async () => {
  const dir = mkdtempSync(join(tmpdir(), "hivemind-empty-"));
  dirs.push(dir);
  git(dir, "init", "-q", "-b", "main");
  git(dir, "config", "user.name", "Test");
  git(dir, "config", "user.email", "test@example.com");
  const calls: Call[] = [];
  setAgentImplementation(fakeTeam(calls));
  const questions: string[] = [];
  const stopAnswering = autoAnswer((question, choices) => {
    questions.push(question);
    return choices?.[0] ?? "x";
  });
  try {
    await runHivemind({ request: "leer", cwd: dir, config: config(), planOnly: false, signal: new AbortController().signal });
  } finally {
    stopAnswering();
  }
  assert.match(questions[0]!, /noch keinen Commit/);
  assert.equal(calls[0]?.name, "Optimizer", "the question came before the first agent");
  assert.equal(git(dir, "log", "--format=%s", "main").split("\n").at(-1), "Start");
});
