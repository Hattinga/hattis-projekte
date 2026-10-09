import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { PermissionMode } from "@anthropic-ai/claude-agent-sdk";

/** ~/.hivemind, or HIVEMIND_HOME (used by the tests, so they never touch your real one). */
export function hivemindHome(): string {
  return process.env.HIVEMIND_HOME || join(homedir(), ".hivemind");
}

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
  /** Stop the run once the estimated cost reaches this many dollars. */
  budgetUsd?: number;
  /** How often failing checks at the end become fix tasks for the coders before the result is handed over. */
  fixRounds: number;
  /** Keep a memory per project that the team updates after every finished run. */
  memory: boolean;
  /** Extra rules every agent gets, e.g. from a team preset ("Roblox: never trust the client"). */
  guidance?: string;
}

export const DEFAULT_ROLES: Record<string, Role> = {
  optimizer: {
    title: "Prompt-Optimizer",
    effort: "medium",
    persona: `Du bist der Prompt-Optimizer einer kleinen Software-Firma aus KI-Agents.
Du bekommst die rohe Anfrage des Kunden. Schau dir kurz das Projekt an (Struktur, Sprache, wichtige Dateien) und mach daraus einen präzisen Auftrag für das Planungs-Team:
Ziel, Kontext im Code, Anforderungen, Akzeptanzkriterien, was ausdrücklich NICHT gemacht werden soll.
Erfinde keine Anforderungen. Wenn etwas Wesentliches unklar ist und sich nicht aus dem Code ergibt, stell höchstens 3 Rückfragen.
Schreib außerdem einen Projektüberblick für das ganze Team, höchstens etwa 400 Wörter: Sprache und Frameworks, Ordnerstruktur,
wichtige Dateien und was sie tun, Befehle zum Bauen und Testen, Konventionen. Das Team liest den Überblick, statt das Projekt selbst
noch einmal zu erkunden, also nenne, was für diesen Auftrag zählt. Bei einem leeren Projekt reicht ein Satz.
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
Pushe nie. Antworte mit einem kurzen Abschlussbericht auf Deutsch: was funktioniert, was nicht, was der Kunde noch prüfen sollte.
Setze passed nur auf false, wenn etwas wirklich kaputt ist oder eine Anforderung fehlt, und beschreibe dann jedes Problem in problems
so, dass ein Coder es ohne Rückfrage beheben kann (was, wo, wie man es nachprüft). Geschmacksfragen sind keine Probleme.`,
  },
  historian: {
    title: "Chronistin",
    effort: "low",
    persona: `Du führst das Gedächtnis des Teams für dieses Projekt. Nach jedem Lauf hältst du fest, was künftigen Läufen hilft:
Konventionen, Architekturentscheidungen und ihre Gründe, Befehle zum Bauen und Testen, Stolperfallen, Vorlieben des Kunden.
Kein Protokoll des Laufs und keine Liste, was gebaut wurde, außer es ist für künftige Arbeit wichtig. Veraltetes streichst du.
Höchstens etwa 400 Wörter, Markdown-Stichpunkte nach Themen.`,
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
  fixRounds: 1,
  memory: true,
};

export interface TeamPreset {
  description: string;
  config: Partial<Config>;
}

/** Ready-made teams for `--team <name>`. Your own go into ~/.hivemind/teams/<name>.json. */
export const BUILTIN_TEAMS: Record<string, TeamPreset> = {
  sparsam: {
    description: "kleines Team, eine Runde, kein Opus bei Codern: schont dein Limit",
    config: {
      planners: ["architect", "skeptic"],
      discussionRounds: 1,
      coders: 2,
      models: { easy: "claude-haiku-5-5", normal: "claude-sonnet-5-5", hard: "claude-sonnet-5-5" },
    },
  },
  roblox: {
    description: "Roblox/Luau-Spiele, mit Roblox-Profi im Planungs-Team",
    config: {
      planners: ["architect", "roblox", "skeptic", "security"],
      roles: {
        roblox: {
          title: "Roblox-Profi",
          effort: "high",
          persona: `Du bist der Roblox-Profi im Planungs-Team. Du kennst Luau, die Roblox-Engine und ihre Services in- und auswendig.
Achte auf saubere Client/Server-Trennung, Replikation, RemoteEvents/RemoteFunctions, DataStores (Limits, Retries, Session-Locking) und Performance.`,
        },
      },
      guidance: `Das ist ein Roblox-Projekt (Luau). Vertraue nie dem Client: jede RemoteEvent-Eingabe wird auf dem Server geprüft.
Spiellogik und Daten gehören auf den Server, der Client macht Darstellung und Eingabe. Halte dich an die vorhandene Struktur (z.B. Rojo-Projekt,
ServerScriptService/ReplicatedStorage/StarterPlayer). Roblox Studio kann hier niemand bedienen: was nur im Studio prüfbar ist, gehört in den Abschlussbericht.`,
    },
  },
  web: {
    description: "Webseiten und Web-Apps, mit UX-Designerin im Planungs-Team",
    config: {
      planners: ["architect", "ux", "skeptic", "security"],
      roles: {
        ux: {
          title: "UX-Designerin",
          effort: "medium",
          persona: `Du bist die UX-Designerin im Planungs-Team. Du achtest darauf, dass die Oberfläche verständlich, zugänglich (Tastatur, Kontraste, Screenreader)
und auf Handy und Desktop gut benutzbar ist, und dass Lade-, Leer- und Fehlerzustände bedacht sind.`,
        },
      },
      guidance: "Web-Projekt: Barrierefreiheit (semantisches HTML, Tastatur, Kontraste) und responsives Layout gehören zu jeder Oberfläche dazu.",
    },
  },
};

/** Built-in teams plus your own from ~/.hivemind/teams/*.json. */
export function listTeams(): Record<string, TeamPreset> {
  const teams = { ...BUILTIN_TEAMS };
  const dir = join(hivemindHome(), "teams");
  if (existsSync(dir)) {
    for (const file of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
      const preset = JSON.parse(readFileSync(join(dir, file), "utf8")) as Partial<TeamPreset> & Partial<Config>;
      const { description = "eigenes Team", config, ...rest } = preset;
      teams[file.slice(0, -5)] = { description, config: config ?? (rest as Partial<Config>) };
    }
  }
  return teams;
}

function merge(config: Config, override: Partial<Config>): Config {
  const roles = { ...config.roles };
  for (const [key, role] of Object.entries(override.roles ?? {})) {
    roles[key] = { ...roles[key], ...role } as Role;
  }
  return { ...config, ...override, models: { ...config.models, ...override.models }, roles };
}

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
 * Loads ~/.hivemind/config.json, then hivemind.config.json in the project, then the team preset,
 * each overriding what came before. Roles are merged field by field.
 */
export function loadConfig(cwd: string, team?: string): Config {
  let config: Config = { ...DEFAULT_CONFIG, roles: { ...DEFAULT_ROLES } };
  for (const path of [join(hivemindHome(), "config.json"), join(cwd, "hivemind.config.json")]) {
    if (existsSync(path)) config = merge(config, JSON.parse(readFileSync(path, "utf8")) as Partial<Config>);
  }
  if (team) {
    const preset = listTeams()[team];
    if (!preset) throw new Error(`Team "${team}" gibt es nicht. Siehe: hivemind teams`);
    config = merge(config, preset.config);
  }
  for (const key of ["optimizer", "moderator", "coder", "reviewer", "integrator", "tester", "historian", ...config.planners]) {
    if (!config.roles[key]) throw new Error(`Rolle "${key}" ist in keiner Config definiert.`);
  }
  return config;
}
