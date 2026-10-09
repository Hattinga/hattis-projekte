import { join, relative } from "node:path";
import { z } from "zod";
import { errorText, runAgent } from "../agent.js";
import { bus } from "../bus.js";
import { modelFor, type Config } from "../config.js";
import { Workspace } from "../git.js";
import { TEAM_TOOLS_HINT, TeamBoard, teamTools } from "../team.js";
import { formatPlan, type Plan, type Task } from "./plan.js";
import { schedule } from "./schedule.js";

const Review = z.object({
  approved: z.boolean(),
  feedback: z.string().describe("Was der Coder ändern muss. Leer, wenn approved."),
});

export interface CodingResult {
  report: string;
  failed: string[];
}

export interface CodingOptions {
  brief: string;
  plan: Plan;
  workspace: Workspace;
  /** The folder hivemind was started in; agents start in the same subfolder of their worktree. */
  cwd: string;
  config: Config;
  signal: AbortSignal;
  /** Tasks finished in an earlier, interrupted run. */
  alreadyDone?: string[];
  onTaskDone?: (taskId: string) => void;
}

/**
 * Runs every task of the plan in its own git worktree, up to config.coders at a time.
 * A task starts once the tasks it depends on are merged. Each task goes
 * coder → reviewer (→ coder → reviewer …) → merge into hivemind/<runId>.
 * Coders talk to each other on a shared board and can ask the architect.
 * At the end the tester checks the merged result.
 */
