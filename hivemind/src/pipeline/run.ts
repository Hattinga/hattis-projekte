import { appendFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { errorText } from "../agent.js";
import { bus, type HiveEvent } from "../bus.js";
import type { Config } from "../config.js";
import { git, hasCommits, hasUncommittedChanges, isGitRepo, Workspace } from "../git.js";
import { RunStore, runsRoot, type RunState } from "../state.js";
import { codingTeam } from "./code.js";
import { optimizePrompt } from "./optimize.js";
import { CancelledByUser, followUpPlan, formatPlan, planTeam, type Plan } from "./plan.js";

export interface RunOptions {
  /** A new request, or `resume` to continue an interrupted run. */
  request?: string;
  resume?: RunState;
  cwd: string;
  config: Config;
  /** Stop after the plan instead of handing it to the coders. */
  planOnly: boolean;
  signal: AbortSignal;
}

function newRunId(): string {
  return new Date().toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15);
}

/** Writes everything that happens into .hivemind/<runId>/transcript.md. */
function recordTranscript(dir: string) {
  const file = join(dir, "transcript.md");
  if (!existsSync(file)) writeFileSync(file, `# hivemind ${new Date().toLocaleString("de-AT")}\n\n`);
  else appendFileSync(file, `\n---\n\n# Fortgesetzt ${new Date().toLocaleString("de-AT")}\n\n`);
  const line = (event: HiveEvent): string | null => {
    switch (event.type) {
      case "phase": return `\n## ${event.phase}\n`;
      case "say": return `### ${event.agent}\n\n${event.text}\n`;
      case "chat": return `> 💬 **${event.from}:** ${event.text}\n`;
      case "tool": return `- \`${event.agent}\` ${event.tool}: ${event.detail}`;
      case "info": return `> ${event.text}\n`;
      case "error": return `> **Fehler:** ${event.text}\n`;
      case "ask": return `> **Frage an dich:** ${event.question}\n`;
      case "finished": return `\n## Ergebnis\n\n${event.summary}\n`;
      default: return null;
    }
  };
  return bus.onEvent((event) => {
    const text = line(event);
    if (text !== null) appendFileSync(file, `${text}\n`);
  });
}

/** Follow-up tasks get a round prefix, so their ids never clash with earlier ones. */
function prefixTasks(plan: Plan, round: number): Plan {
  const prefix = (id: string) => `r${round}-${id}`;
  return { ...plan, tasks: plan.tasks.map((t) => ({ ...t, id: prefix(t.id), dependsOn: t.dependsOn.map(prefix) })) };
}

