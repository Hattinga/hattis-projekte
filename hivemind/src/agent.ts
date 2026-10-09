import { query, type CanUseTool, type McpServerConfig, type Options } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { bus } from "./bus.js";
import type { Config, Role } from "./config.js";

/** read: look at the code only. review: also run commands. write: full Claude Code toolset. */
export type Access = "read" | "review" | "write";

/** In-process tools an agent gets on top of its access level, e.g. the team chat. */
export interface TeamTools {
  server: McpServerConfig;
  /** Full tool names (mcp__<server>__<tool>), so they can be allowed explicitly. */
  names: string[];
}

export interface AgentRun<T> {
  /** Unique name in the UI, e.g. "Coder 2". */
  name: string;
  team: string;
  role: Role;
  config: Config;
  prompt: string;
  cwd: string;
  access: Access;
  /** Overrides the role's and config's model, e.g. the one routing picked for this job. */
  model?: string;
  /** When set, the agent must answer with JSON matching this schema. */
  schema?: z.ZodType<T>;
  /** Session id of an earlier run of this agent, so it remembers what it did. */
  resume?: string;
  teamTools?: TeamTools;
  signal?: AbortSignal;
}

export interface AgentResult<T> {
  text: string;
  data: T;
  costUsd: number;
  sessionId: string;
  /** Whether the agent already said something visible, so callers don't repeat it. */
  spoke: boolean;
}

const READ_TOOLS = ["Read", "Glob", "Grep"];
// Tools that would block on a human or switch the session's mode; hivemind handles those itself.
const BLOCKED_TOOLS = ["AskUserQuestion", "EnterPlanMode", "ExitPlanMode", "EnterWorktree", "ExitWorktree"];

const READ_ONLY_PREAMBLE = `Du bist ein Agent in "hivemind", einer Software-Firma aus KI-Agents, die gemeinsam für einen Kunden an seinem Projekt arbeiten.
Das Projekt liegt in deinem Arbeitsverzeichnis. Du kannst es mit Read, Glob und Grep lesen, aber nichts ändern.
Lies gezielt nur, was du für deine Aufgabe brauchst. Antworte auf Deutsch, knapp und konkret, in Markdown.`;

/** Last reported total per session; a resumed session reports its total including earlier runs. */
const sessionCosts = new Map<string, number>();

/** Tool names you chose "immer erlauben" for, shared by every agent of this run. */
const alwaysAllowed = new Set<string>();

/** Claude Code rejects the "$schema" meta key that zod adds. */
function jsonSchema(schema: z.ZodType): Record<string, unknown> {
  const { $schema: _, ...rest } = z.toJSONSchema(schema);
  return rest;
}

export function describeTool(name: string, input: Record<string, unknown>): string {
  const value = input.command ?? input.file_path ?? input.pattern ?? input.path ?? input.url ?? input.description ?? input.message ?? input.question;
  return typeof value === "string" ? value.split("\n")[0]!.slice(0, 160) : "";
}

function permissionPrompt(agent: string, trusted: string[]): CanUseTool {
  return async (toolName, input, { decisionReason }) => {
    if (trusted.includes(toolName) || alwaysAllowed.has(toolName)) return { behavior: "allow", updatedInput: input };
    const reason = decisionReason ? `\n(${decisionReason})` : "";
    const answer = await bus.ask(
      `${agent} möchte ${toolName} ausführen:\n${describeTool(toolName, input)}${reason}`,
      ["ja", "nein", `immer (${toolName})`],
    );
    if (answer.startsWith("immer")) alwaysAllowed.add(toolName);
    if (answer === "ja" || answer.startsWith("immer")) return { behavior: "allow", updatedInput: input };
    return { behavior: "deny", message: "Der Kunde hat das abgelehnt. Such einen anderen Weg oder lass es weg." };
  };
}

function permissions(agent: string, config: Config, trusted: string[]): Partial<Options> {
  if (config.permissionMode === "bypassPermissions") {
    // Every tool call runs without asking, so no agent ever waits on you.
    return { permissionMode: "bypassPermissions", allowDangerouslySkipPermissions: true };
  }
  return { permissionMode: config.permissionMode, canUseTool: permissionPrompt(agent, trusted) };
}

function accessOptions(run: AgentRun<unknown>): Partial<Options> {
  const { access, name, config, role, teamTools } = run;
  const extra = teamTools?.names ?? [];
  const trusted = [...READ_TOOLS, ...extra];
  switch (access) {
    case "read":
      // Nothing outside these tools exists, and nothing ever prompts.
      return {
        tools: READ_TOOLS,
        allowedTools: trusted,
        permissionMode: "dontAsk",
        systemPrompt: `${READ_ONLY_PREAMBLE}\n\n${role.persona}`,
      };
    case "review":
      return {
        tools: [...READ_TOOLS, "Bash"],
        systemPrompt: `${READ_ONLY_PREAMBLE}\nZusätzlich darfst du Befehle zum Lesen, Bauen und Testen ausführen (Bash), aber keine Dateien ändern.\n\n${role.persona}`,
        ...permissions(name, config, trusted),
      };
    case "write":
      return {
        tools: { type: "preset", preset: "claude_code" },
        disallowedTools: BLOCKED_TOOLS,
        systemPrompt: { type: "preset", preset: "claude_code", append: role.persona },
        ...permissions(name, config, trusted),
      };
  }
}