export async function codingTeam(options: CodingOptions): Promise<CodingResult> {
  const { brief, plan, workspace, cwd, config, signal } = options;
  bus.emitEvent({ type: "phase", phase: "Umsetzung" });
  const subdir = relative(workspace.repo, cwd);
  const integrationCwd = join(workspace.integration, subdir);
  const context = `Gesamtauftrag:\n\n${brief}\n\nAbgestimmter Plan:\n\n${formatPlan(plan)}`;

  const board = new TeamBoard();
  const questionBudget = { left: config.architectQuestions };
  const architect = config.roles.architect ?? config.roles.moderator!;
  const askArchitect = async (from: string, question: string) => {
    const { text } = await runAgent({
      name: architect.title,
      team: "Umsetzung",
      role: architect,
      model: modelFor(architect, "hard", config),
      config,
      prompt: `${context}\n\nDas Team setzt den Plan gerade um. Der aktuell gemergte Stand liegt in deinem Arbeitsverzeichnis.\nTeam-Board bisher:\n${board.messages.map((m) => `- ${m.from}: ${m.text}`).join("\n") || "(leer)"}\n\n${from} fragt dich:\n\n${question}\n\nAntworte kurz und entscheide klar.`,
      cwd: integrationCwd,
      access: "read",
      signal,
    });
    board.post(architect.title, `@${from} ${text}`);
    return text;
  };

  let mergeQueue = Promise.resolve();
  const merge = (task: Task, branch: string) => {
    const step = mergeQueue.then(() => mergeTask(task, branch));
    mergeQueue = step.catch(() => {});
    return step;
  };

  const mergeTask = async (task: Task, branch: string) => {
    if (!workspace.merge(branch, `hivemind: ${task.title}`)) {
      bus.emitEvent({ type: "info", text: `Merge-Konflikt bei [${task.id}], der Integrator übernimmt.` });
      await runAgent({
        name: "Integrator",
        team: "Umsetzung",
        role: config.roles.integrator!,
        model: modelFor(config.roles.integrator!, "hard", config),
        config,
        prompt: `${context}\n\nBeim Mergen von Branch ${branch} (Task "${task.title}") in den aktuellen Branch gab es Konflikte. Löse sie und schließe den Merge ab.\n\nTask:\n${task.description}`,
        cwd: integrationCwd,
        access: "write",
        signal,
      });
      if (workspace.mergeInProgress()) {
        workspace.abortMerge();
        throw new Error(`Merge-Konflikt bei [${task.id}] konnte nicht gelöst werden.`);
      }
    }
    board.post("hivemind", `[${task.id}] ${task.title} ist gemergt. Wer die Änderungen braucht: git merge ${workspace.branch}`);
  };

  const work = async (task: Task, slot: number) => {
    const coderName = `Coder ${slot}`;
    const { dir, branch, base } = workspace.taskWorktree(task.id);
    const taskCwd = join(dir, subdir);
    const tools = () => teamTools(board, coderName, askArchitect, questionBudget);
    const coderModel = modelFor(config.roles.coder!, task.difficulty, config);
    // The reviewer is never weaker than Sonnet: an easy task can still hide a bug.
    const reviewerModel = modelFor(config.roles.reviewer!, task.difficulty === "hard" ? "hard" : "normal", config);
    try {
      bus.emitEvent({ type: "info", text: `${coderName} übernimmt [${task.id}] ${task.title}` });
      const news = board.catchUp(coderName);
      let coder = await runAgent({
        name: coderName,
        team: "Umsetzung",
        role: config.roles.coder!,
        model: coderModel,
        config,
        prompt: `${context}\n\nDeine Task [${task.id}] ${task.title}:\n\n${task.description}\n\nVoraussichtlich betroffene Dateien: ${task.files.join(", ") || "(offen)"}\n\nAndere Coder arbeiten parallel an anderen Tasks. Bleib bei deiner.\n\n${TEAM_TOOLS_HINT}${news ? `\n\nBisher auf dem Team-Board:\n${news}` : ""}`,
        cwd: taskCwd,
        access: "write",
        teamTools: tools(),
        signal,
      });

      for (let loop = 0; ; loop++) {
        workspace.commitLeftovers(dir, `hivemind: ${task.title}`);
        const review = await runAgent({
          name: `Reviewer ${slot}`,
          team: "Umsetzung",
          role: config.roles.reviewer!,
          model: reviewerModel,
          config,
          prompt: `Task [${task.id}] ${task.title}:\n\n${task.description}\n\nZusammenfassung des Coders:\n${coder.text}\n\nDie Änderungen siehst du mit: git diff ${base}..HEAD\n\nPrüfe sie.`,
          cwd: taskCwd,
          access: "review",
          schema: Review,
          signal,
        });
        if (review.data.approved) {
          bus.emitEvent({ type: "info", text: `Reviewer ${slot} gibt [${task.id}] frei.` });
          break;
        }
        if (loop >= config.maxReviewLoops) {
          bus.emitEvent({ type: "info", text: `[${task.id}] nach ${loop + 1} Reviews nicht freigegeben, wird trotzdem übernommen.` });
          break;
        }
        bus.emitEvent({ type: "say", agent: `Reviewer ${slot}`, text: `Zurück an ${coderName}:\n\n${review.data.feedback}` });
        coder = await runAgent({
          name: coderName,
          team: "Umsetzung",
          role: config.roles.coder!,
          model: coderModel,
          config,
          prompt: `Der Reviewer hat deine Änderungen zurückgeschickt:\n\n${review.data.feedback}\n\nBehebe das und committe.`,
          cwd: taskCwd,
          access: "write",
          resume: coder.sessionId,
          teamTools: tools(),
          signal,
        });
      }

      await merge(task, branch);
      options.onTaskDone?.(task.id);
    } finally {
      workspace.removeTaskWorktree(dir, branch);
    }
  };

  const result = await schedule(plan.tasks, config.coders, work, {
    alreadyDone: options.alreadyDone,
    signal,
    onFail: (task, error) => bus.emitEvent({ type: "error", text: `[${task.id}] fehlgeschlagen: ${errorText(error)}` }),
  });
  for (const id of result.skipped) {
    bus.emitEvent({ type: "error", text: `[${id}] übersprungen, weil eine Abhängigkeit fehlgeschlagen ist.` });
  }
  const failed = [...result.failed, ...result.skipped];
  if (signal.aborted) throw new Error("Abgebrochen.");

  bus.emitEvent({ type: "phase", phase: "Test" });
  const tester = await runAgent({
    name: "Testerin",
    team: "Umsetzung",
    role: config.roles.tester!,
    model: modelFor(config.roles.tester!, "normal", config),
    config,
    prompt: `${context}\n\nAlle Tasks sind umgesetzt und gemergt${failed.length ? `, außer: ${failed.join(", ")}` : ""}. Prüfe das Ergebnis.`,
    cwd: integrationCwd,
    access: "write",
    signal,
  });
  workspace.commitLeftovers(workspace.integration, "hivemind: Korrekturen der Testerin");

  return { report: tester.text, failed };
}
