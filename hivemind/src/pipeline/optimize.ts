import { z } from "zod";
import { runAgent } from "../agent.js";
import { bus } from "../bus.js";
import { modelFor, type Config } from "../config.js";

export const Size = z.enum(["S", "M", "L"]);
export type Size = z.infer<typeof Size>;

const Brief = z.object({
  brief: z.string().describe("Der optimierte, vollständige Auftrag für das Planungs-Team (Markdown)."),
  size: Size.describe("S, M oder L, siehe Anweisungen."),
  questions: z.array(z.string()).describe("Rückfragen an den Kunden. Leer, wenn alles klar ist."),
});

export interface Briefing {
  brief: string;
  size: Size;
}

/** Turns the raw request into a precise brief, asking the human when something essential is unclear. */
export async function optimizePrompt(request: string, cwd: string, config: Config, signal: AbortSignal): Promise<Briefing> {
  bus.emitEvent({ type: "phase", phase: "Prompt-Optimierung" });
  let prompt = `Anfrage des Kunden:\n\n${request}`;
  let resume: string | undefined;

  for (let attempt = 0; ; attempt++) {
    const result = await runAgent({
      name: "Optimizer",
      team: "Empfang",
      role: config.roles.optimizer!,
      model: modelFor(config.roles.optimizer!, "normal", config),
      config,
      prompt,
      cwd,
      access: "read",
      schema: Brief,
      resume,
      signal,
    });
    const { data } = result;
    resume = result.sessionId;

    if (data.questions.length === 0 || attempt >= 1) {
      bus.emitEvent({ type: "say", agent: "Optimizer", text: `${data.brief}\n\nGröße: ${data.size}` });
      return { brief: data.brief, size: data.size };
    }

    const answers: string[] = [];
    for (const question of data.questions) {
      answers.push(`F: ${question}\nA: ${await bus.ask(question)}`);
    }
    prompt = `Antworten des Kunden auf deine Rückfragen:\n\n${answers.join("\n\n")}\n\nSchreib jetzt den finalen Auftrag. Keine weiteren Rückfragen.`;
  }
}
