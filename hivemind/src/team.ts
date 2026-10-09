import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import type { TeamTools } from "./agent.js";
import { bus } from "./bus.js";

export interface BoardMessage {
  from: string;
  text: string;
}

/** The coding team's shared chat. Coders post what others should know and read what others posted. */
export class TeamBoard {
  readonly messages: BoardMessage[] = [];
  private readCursor = new Map<string, number>();

  post(from: string, text: string) {
    this.messages.push({ from, text });
    bus.emitEvent({ type: "chat", from, text });
  }

  /** Messages from others that `agent` has not read yet. Marks them as read. */
  unread(agent: string): BoardMessage[] {
    const start = this.readCursor.get(agent) ?? 0;
    this.readCursor.set(agent, this.messages.length);
    return this.messages.slice(start).filter((m) => m.from !== agent);
  }

  /** Everything so far, for an agent that just joins. Marks it as read. */
  catchUp(agent: string): string {
    const messages = this.unread(agent);
    return messages.length ? messages.map(format).join("\n") : "";
  }
}

const format = (m: BoardMessage) => `- ${m.from}: ${m.text}`;

export const TEAM_TOOLS_HINT = `Du arbeitest nicht allein. Dafür hast du Team-Tools:
- mcp__team__post: Schreib eine kurze Nachricht ans Team-Board, wenn andere etwas wissen müssen (z.B. du änderst eine gemeinsame Schnittstelle, legst eine Datei an, die andere auch brauchen, oder findest einen Fehler außerhalb deiner Task).
- mcp__team__read: Lies neue Nachrichten der anderen. Mach das mindestens einmal, bevor du committest.
- mcp__team__ask_architect: Frag die Architektin, wenn der Plan an einer Stelle unklar ist oder nicht zum Code passt. Nicht für Kleinigkeiten, die du selbst entscheiden kannst.`;

/**
 * One MCP server per agent (an MCP server instance serves one session at a time).
 * `askArchitect` answers design questions; `questionBudget` is shared across the whole team.
 */
export function teamTools(
  board: TeamBoard,
  agent: string,
  askArchitect: (from: string, question: string) => Promise<string>,
  questionBudget: { left: number },
): TeamTools {
  const server = createSdkMcpServer({
    name: "team",
    tools: [
      tool("post", "Schreibt eine Nachricht ans Team-Board, das alle Coder sehen.", { message: z.string() }, async ({ message }) => {
        board.post(agent, message);
        return { content: [{ type: "text", text: "Gesendet." }] };
      }),
      tool("read", "Liest neue Nachrichten der anderen Teammitglieder vom Team-Board.", {}, async () => {
        const messages = board.unread(agent);
        const text = messages.length ? messages.map(format).join("\n") : "Keine neuen Nachrichten.";
        return { content: [{ type: "text", text }] };
      }),
      tool(
        "ask_architect",
        "Stellt der Architektin eine Frage zum Plan oder Design und wartet auf ihre Antwort.",
        { question: z.string() },
        async ({ question }) => {
          if (questionBudget.left <= 0) {
            return { content: [{ type: "text", text: "Die Architektin ist gerade nicht erreichbar. Entscheide selbst und schreib deine Entscheidung ans Team-Board." }] };
          }
          questionBudget.left--;
          bus.emitEvent({ type: "chat", from: agent, text: `@Architektin ${question}` });
          const answer = await askArchitect(agent, question);
          return { content: [{ type: "text", text: answer }] };
        },
      ),
    ],
  });
  return { server, names: ["mcp__team__post", "mcp__team__read", "mcp__team__ask_architect"] };
}
