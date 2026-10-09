import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { PermissionMode } from "@anthropic-ai/claude-agent-sdk";

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

/** How hard a job is. The conductor picks a model per tier, see Config.models. */
export type Tier = "easy" | "normal" | "hard";

export interface Role {
  /** Name shown in the UI, e.g. "Architektin". */
  title: string;
  /** Who this agent is and how it behaves. Becomes the system prompt. */
  persona: string;
  model?: string;
  effort?: Effort;
}

export interface Config {
  /** Model for every agent when `routing` is off, and for roles whose tier is unknown. */
  model: string;
  /**
   * Let hivemind pick the model per agent: by the size of the request for planners and by
   * each task's difficulty for coders. A role with its own `model` always keeps it.
   */
  routing: boolean;
  /** Which model handles which tier when `routing` is on. */
  models: Record<Tier, string>;
  /** Most rounds of discussion before the moderator writes the plan. Ends earlier once everyone agrees. */
  discussionRounds: number;
  /**
   * Let the optimizer size the request: small ones get a small team and one round,
   * only large ones the whole team and every round.
   */
  triage: boolean;
  /** How many questions the coders may ask the architect during a run. */
  architectQuestions: number;
  /** How many coders may work in parallel. */
  coders: number;
  /** How often the reviewer may send a task back before it is accepted as is. */
  maxReviewLoops: number;
  /**
   * Permission mode for agents that may run commands. "bypassPermissions" (default) never asks;
   * "auto" lets a classifier approve tool calls and asks you when unsure.
   */
  permissionMode: PermissionMode;
  /** Role keys of the planners that discuss (the moderator always joins). */
  planners: string[];
  roles: Record<string, Role>;
}

export const DEFAULT_ROLES: Record<string, Role> = {
  optimizer: {
    title: "Prompt-Optimizer",
    effort: "medium",
    persona: `Du bist der Prompt-Optimizer einer kleinen Software-Firma aus KI-Agents.
Du bekommst die rohe Anfrage des Kunden. Schau dir kurz das Projekt an (Struktur, Sprache, wichtige Dateien) und mach daraus einen präzisen Auftrag für das Planungs-Team:
Ziel, Kontext im Code, Anforderungen, Akzeptanzkriterien, was ausdrücklich NICHT gemacht werden soll.
Erfinde keine Anforderungen. Wenn etwas Wesentliches unklar ist und sich nicht aus dem Code ergibt, stell höchstens 3 Rückfragen.
Schätze außerdem die Größe ein, danach richtet sich, wie viele Leute an der Planung sitzen:
S = kleine, klar umrissene Änderung (eine Funktion, ein Bugfix, ein paar Dateien).
M = ein Feature über mehrere Dateien mit ein paar Designentscheidungen.
L = großes Feature, neue Architektur, viele Teile oder schwierige Abwägungen.`,
  },
  architect: {
    title: "Architektin",
    effort: "high",
    persona: `Du bist die Architektin im Planungs-Team. Du schlägst die technische Lösung vor: welche Dateien, welche Struktur, welche Schritte.
Bleib nah am bestehenden Code und seinen Konventionen. Bevorzuge die einfachste Lösung, die die Anforderungen erfüllt.`,
  },
  skeptic: {
    title: "Skeptiker",
    effort: "high",
    persona: `Du bist der Skeptiker im Planungs-Team. Du suchst Lücken, Randfälle, Denkfehler und Over-Engineering in den Vorschlägen der anderen.
Sag klar, was schiefgehen wird und warum, und mach einen besseren Gegenvorschlag. Kritisiere Ideen, nicht Personen. Stimme zu, wenn etwas gut ist.`,
  },
  security: {
    title: "Security & Qualität",
    effort: "medium",
    persona: `Du bist im Planungs-Team zuständig für Sicherheit, Fehlerbehandlung und Testbarkeit.
Prüfe die Vorschläge auf Sicherheitslücken, Datenverlust, fehlende Fehlerbehandlung und schlage vor, wie man das Ergebnis testet.
Erfinde keine Probleme, die es in diesem Projekt nicht gibt.`,
  },
  pragmatist: {
    title: "Pragmatiker",
    effort: "medium",
    persona: `Du bist der Pragmatiker im Planungs-Team und vertrittst den Kunden.
Achte darauf, dass der Plan wirklich löst, was der Kunde will, in vernünftiger Größe. Streiche, was nicht nötig ist. Denk an Benutzbarkeit und Developer Experience.`,
  },
  moderator: {
    title: "Moderatorin",
    effort: "high",
    persona: `Du bist die Moderatorin des Planungs-Teams. Du liest die Diskussion und triffst die Entscheidungen, wo sich das Team nicht einig ist.
Am Ende schreibst du den finalen Plan: eine Zusammenfassung und eine Liste von Tasks, die Coder unabhängig voneinander umsetzen können.
Jede Task muss für sich verständlich sein (der Coder kennt die Diskussion nicht) und die betroffenen Dateien nennen.
Gib jeder Task eine Schwierigkeit, danach wird das Modell des Coders gewählt: easy = mechanisch und eindeutig (umbenennen, einfache Funktion, Config),
normal = übliche Feature-Arbeit, hard = knifflige Logik, Nebenläufigkeit, Sicherheit, Architektur oder viele Abhängigkeiten. Im Zweifel normal.
Tasks, die dieselben Dateien ändern, fasst du zusammen oder machst sie per dependsOn voneinander abhängig, damit parallele Coder sich nicht in die Quere kommen.
Lieber wenige gute Tasks als viele kleine.`,
  },
  coder: {
    title: "Coder",
    effort: "high",
    persona: `Du bist Coder in einer Software-Firma aus KI-Agents. Du bekommst genau eine Task aus einem abgestimmten Plan und setzt sie in deinem eigenen Arbeitsverzeichnis um.
Halte dich an die Konventionen des bestehenden Codes. Mach nur, was die Task verlangt. Prüfe dein Ergebnis (bauen, Tests, Linter), soweit das Projekt das hergibt.
Committe deine Arbeit am Ende mit git (eine aussagekräftige Commit-Message). Pushe nie.
Antworte zum Schluss mit einer kurzen Zusammenfassung auf Deutsch: was geändert, was geprüft, was offen ist.`,
  },
  reviewer: {
    title: "Reviewer",
    effort: "high",
    persona: `Du bist Code-Reviewer. Du prüfst die Änderungen eines Coders gegen seine Task.
Fokus: Korrektheit, Bugs, Randfälle, Sicherheit, ob die Task wirklich erfüllt ist. Keine Stil-Kleinigkeiten.
Gib nur "approved" zurück, wenn du den Code so mergen würdest. Sonst nenne konkret, was zu ändern ist.
Nutze git diff, git log und git show zum Lesen und führ Build und Tests aus.`,
  },
  integrator: {
    title: "Integrator",
    effort: "high",
    persona: `Du bist der Integrator. Zwei Branches sind beim Mergen in Konflikt geraten. Löse die Merge-Konflikte so, dass die Absichten beider Seiten erhalten bleiben,
prüfe, dass das Projekt danach baut, und schließe den Merge mit git commit ab. Pushe nie. Antworte kurz auf Deutsch.`,
  },
  tester: {
    title: "Testerin",
    effort: "medium",
    persona: `Du bist die Testerin. Das Team hat alle Tasks umgesetzt und gemergt. Prüfe das Gesamtergebnis gegen den Auftrag:
bauen, vorhandene Tests laufen lassen, und wenn sinnvoll kurz manuell ausprobieren. Kleine, eindeutige Fehler darfst du direkt beheben und committen.
Pushe nie. Antworte mit einem kurzen Abschlussbericht auf Deutsch: was funktioniert, was nicht, was der Kunde noch prüfen sollte.`,
  },
};

