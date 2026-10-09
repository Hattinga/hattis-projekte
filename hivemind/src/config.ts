import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { McpServerConfig, PermissionMode } from "@anthropic-ai/claude-agent-sdk";

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
  /** MCP servers this role may use, by name (looked up in `mcpServers`, then in your Claude Code setup). */
  mcp?: string[];
  /**
   * For roles that only read or test: exactly these MCP tools (full names) are allowed, everything else
   * is denied, whatever the permission mode. Roles that write (coders) get every tool of their servers.
   */
  mcpTools?: string[];
}

/**
 * git: coders work in parallel git worktrees on files, the result is a branch.
 * studio: the game lives in Roblox Studio; coders change it one after another through the Studio MCP.
 */
export type Mode = "git" | "studio";

export interface Config {
  mode: Mode;
  /** MCP servers roles can name in `mcp`, in addition to the ones from your Claude Code setup. */
  mcpServers?: Record<string, McpServerConfig>;
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
  /** A team preset this config builds on (`hivemind teams`). `--team` on the command line wins. */
  team?: string;
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
  mode: "git",
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

/** What a config file or team preset may contain: any part of Config, and roles only partly. */
export type ConfigOverride = Omit<Partial<Config>, "roles"> & { roles?: Record<string, Partial<Role>> };

export interface TeamPreset {
  description: string;
  config: ConfigOverride;
}

const STUDIO = "mcp__Roblox_Studio__";
/** Studio tools that only look: scripts, the instance tree, the output window. */
export const STUDIO_READ_TOOLS = ["get_studio_state", "list_roblox_studios", "script_read", "script_grep", "script_search", "search_game_tree", "inspect_instance", "get_console_output"].map((t) => STUDIO + t);
/** What QA needs on top: playtests, screenshots, simulated input, reading state with Luau. */
export const STUDIO_QA_TOOLS = [
  ...STUDIO_READ_TOOLS,
  ...["start_stop_play", "screen_capture", "execute_luau", "user_mouse_input", "user_keyboard_input", "character_navigation", "wait_job_finished"].map((t) => STUDIO + t),
];

const ROBLOX_PROFI: Role = {
  title: "Roblox-Profi",
  effort: "high",
  persona: `Du bist der Roblox-Profi im Planungs-Team. Du kennst Luau, die Roblox-Engine und ihre Services in- und auswendig.
Achte auf saubere Client/Server-Trennung, Replikation und Netzwerk-Besitz, RemoteEvents/RemoteFunctions (Validierung, Rate-Limits),
DataStores (Limits, Retries, Session-Locking), Streaming und Performance auf schwachen Handys.`,
};

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
  "roblox-studio": {
    description: "Roblox-Spiele, die in Roblox Studio leben: das Team arbeitet über den Studio-MCP, nacheinander, ohne git",
    config: {
      mode: "studio",
      planners: ["architect", "roblox", "skeptic", "security"],
      roles: {
        roblox: ROBLOX_PROFI,
        optimizer: { mcp: ["Roblox_Studio"], mcpTools: STUDIO_READ_TOOLS },
        coder: {
          mcp: ["Roblox_Studio"],
          persona: `Du bist Roblox-Entwickler in einer Software-Firma aus KI-Agents. Du bekommst genau eine Task aus einem abgestimmten Plan
und setzt sie direkt im laufenden Roblox Studio um, über die Roblox-Studio-Tools: Skripte lesen und ändern, Instanzen anlegen, Luau ausführen.
Wähle zuerst mit list_roblox_studios die richtige Studio-Instanz. Halte dich an die vorhandene Struktur und die Konventionen der Skripte.
Mach nur, was die Task verlangt. Prüf dein Ergebnis kurz (Output-Fenster auf Fehler, bei Bedarf ein kurzer stiller Playtest, den du wieder stoppst).
Studio nicht speichern oder veröffentlichen. Antworte zum Schluss mit einer kurzen Zusammenfassung auf Deutsch:
welche Skripte und Instanzen du geändert hast, was geprüft ist, was offen ist.`,
        },
        reviewer: {
          mcp: ["Roblox_Studio"],
          mcpTools: STUDIO_READ_TOOLS,
          persona: `Du bist Code-Reviewer für ein Roblox-Spiel. Die Änderungen des Coders sind live in Roblox Studio; lies die betroffenen Skripte
und Instanzen mit den Studio-Tools (zuerst list_roblox_studios und die richtige Instanz wählen). Fokus: Korrektheit, Bugs, Randfälle,
Client/Server-Trennung (der Server prüft jede Client-Eingabe), Rate-Limits, Speicherlecks durch nicht getrennte Verbindungen, ob die Task erfüllt ist.
Keine Stil-Kleinigkeiten. approved nur, wenn du es so ins Spiel nehmen würdest; sonst konkret, was zu ändern ist (Skript-Pfad, Zeile, warum).`,
        },
        tester: {
          mcp: ["Roblox_Studio"],
          mcpTools: STUDIO_QA_TOOLS,
          persona: `Du bist die Testerin für ein Roblox-Spiel in Roblox Studio. Wähle mit list_roblox_studios die richtige Instanz.
Teste das Ergebnis gegen den Auftrag: Playtests, Output-Fenster, Zustand mit execute_luau auslesen, Screenshots, simulierte Eingaben.
Reproduziere jeden Fehler zweimal, bevor du ihn meldest, und belege ihn (Konsolenzeilen, ausgelesene Werte oder Screenshot).
screen_capture ist schwarz, wenn Studio im Hintergrund ist: dann über Daten prüfen (Positionen, Attribute).
Nie: Skripte ändern oder den Place dauerhaft verändern (execute_luau nur zum Auslesen und für vorhandene Test-Hooks; was du für einen Test
anlegst, entfernst du wieder), Ton in Playtests, veröffentlichen, kaufen, DataStores eines Live-Spiels anfassen.
Stoppe den Playtest immer, bevor du fertig bist.
Antworte mit einem kurzen Abschlussbericht auf Deutsch: was funktioniert, was nicht, was der Kunde noch selbst prüfen sollte.
Setze passed nur auf false, wenn etwas wirklich kaputt ist oder eine Anforderung fehlt, und beschreibe dann jedes Problem in problems
so, dass ein Coder es ohne Rückfrage beheben kann (was, wo, wie man es nachprüft).`,
        },
      },
      guidance: `Roblox-Spiel, Studio ist die Quelle der Wahrheit (kein git). Vertraue nie dem Client: jede RemoteEvent-Eingabe wird auf dem Server geprüft.
Spiellogik und Daten gehören auf den Server, der Client macht Darstellung und Eingabe. Playtests ohne Ton. Nichts veröffentlichen.`,
    },
  },
  roblox: {
    description: "Roblox/Luau-Projekte als Dateien (z.B. Rojo + git), mit Roblox-Profi im Planungs-Team",
    config: {
      planners: ["architect", "roblox", "skeptic", "security"],
      roles: {
        roblox: ROBLOX_PROFI,
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
      const preset = JSON.parse(readFileSync(join(dir, file), "utf8")) as Partial<TeamPreset> & ConfigOverride;
      const { description = "eigenes Team", config, ...rest } = preset;
      teams[file.slice(0, -5)] = { description, config: config ?? (rest as ConfigOverride) };
    }
  }
  return teams;
}

function merge(config: Config, override: ConfigOverride): Config {
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
  const files = [join(hivemindHome(), "config.json"), join(cwd, "hivemind.config.json")]
    .filter((path) => existsSync(path))
    .map((path) => JSON.parse(readFileSync(path, "utf8")) as ConfigOverride);
  // The team preset comes first, so your own files can still change single things of it.
  const teamName = team ?? files.findLast((f) => f.team)?.team;
  let config: Config = { ...DEFAULT_CONFIG, roles: { ...DEFAULT_ROLES } };
  if (teamName) {
    const preset = listTeams()[teamName];
    if (!preset) throw new Error(`Team "${teamName}" gibt es nicht. Siehe: hivemind teams`);
    config = merge(config, preset.config);
  }
  for (const file of files) config = merge(config, file);
  config.team = teamName;
  for (const key of ["optimizer", "moderator", "coder", "reviewer", "integrator", "tester", "historian", ...config.planners]) {
    if (!config.roles[key]) throw new Error(`Rolle "${key}" ist in keiner Config definiert.`);
  }
  return config;
}
