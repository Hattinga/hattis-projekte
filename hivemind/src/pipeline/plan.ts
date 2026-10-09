import { z } from "zod";
import { runAgent } from "../agent.js";
import { bus } from "../bus.js";
import { modelFor, type Config, type Tier } from "../config.js";
import type { Size } from "./optimize.js";

export const Plan = z.object({
  summary: z.string().describe("Was gebaut wird und wie, in wenigen Sätzen."),
  decisions: z.array(z.string()).describe("Entscheidungen, die das Team getroffen hat, inkl. strittiger Punkte."),
  tasks: z.array(
    z.object({
      id: z.string().describe("Kurze ID ohne Leerzeichen, z.B. t1. Bei Nachbesserungen neue IDs vergeben."),
      title: z.string(),
      description: z.string().describe("Vollständige Anweisung für einen Coder, der die Diskussion nicht kennt."),
      files: z.array(z.string()).describe("Dateien, die voraussichtlich angelegt oder geändert werden."),
      dependsOn: z.array(z.string()).describe("IDs von Tasks aus diesem Plan, die vorher fertig sein müssen."),
      difficulty: z.enum(["easy", "normal", "hard"]).describe("Wie schwer die Task ist; danach wird das Modell des Coders gewählt."),
    }),
  ),
});
export type Plan = z.infer<typeof Plan>;
export type Task = Plan["tasks"][number];

const Statement = z.object({
  message: z.string().describe("Dein Beitrag zur Diskussion (Markdown)."),
  agrees: z.boolean().describe("true, wenn du mit dem aktuellen Stand einverstanden bist und nichts Wesentliches mehr fehlt."),
});

/** You chose "abbrechen". Not a failure, so nothing to report. */
export class CancelledByUser extends Error {
  constructor() {
    super("Von dir abgebrochen.");
  }
}

export function formatPlan(plan: Plan): string {
  const tasks = plan.tasks.map((t) => {
    const deps = t.dependsOn.length ? ` (nach ${t.dependsOn.join(", ")})` : "";
    const level = { easy: "leicht", normal: "normal", hard: "schwer" }[t.difficulty];
    const files = t.files.length ? `\n  ${t.files.join(", ")}` : "";
    return `- **[${t.id}] ${t.title}**${deps} · ${level}${files}`;
  });
  const decisions = plan.decisions.map((d) => `- ${d}`);
  return `${plan.summary}\n\n## Entscheidungen\n${decisions.join("\n")}\n\n## Tasks\n${tasks.join("\n")}`;
}

/** Who sits at the table and for how many rounds, depending on the size of the request. */
export function planningTeam(size: Size, config: Config): { planners: string[]; rounds: number } {
  if (!config.triage || size === "L") return { planners: config.planners, rounds: config.discussionRounds };
  if (size === "M") return { planners: config.planners, rounds: Math.min(2, config.discussionRounds) };
  return { planners: config.planners.slice(0, 2), rounds: 1 };
}

/**
 * The planners discuss in rounds: first everyone proposes independently and in parallel,
 * then they answer each other one after another, until everyone agrees or the rounds run out.
 * The moderator turns the discussion into a plan, which the human approves or sends back.
 */