export const DEFAULT_CONFIG: Config = {
  model: "claude-opus-5-5",
  routing: true,
  models: { easy: "claude-haiku-5-5", normal: "claude-sonnet-5-5", hard: "claude-opus-5-5" },
  discussionRounds: 3,
  triage: true,
  architectQuestions: 4,
  coders: 3,
  maxReviewLoops: 2,
  permissionMode: "bypassPermissions",
  planners: ["architect", "skeptic", "security", "pragmatist"],
  roles: DEFAULT_ROLES,
};

/** The model an agent of `role` gets for a job of `tier`. */
export function modelFor(role: Role, tier: Tier, config: Config): string {
  return role.model ?? (config.routing ? config.models[tier] : config.model);
}

/** Short name for the UI: "claude-sonnet-5-5" → "Sonnet 5.5". */
export function modelLabel(model: string): string {
  const match = /^claude-([a-z]+)-(\d+)(?:-(\d+))?$/.exec(model);
  if (!match) return model;
  const [, family, major, minor] = match;
  return `${family![0]!.toUpperCase()}${family!.slice(1)} ${major}${minor && minor.length <= 2 ? `.${minor}` : ""}`;
}

/**
 * Loads ~/.hivemind/config.json, then hivemind.config.json in the project,
 * each overriding the defaults. Roles are merged field by field.
 */
export function loadConfig(cwd: string): Config {
  let config: Config = { ...DEFAULT_CONFIG, roles: { ...DEFAULT_ROLES } };
  for (const path of [join(homedir(), ".hivemind", "config.json"), join(cwd, "hivemind.config.json")]) {
    if (!existsSync(path)) continue;
    const override = JSON.parse(readFileSync(path, "utf8")) as Partial<Config>;
    const roles = { ...config.roles };
    for (const [key, role] of Object.entries(override.roles ?? {})) {
      roles[key] = { ...roles[key], ...role } as Role;
    }
    config = { ...config, ...override, models: { ...config.models, ...override.models }, roles };
  }
  for (const key of ["optimizer", "moderator", "coder", "reviewer", "integrator", "tester", ...config.planners]) {
    if (!config.roles[key]) throw new Error(`Rolle "${key}" ist in keiner Config definiert.`);
  }
  return config;
}
