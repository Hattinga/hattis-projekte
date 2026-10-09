import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { z } from "zod";
import { runAgent } from "../agent.js";
import { bus } from "../bus.js";
import { modelFor, type Config } from "../config.js";
import { runsRoot } from "../state.js";
import { formatPlan, type Plan } from "./plan.js";

/** The team's memory of a project, next to its runs: ~/.hivemind/projects/<projekt>/memory.md. */
export function memoryFile(repo: string): string {
  return join(runsRoot(repo), "memory.md");
}

export function readMemory(repo: string): string {
  const file = memoryFile(repo);
  return existsSync(file) ? readFileSync(file, "utf8").trim() : "";
}

const Memory = z.object({
  memory: z.string().describe("Das komplette neue Gedächtnis (Markdown), ersetzt das alte."),
});

/** After a finished run, the historian folds what the team learned into the project memory. */
export async function updateMemory(options: {
  repo: string;
  cwd: string;
  brief: string;
  plans: Plan[];
  report: string;
  config: Config;
  signal: AbortSignal;
}): Promise<void> {
  const { repo, config } = options;
  const historian = config.roles.historian!;
  const old = readMemory(repo);
  const { data } = await runAgent({
    name: historian.title,
    team: "Abschluss",
    role: historian,
    model: modelFor(historian, "easy", config),
    config,
    prompt: `Bisheriges Gedächtnis:\n\n${old || "(noch leer)"}\n\nDieser Lauf:\n\nAuftrag:\n${options.brief}\n\n${options.plans.map(formatPlan).join("\n\n")}\n\nAbschlussbericht:\n${options.report}\n\nSchreib das aktualisierte Gedächtnis. Den aktuellen Code findest du in deinem Arbeitsverzeichnis, falls du etwas nachprüfen willst.`,
    cwd: options.cwd,
    access: "read",
    schema: Memory,
    signal: options.signal,
  });
  const file = memoryFile(repo);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, `${data.memory.trim()}\n`);
  bus.emitEvent({ type: "info", text: `Gedächtnis aktualisiert: ${file}` });
}
