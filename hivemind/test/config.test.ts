import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { DEFAULT_CONFIG, loadConfig } from "../src/config.js";
import { planningTeam } from "../src/pipeline/plan.js";
import { findResumable, listRuns, RunStore, type RunState } from "../src/state.js";
import { TeamBoard } from "../src/team.js";

const dir = mkdtempSync(join(tmpdir(), "hivemind-config-"));
after(() => rmSync(dir, { recursive: true, force: true }));

test("project config overrides defaults and merges roles field by field", () => {
  writeFileSync(
    join(dir, "hivemind.config.json"),
    JSON.stringify({
      coders: 1,
      planners: ["architect", "roblox"],
      roles: { coder: { model: "claude-sonnet-5-5" }, roblox: { title: "Roblox-Profi", persona: "Luau!" } },
    }),
  );
  const config = loadConfig(dir);
  assert.equal(config.coders, 1);
  assert.equal(config.discussionRounds, DEFAULT_CONFIG.discussionRounds);
  assert.equal(config.roles.coder!.model, "claude-sonnet-5-5");
  assert.equal(config.roles.coder!.title, "Coder", "unchanged fields of a role stay");
  assert.equal(config.roles.roblox!.title, "Roblox-Profi");
});

test("a planner without a role definition is an error, not a silent skip", () => {
  const other = join(dir, "kaputt");
  mkdirSync(other);
  writeFileSync(join(other, "hivemind.config.json"), JSON.stringify({ planners: ["gibtsnicht"] }));
  assert.throws(() => loadConfig(other), /gibtsnicht/);
});

test("triage: small requests get a small team, large ones everyone", () => {
  const config = { ...DEFAULT_CONFIG, discussionRounds: 3 };
  assert.deepEqual(planningTeam("S", config), { planners: ["architect", "skeptic"], rounds: 1 });
  assert.deepEqual(planningTeam("M", config), { planners: config.planners, rounds: 2 });
  assert.deepEqual(planningTeam("L", config), { planners: config.planners, rounds: 3 });
  assert.deepEqual(planningTeam("S", { ...config, triage: false }), { planners: config.planners, rounds: 3 });
});

test("team board: everyone reads what the others posted, once", () => {
  const board = new TeamBoard();
  board.post("Coder 1", "Ich ändere die Signatur von add()");
  board.post("Coder 2", "ok");
  assert.deepEqual(board.unread("Coder 2").map((m) => m.from), ["Coder 1"]);
  assert.deepEqual(board.unread("Coder 2"), []);
  board.post("Coder 1", "fertig");
  assert.deepEqual(board.unread("Coder 2").map((m) => m.text), ["fertig"]);
  assert.equal(board.catchUp("Coder 3"), "- Coder 1: Ich ändere die Signatur von add()\n- Coder 2: ok\n- Coder 1: fertig");
});

test("runs: newest first, resume picks the newest unfinished one", () => {
  const base: Omit<RunState, "id" | "status"> = { request: "x", cwd: dir, createdAt: "", phase: "", costUsd: 0, plans: [], doneTasks: [] };
  for (const [id, status] of [["20261001-0900", "aborted"], ["20261002-0900", "done"], ["20261003-0900", "failed"]] as const) {
    const runDir = join(dir, "runs", id);
    mkdirSync(runDir, { recursive: true });
    new RunStore(runDir, { ...base, id, status }).update({});
  }
  const root = join(dir, "runs");
  assert.deepEqual(listRuns(root).map((r) => r.id), ["20261003-0900", "20261002-0900", "20261001-0900"]);
  assert.equal(findResumable(root)?.id, "20261003-0900");
  assert.equal(findResumable(root, "20261001-0900")?.status, "aborted");
  assert.equal(findResumable(root, "nope"), undefined);
});

test("routing: the tier picks the model, a role's own model wins, --model turns it off", async () => {
  const { modelFor, modelLabel } = await import("../src/config.js");
  const config = { ...DEFAULT_CONFIG };
  const coder = DEFAULT_CONFIG.roles.coder!;
  assert.equal(modelFor(coder, "easy", config), "claude-haiku-5-5");
  assert.equal(modelFor(coder, "normal", config), "claude-sonnet-5-5");
  assert.equal(modelFor(coder, "hard", config), "claude-opus-5-5");
  assert.equal(modelFor({ ...coder, model: "claude-haiku-4-5" }, "hard", config), "claude-haiku-4-5");
  assert.equal(modelFor(coder, "easy", { ...config, routing: false, model: "claude-sonnet-5" }), "claude-sonnet-5");
  assert.equal(modelLabel("claude-sonnet-5-5"), "Sonnet 5.5");
  assert.equal(modelLabel("claude-opus-5"), "Opus 5");
  assert.equal(modelLabel("claude-haiku-4-5-20251001"), "claude-haiku-4-5-20251001");
});

test("routing: a config can replace single tiers", () => {
  const other = join(dir, "modelle");
  mkdirSync(other);
  writeFileSync(join(other, "hivemind.config.json"), JSON.stringify({ models: { easy: "claude-haiku-4-5" } }));
  const config = loadConfig(other);
  assert.deepEqual(config.models, { easy: "claude-haiku-4-5", normal: "claude-sonnet-5-5", hard: "claude-opus-5-5" });
});

test("a project config can build on a team preset and change single things of it", () => {
  const other = join(dir, "rakete");
  mkdirSync(other);
  writeFileSync(
    join(other, "hivemind.config.json"),
    JSON.stringify({ team: "roblox-studio", planners: ["designer", "roblox"], roles: { designer: { title: "Spieldesignerin", persona: "Spaß!" }, architect: { persona: "eigene" } } }),
  );
  const config = loadConfig(other);
  assert.equal(config.team, "roblox-studio");
  assert.equal(config.mode, "studio");
  assert.equal(config.roles.roblox!.title, "Roblox-Profi", "from the preset");
  assert.deepEqual(config.roles.coder!.mcp, ["Roblox_Studio"], "from the preset");
  assert.equal(config.roles.architect!.title, "Architektin", "a partial role keeps the rest");
  assert.equal(config.roles.architect!.persona, "eigene");
  assert.equal(config.roles.designer!.title, "Spieldesignerin");
  const plain = join(dir, "nur-team");
  mkdirSync(plain);
  writeFileSync(join(plain, "hivemind.config.json"), JSON.stringify({ team: "roblox-studio" }));
  assert.equal(loadConfig(plain, "web").mode, "git", "--team on the command line wins over the file's team");
});

test("studio roles: readers and testers get an allow-list, coders get the whole server", () => {
  const studio = loadConfig(join(dir, "rakete"));
  assert.ok(studio.roles.reviewer!.mcpTools!.every((t) => /script_read|script_grep|script_search|search_game_tree|inspect_instance|get_console_output|get_studio_state|list_roblox_studios/.test(t)));
  assert.ok(studio.roles.tester!.mcpTools!.includes("mcp__Roblox_Studio__start_stop_play"));
  assert.ok(!studio.roles.tester!.mcpTools!.includes("mcp__Roblox_Studio__multi_edit"), "the tester can't edit scripts");
  assert.equal(studio.roles.coder!.mcpTools, undefined);
});
