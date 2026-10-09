import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import type { Size } from "./pipeline/optimize.js";
import type { Plan } from "./pipeline/plan.js";

export type RunStatus = "running" | "done" | "aborted" | "failed";

/** Everything needed to show a past run or continue an interrupted one. Lives in .hivemind/<id>/state.json. */
export interface RunState {
  id: string;
  request: string;
  /** Folder hivemind was started in. */
  cwd: string;
  createdAt: string;
  status: RunStatus;
  phase: string;
  costUsd: number;
  brief?: string;
  size?: Size;
  /** Approved plans: the first one, then one per round of follow-ups. */
  plans: Plan[];
  doneTasks: string[];
  branch?: string;
}

export class RunStore {
  readonly file: string;

  constructor(readonly dir: string, public state: RunState) {
    this.file = join(dir, "state.json");
  }

  update(patch: Partial<RunState>) {
    this.state = { ...this.state, ...patch };
    writeFileSync(this.file, JSON.stringify(this.state, null, 2));
  }
}

/**
 * Where a project's runs live: ~/.hivemind/projects/<name>-<hash>/. Outside the project on purpose,
 * so agents looking around the project never stumble over transcripts or other runs' worktrees.
 */
export function runsRoot(project: string): string {
  const path = resolve(project);
  const hash = createHash("sha1").update(path.toLowerCase()).digest("hex").slice(0, 8);
  return join(homedir(), ".hivemind", "projects", `${basename(path)}-${hash}`);
}

/** All runs in `root` (see runsRoot), newest first. */
export function listRuns(root: string): RunState[] {
  if (!existsSync(root)) return [];
  return readdirSync(root)
    .map((id) => join(root, id, "state.json"))
    .filter((file) => existsSync(file))
    .map((file) => JSON.parse(readFileSync(file, "utf8")) as RunState)
    .sort((a, b) => b.id.localeCompare(a.id));
}

/** The run to continue: the given id, or the newest one that did not finish. */
export function findResumable(root: string, id?: string): RunState | undefined {
  const runs = listRuns(root);
  if (id) return runs.find((r) => r.id === id);
  return runs.find((r) => r.status !== "done");
}