export async function planTeam(brief: string, size: Size, cwd: string, config: Config, signal: AbortSignal): Promise<Plan> {
  bus.emitEvent({ type: "phase", phase: "Planung" });
  const { planners, rounds } = planningTeam(size, config);
  // Only large requests need the strongest model in the discussion; the moderator decides on Opus anyway.
  const tier: Tier = size === "L" ? "hard" : "normal";
  const names = planners.map((key) => config.roles[key]!.title).join(", ");
  bus.emitEvent({ type: "info", text: `Größe ${size}: ${names} planen, höchstens ${rounds} ${rounds === 1 ? "Runde" : "Runden"}.` });

  const discussion: string[] = [];
  const transcript = () => discussion.join("\n\n---\n\n");
  const runPlanner = (key: string, prompt: string) => {
    const role = config.roles[key]!;
    return runAgent({ name: role.title, team: "Planung", role, model: modelFor(role, tier, config), config, prompt, cwd, access: "read", signal });
  };

  const opening = await Promise.all(
    planners.map(async (key) => {
      const { text } = await runPlanner(
        key,
        `Auftrag:\n\n${brief}\n\nDas Planungs-Team (${names}) bespricht, wie dieser Auftrag umgesetzt wird. Schau dir den relevanten Code an und gib aus deiner Rolle heraus deinen Vorschlag bzw. deine Einschätzung ab. Höchstens etwa 250 Wörter: nur was für die Entscheidung zählt, keine Wiederholung des Auftrags.`,
      );
      return `**${config.roles[key]!.title}:**\n${text}`;
    }),
  );
  discussion.push(...opening);

  for (let round = 2; round <= rounds; round++) {
    bus.emitEvent({ type: "info", text: `Diskussionsrunde ${round} von höchstens ${rounds}` });
    let everyoneAgrees = true;
    for (const key of planners) {
      const role = config.roles[key]!;
      const { data, spoke } = await runAgent({
        name: role.title,
        team: "Planung",
        role,
        model: modelFor(role, tier, config),
        config,
        prompt: `Auftrag:\n\n${brief}\n\nBisherige Diskussion:\n\n${transcript()}\n\nReagiere auf die anderen: Wo stimmst du zu, wo nicht und warum, was fehlt noch? Wiederhole nichts, was schon gesagt wurde. Höchstens etwa 120 Wörter. Wenn du einverstanden bist und nichts Wesentliches fehlt, reicht ein Satz.`,
        cwd,
        access: "read",
        schema: Statement,
        signal,
      });
      if (!spoke) bus.emitEvent({ type: "say", agent: role.title, text: data.message });
      if (data.agrees) bus.emitEvent({ type: "info", text: `${role.title} ist einverstanden.` });
      discussion.push(`**${role.title}:**\n${data.message}`);
      everyoneAgrees &&= data.agrees;
    }
    if (everyoneAgrees) {
      bus.emitEvent({ type: "info", text: "Alle sind einverstanden, die Diskussion ist beendet." });
      break;
    }
  }

  return moderate(
    `Auftrag:\n\n${brief}\n\nDiskussion des Planungs-Teams:\n\n${transcript()}\n\nEntscheide offene Punkte und schreib den finalen Plan.`,
    cwd,
    config,
    signal,
  );
}

/** Plan for a round of changes the human asked for after seeing the result. `cwd` holds the current result. */
export function followUpPlan(brief: string, previous: Plan, feedback: string, cwd: string, config: Config, signal: AbortSignal): Promise<Plan> {
  bus.emitEvent({ type: "phase", phase: "Nachbesserung planen" });
  return moderate(
    `Ursprünglicher Auftrag:

${brief}

Das Team hat diesen Plan bereits umgesetzt:

${formatPlan(previous)}

Der Kunde hat das Ergebnis angeschaut und möchte Folgendes ändern:

${feedback}

Schau dir den aktuellen Code an und schreib einen Plan nur für diese Nachbesserungen, mit neuen Task-IDs.`,
    cwd,
    config,
    signal,
  );
}

/** The moderator writes a plan; the human approves it or sends it back with feedback. */
async function moderate(prompt: string, cwd: string, config: Config, signal: AbortSignal): Promise<Plan> {
  const moderator = config.roles.moderator!;
  let resume: string | undefined;
  for (;;) {
    const result = await runAgent({ name: moderator.title, team: "Planung", role: moderator, model: modelFor(moderator, "hard", config), config, prompt, cwd, access: "read", schema: Plan, resume, signal });
    resume = result.sessionId;
    bus.emitEvent({ type: "say", agent: moderator.title, text: formatPlan(result.data) });

    const answer = await bus.ask("Plan freigeben?", ["freigeben", "ändern", "abbrechen"]);
    if (answer === "freigeben") return result.data;
    if (answer === "abbrechen") throw new CancelledByUser();
    const feedback = await bus.ask("Was soll am Plan anders werden?");
    prompt = `Der Kunde möchte den Plan geändert haben:

${feedback}

Überarbeite den Plan entsprechend.`;
  }
}
