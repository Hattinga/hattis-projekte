import { EventEmitter } from "node:events";

export type AgentStatus = "idle" | "thinking" | "working" | "done" | "error";

export type HiveEvent =
  | { type: "phase"; phase: string }
  | { type: "agent"; agent: string; team: string; status: AgentStatus; note?: string; model?: string }
  | { type: "say"; agent: string; text: string }
  /** A piece of text an agent is writing right now; the full block follows as "say". */
  | { type: "delta"; agent: string; text: string }
  /** A message on the team board, visible to every coder. */
  | { type: "chat"; from: string; text: string }
  | { type: "tool"; agent: string; tool: string; detail: string }
  | { type: "cost"; agent: string; usd: number }
  | { type: "info"; text: string }
  | { type: "error"; text: string }
  | { type: "ask"; id: number; question: string; choices?: string[] }
  | { type: "finished"; summary: string };

/** One event stream shared by the pipeline, the UI and the transcript writer. */
class Bus extends EventEmitter {
  private nextAsk = 1;
  private pending = new Map<number, { resolve: (answer: string) => void; reject: (error: Error) => void }>();

  emitEvent(event: HiveEvent) {
    this.emit("event", event);
  }

  onEvent(listener: (event: HiveEvent) => void) {
    this.on("event", listener);
    return () => {
      this.off("event", listener);
    };
  }

  /** Asks the human a question through whatever UI is listening and waits for the answer. */
  ask(question: string, choices?: string[]): Promise<string> {
    const id = this.nextAsk++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.emitEvent({ type: "ask", id, question, choices });
    });
  }

  answer(id: number, answer: string) {
    this.pending.get(id)?.resolve(answer);
    this.pending.delete(id);
  }

  /** Fails every open question, e.g. when the run is aborted while waiting for you. */
  cancelAsks(reason: string) {
    for (const { reject } of this.pending.values()) reject(new Error(reason));
    this.pending.clear();
  }
}

export const bus = new Bus();
