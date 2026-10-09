#!/usr/bin/env node
import { render } from "ink";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { bus } from "./bus.js";
import { listTeams, loadConfig } from "./config.js";
import { git, isGitRepo } from "./git.js";
import { memoryFile, readMemory } from "./pipeline/memory.js";
import { runHivemind } from "./pipeline/run.js";
import { findResumable, listRuns, runsRoot, type RunState } from "./state.js";
import { App } from "./ui/App.js";

const HELP = `hivemind - eine kleine KI-Firma für dein Projekt

  hivemind ["was gebaut werden soll"] [Optionen]
  hivemind runs                 zeigt die bisherigen Läufe in diesem Projekt
  hivemind --resume [id]        setzt einen abgebrochenen Lauf fort
  hivemind teams                zeigt die Team-Vorlagen
  hivemind memory               zeigt, was das Team über dieses Projekt weiß

Ohne Prompt fragt hivemind dich danach.

Optionen:
  -C, --cwd <ordner>   Projektordner (Standard: aktueller Ordner)
  -p, --plan-only      nur Optimizer + Planungs-Team, kein Code
  -t, --team <name>    Team-Vorlage, z.B. sparsam, roblox, web (siehe hivemind teams)
  -b, --budget <usd>   höchstens so viele Dollar (Schätzung), dann sauber stoppen
  -f, --full           immer das ganze Planungs-Team, egal wie klein der Auftrag ist
  -r, --rounds <n>     höchstens so viele Diskussionsrunden (Standard: 3)
  -c, --coders <n>     parallele Coder (Standard: 3)
  -m, --model <id>     ein Modell für alle Agents, statt es pro Aufgabe zu wählen
  -a, --ask            Agents fragen dich vor heiklen Aktionen (statt volle Rechte)
  -h, --help           diese Hilfe

Rollen, Personas und Modelle lassen sich in hivemind.config.json (im Projekt)
oder ~/.hivemind/config.json anpassen, siehe README.`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    cwd: { type: "string", short: "C" },
    "plan-only": { type: "boolean", short: "p", default: false },
    team: { type: "string", short: "t" },
    budget: { type: "string", short: "b" },
    full: { type: "boolean", short: "f", default: false },
    rounds: { type: "string", short: "r" },
    coders: { type: "string", short: "c" },
    model: { type: "string", short: "m" },
    ask: { type: "boolean", short: "a", default: false },
    resume: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
});

if (values.help) {
  console.log(HELP);
  process.exit(0);
}

const cwd = resolve(values.cwd ?? process.cwd());
const repo = isGitRepo(cwd) ? git(cwd, "rev-parse", "--show-toplevel") : cwd;

const STATUS: Record<RunState["status"], string> = { running: "läuft", done: "fertig", aborted: "abgebrochen", failed: "fehlgeschlagen" };

if (positionals[0] === "runs" && positionals.length === 1) {
  const runs = listRuns(runsRoot(repo));
  if (runs.length === 0) console.log("Noch keine Läufe in diesem Projekt.");
  for (const run of runs) {
    const request = run.request.replace(/\s+/g, " ");
    console.log(
      `${run.id}  ${STATUS[run.status].padEnd(14)} $${run.costUsd.toFixed(2).padStart(6)}  ${run.phase.padEnd(20)} ${request.length > 60 ? `${request.slice(0, 57)}...` : request}`,
    );
  }
  process.exit(0);
}

if (positionals[0] === "teams" && positionals.length === 1) {
  for (const [name, team] of Object.entries(listTeams())) console.log(`${name.padEnd(12)} ${team.description}`);
  console.log("\nEigene Teams: ~/.hivemind/teams/<name>.json (Aufbau wie hivemind.config.json, plus \"description\")");
  process.exit(0);
}

if (positionals[0] === "memory" && positionals.length === 1) {
  const memory = readMemory(repo);
  console.log(memory || "Das Team weiß noch nichts über dieses Projekt. Nach dem ersten fertigen Lauf steht hier etwas.");
  console.log(`\n(${memoryFile(repo)}, du kannst die Datei selbst bearbeiten)`);
  process.exit(0);
}

let resume: RunState | undefined;
if (values.resume) {
  resume = findResumable(runsRoot(repo), positionals[0]);
  if (!resume) {
    console.error(positionals[0] ? `Lauf ${positionals[0]} gibt es nicht. Siehe: hivemind runs` : "Kein abgebrochener Lauf zum Fortsetzen.");
    process.exit(1);
  }
}

let config: ReturnType<typeof loadConfig>;
try {
  config = loadConfig(cwd, values.team);
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
if (values.budget) {
  const budget = Number(values.budget.replace(",", "."));
  if (!(budget > 0)) {
    console.error(`--budget braucht einen Betrag in Dollar, z.B. --budget 3 (nicht "${values.budget}").`);
    process.exit(1);
  }
  config.budgetUsd = budget;
}
if (values.rounds) config.discussionRounds = Math.max(1, Number(values.rounds));
if (values.coders) config.coders = Math.max(1, Number(values.coders));
if (values.model) {
  // One model for everyone: no routing.
  config.model = values.model;
  config.routing = false;
}
if (values.ask) config.permissionMode = "auto";
if (values.full) config.triage = false;

const abort = new AbortController();
let running: Promise<void> | undefined;
const start = (request?: string) => {
  running = runHivemind({ request, resume, cwd: resume?.cwd ?? cwd, config, planOnly: values["plan-only"], signal: abort.signal });
};

// After Ctrl+C the UI is gone, but the run still reports how it ended; print that plainly.
let uiClosed = false;
bus.onEvent((event) => {
  if (uiClosed && event.type === "finished") console.log(`\n${event.summary}`);
});

const initialRequest = resume ? undefined : positionals.join(" ").trim() || undefined;
const app = render(<App initialRequest={initialRequest} autoStart={Boolean(resume)} start={start} alwaysFull={[config.roles.moderator!.title]} />);
await app.waitUntilExit();
uiClosed = true;

if (running) {
  // Ctrl+C: stop every agent, then give the run a moment to clean up its worktrees and save its state.
  abort.abort();
  bus.cancelAsks("Abgebrochen.");
  await Promise.race([running, new Promise((r) => setTimeout(r, 10_000))]);
}
process.exit(0);