/**
 * What every agent of the current run should know, set by the pipeline.
 * One run per process, so module state is fine here.
 */
export const shared = {
  /** Team memory and project overview, put in front of every fresh agent's prompt. */
  background: "",
  /** What you wrote to the team while the run was going. */
  notes: [] as string[],
  budgetUsd: Number.POSITIVE_INFINITY,
  spentUsd: 0,
};

bus.onEvent((event) => {
  if (event.type === "cost") shared.spentUsd += event.usd;
  if (event.type === "note") shared.notes.push(event.text);
});

/** The run's budget is used up. Not retried; the run stops and can be resumed with a higher budget. */
export class BudgetExceeded extends Error {
  constructor() {
    super(`Budget von $${shared.budgetUsd.toFixed(2)} ist aufgebraucht.`);
  }
}

/** Your plan's usage limit is reached. `resetsAt` is when it frees up again (ms), if known. */
class RateLimited extends Error {
  constructor(readonly resetsAt: number | undefined, readonly sessionId: string) {
    super("Nutzungslimit erreicht.");
  }
}

/** The agent ran, but ended without a usable result. Retrying the same prompt rarely helps. */
class AgentFailed extends Error {}

export function errorText(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).split("\n")[0]!.slice(0, 200);
}

type Implementation = (run: AgentRun<unknown>) => Promise<AgentResult<unknown>>;
let implementation: Implementation = runAgentOnce;

/** Swaps the real Claude Code agent for a fake one. Only for tests. */
export function setAgentImplementation(fake: Implementation | null) {
  implementation = fake ?? runAgentOnce;
}

function withContext<T>(run: AgentRun<T>): AgentRun<T> {
  const parts: string[] = [];
  // A resumed session already has the background from its first prompt.
  if (shared.background && !run.resume) parts.push(shared.background);
  if (shared.notes.length) parts.push(`Nachrichten des Kunden während des Laufs (haben Vorrang):\n${shared.notes.map((n) => `- ${n}`).join("\n")}`);
  return parts.length ? { ...run, prompt: `${parts.join("\n\n")}\n\n---\n\n${run.prompt}` } : run;
}

/**
 * Runs one agent. Waits out usage limits and continues where the agent stopped,
 * retries once if it crashes, and refuses to start once the budget is used up.
 */
export async function runAgent<T = undefined>(run: AgentRun<T>): Promise<AgentResult<T>> {
  let current = run;
  let crashed = false;
  for (;;) {
    if (shared.spentUsd >= shared.budgetUsd) throw new BudgetExceeded();
    try {
      return (await implementation(withContext(current) as AgentRun<unknown>)) as AgentResult<T>;
    } catch (error) {
      if (run.signal?.aborted || error instanceof AgentFailed || error instanceof BudgetExceeded) throw error;
      if (error instanceof RateLimited) {
        await waitForLimit(run.name, error.resetsAt, run.signal);
        current = error.sessionId
          ? { ...run, resume: error.sessionId, prompt: "Du wurdest durch ein Nutzungslimit unterbrochen. Mach genau dort weiter, wo du aufgehört hast." }
          : run;
        continue;
      }
      if (crashed) throw error;
      crashed = true;
      bus.emitEvent({ type: "info", text: `${run.name} ist abgestürzt (${errorText(error)}), neuer Versuch …` });
    }
  }
}

/** Sleeps until the usage limit resets (plus a minute of slack), or 15 minutes if the reset time is unknown. */
async function waitForLimit(agent: string, resetsAt: number | undefined, signal?: AbortSignal) {
  const until = resetsAt && resetsAt > Date.now() ? resetsAt + 60_000 : Date.now() + 15 * 60_000;
  bus.emitEvent({ type: "limit", agent, until });
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(done, until - Date.now());
    function done() {
      signal?.removeEventListener("abort", stop);
      resolve();
    }
    function stop() {
      clearTimeout(timer);
      reject(new Error("Abgebrochen."));
    }
    signal?.addEventListener("abort", stop, { once: true });
  });
  bus.emitEvent({ type: "info", text: `Limit wieder frei, ${agent} macht weiter.` });
}

/** Limit warnings already shown, so each appears once per run. */
const warned = new Set<string>();

const LIMIT_NAMES: Record<string, string> = {
  five_hour: "5-Stunden-Limits",
  seven_day: "Wochenlimits",
  seven_day_opus: "Opus-Wochenlimits",
  seven_day_sonnet: "Sonnet-Wochenlimits",
};