export async function runHivemind({ request, resume, cwd, config, planOnly, signal }: RunOptions): Promise<void> {
  const isGit = isGitRepo(cwd);
  const repo = isGit ? git(cwd, "rev-parse", "--show-toplevel") : cwd;
  const id = resume?.id ?? newRunId();
  const runDir = join(runsRoot(repo), id);
  mkdirSync(runDir, { recursive: true });

  const store = new RunStore(
    runDir,
    resume
      ? { ...resume, status: "running" }
      : { id, request: request!, cwd, createdAt: new Date().toISOString(), status: "running", phase: "Start", costUsd: 0, plans: [], doneTasks: [] },
  );
  store.update({});
  const stopRecording = recordTranscript(runDir);
  const stopTracking = bus.onEvent((e) => {
    if (e.type === "cost") store.update({ costUsd: store.state.costUsd + e.usd });
    if (e.type === "phase") store.update({ phase: e.phase });
  });
  const cost = () => `Kosten (geschätzt): $${store.state.costUsd.toFixed(2)}`;
  let workspace: Workspace | undefined;

  try {
    if (resume) bus.emitEvent({ type: "info", text: `Setze Lauf ${id} fort: ${resume.request}` });

    // Worktrees need a commit to start from. Better to find out now than after the planning.
    if (isGit && !planOnly && !hasCommits(repo)) {
      const answer = await bus.ask("Dein Repo hat noch keinen Commit, ohne den können die Coder nicht starten.", ["leeren Start-Commit anlegen", "abbrechen"]);
      if (answer !== "leeren Start-Commit anlegen") throw new CancelledByUser();
      git(repo, "commit", "--allow-empty", "-m", "Start");
      bus.emitEvent({ type: "info", text: "Leerer Start-Commit angelegt." });
    }

    if (!store.state.brief) {
      const { brief, size } = await optimizePrompt(store.state.request, cwd, config, signal);
      store.update({ brief, size });
    }
    const brief = store.state.brief!;

    if (store.state.plans.length === 0) {
      const plan = await planTeam(brief, store.state.size ?? "M", cwd, config, signal);
      store.update({ plans: [plan] });
      writeFileSync(join(runDir, "plan.json"), JSON.stringify({ brief, ...plan }, null, 2));
    }

    if (planOnly || !isGit) {
      const why = isGit ? "" : "\n\nDas Coder-Team braucht ein Git-Repo (jeder Coder arbeitet in seinem eigenen Worktree). Führ `git init` aus und committe einmal, dann geht's mit `hivemind --resume` weiter.";
      store.update({ status: isGit ? "done" : "aborted" });
      bus.emitEvent({ type: "finished", summary: `${formatPlan(store.state.plans[0]!)}\n\nPlan gespeichert in ${join(runDir, "plan.json")}.${why}\n\n${cost()}` });
      return;
    }

    if (hasUncommittedChanges(repo)) {
      bus.emitEvent({ type: "info", text: "Achtung: Du hast uncommittete Änderungen. Die Coder starten vom letzten Commit und sehen sie nicht." });
    }
    workspace = new Workspace(repo, id, runDir);
    workspace.open();
    store.update({ branch: workspace.branch });
    const resultCwd = join(workspace.integration, relative(repo, cwd));

    let ending = "";
    for (;;) {
      const plan = store.state.plans.at(-1)!;
      const result = await codingTeam({
        brief,
        plan,
        workspace,
        cwd,
        config,
        signal,
        alreadyDone: store.state.doneTasks,
        onTaskDone: (taskId) => store.update({ doneTasks: [...store.state.doneTasks, taskId] }),
      });
      if (result.failed.length) bus.emitEvent({ type: "error", text: `Nicht umgesetzt: ${result.failed.join(", ")}` });

      const next = await bus.ask(`Alles liegt auf ${workspace.branch}. Wie geht's weiter?`, ["fertig", "nachbessern", "in meinen Branch mergen"]);
      if (next === "nachbessern") {
        const feedback = await bus.ask("Was soll das Team nachbessern?");
        const followUp = await followUpPlan(brief, plan, feedback, resultCwd, config, signal);
        store.update({ plans: [...store.state.plans, prefixTasks(followUp, store.state.plans.length + 1)] });
        continue;
      }
      if (next === "in meinen Branch mergen") {
        ending = workspace.mergeIntoCheckout().message;
      } else {
        ending = `Dein Branch ist unverändert.\nAnschauen: git diff HEAD...${workspace.branch}\nÜbernehmen: git merge ${workspace.branch}`;
      }
      break;
    }

    store.update({ status: "done" });
    bus.emitEvent({ type: "finished", summary: `${ending}\n\nProtokoll: ${join(runDir, "transcript.md")}\n${cost()}` });
  } catch (error) {
    const aborted = signal.aborted || error instanceof CancelledByUser;
    store.update({ status: aborted ? "aborted" : "failed" });
    if (!aborted) bus.emitEvent({ type: "error", text: errorText(error) });
    bus.emitEvent({
      type: "finished",
      summary: `${aborted ? "Abgebrochen" : "Fehlgeschlagen"}. Weitermachen mit: hivemind --resume ${id}\nProtokoll: ${join(runDir, "transcript.md")}\n${cost()}`,
    });
  } finally {
    workspace?.cleanup();
    stopTracking();
    stopRecording();
  }
}