async function runAgentOnce<T>(run: AgentRun<T>): Promise<AgentResult<T>> {
  const { name, team, role, config } = run;
  const abortController = new AbortController();
  const onAbort = () => abortController.abort();
  run.signal?.addEventListener("abort", onAbort, { once: true });

  const model = run.model ?? role.model ?? config.model;
  bus.emitEvent({ type: "agent", agent: name, team, status: "thinking", model });
  const texts: string[] = [];
  let structured: unknown;
  let costUsd = 0;
  let sessionId = "";
  let spoke = false;
  let limitResetsAt: number | undefined;
  let limited = false;
  const budgetLeft = shared.budgetUsd - shared.spentUsd;

  try {
    const messages = query({
      prompt: run.prompt,
      options: {
        cwd: run.cwd,
        model,
        effort: role.effort,
        outputFormat: run.schema ? { type: "json_schema", schema: jsonSchema(run.schema) } : undefined,
        resume: run.resume,
        abortController,
        includePartialMessages: true,
        maxBudgetUsd: Number.isFinite(budgetLeft) ? Math.max(0.01, budgetLeft) : undefined,
        // Isolated from your own Claude Code setup: no MCP servers, plugins, skills or hooks from
        // ~/.claude. Those cost tens of thousands of tokens per turn and no agent here needs them.
        // The project's own settings and CLAUDE.md still apply.
        settingSources: ["project"],
        strictMcpConfig: true,
        mcpServers: run.teamTools ? { team: run.teamTools.server } : {},
        skills: [],
        env: { ...process.env, CLAUDE_AGENT_SDK_CLIENT_APP: "hivemind/0.3.0" },
        ...accessOptions(run as AgentRun<unknown>),
      },
    });

    for await (const message of messages) {
      if (message.type === "system" && message.subtype === "init") {
        sessionId = message.session_id;
      } else if (message.type === "rate_limit_event") {
        const info = message.rate_limit_info;
        if (info.status === "rejected") {
          limited = true;
          if (info.resetsAt) limitResetsAt = info.resetsAt < 1e12 ? info.resetsAt * 1000 : info.resetsAt;
        } else if (info.status === "allowed_warning" && info.rateLimitType && !warned.has(info.rateLimitType)) {
          warned.add(info.rateLimitType);
          const used = info.utilization === undefined ? "" : `${Math.round(info.utilization <= 1 ? info.utilization * 100 : info.utilization)} % `;
          bus.emitEvent({ type: "info", text: `Achtung: ${used}deines ${LIMIT_NAMES[info.rateLimitType] ?? "Limits"} sind verbraucht.` });
        }
      } else if (message.type === "stream_event" && message.parent_tool_use_id === null) {
        const event = message.event;
        if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
          bus.emitEvent({ type: "delta", agent: name, text: event.delta.text });
        }
      } else if (message.type === "assistant" && message.parent_tool_use_id === null) {
        if (message.error === "rate_limit") limited = true;
        for (const block of message.message.content) {
          if (block.type === "text" && block.text.trim()) {
            texts.push(block.text);
            spoke = true;
            bus.emitEvent({ type: "say", agent: name, text: block.text.trim() });
          } else if (block.type === "tool_use" && block.name !== "StructuredOutput") {
            const input = (block.input ?? {}) as Record<string, unknown>;
            bus.emitEvent({ type: "agent", agent: name, team, status: "working", note: block.name });
            bus.emitEvent({ type: "tool", agent: name, tool: block.name, detail: describeTool(block.name, input) });
          }
        }
      } else if (message.type === "result") {
        sessionId = message.session_id;
        costUsd = message.total_cost_usd - (run.resume ? (sessionCosts.get(run.resume) ?? 0) : 0);
        sessionCosts.set(sessionId, message.total_cost_usd);
        bus.emitEvent({ type: "cost", agent: name, usd: costUsd });
        if (limited) throw new RateLimited(limitResetsAt, sessionId);
        if (message.subtype === "error_max_budget_usd") throw new BudgetExceeded();
        if (message.subtype !== "success") throw new AgentFailed(`${name} ist abgebrochen (${message.subtype}).`);
        if (message.result.trim()) texts.push(message.result);
        structured = message.structured_output;
      }
    }

    const data = run.schema ? run.schema.parse(structured) : (undefined as T);
    bus.emitEvent({ type: "agent", agent: name, team, status: "done" });
    return { text: texts.at(-1) ?? "", data, costUsd, sessionId, spoke };
  } catch (error) {
    // The CLI may also just exit when the limit hits; what it reported before decides.
    const failure = limited && !(error instanceof RateLimited) ? new RateLimited(limitResetsAt, sessionId) : error;
    const waiting = failure instanceof RateLimited;
    bus.emitEvent({ type: "agent", agent: name, team, status: waiting ? "waiting" : "error", note: waiting ? "wartet auf Limit" : errorText(error) });
    throw failure;
  } finally {
    run.signal?.removeEventListener("abort", onAbort);
  }
}
