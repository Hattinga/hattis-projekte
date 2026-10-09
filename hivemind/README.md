# hivemind

Eine kleine KI-Firma im Terminal. Statt dass ein einzelner Agent alles allein macht, geht dein Prompt durch mehrere Teams aus Claude-Agents, die wie in einer Firma zusammenarbeiten:

```
Dein Prompt
   │
   ▼
Prompt-Optimizer ── schaut sich das Projekt an, macht einen präzisen Auftrag draus,
   │                 fragt dich bei Unklarheiten nach und schätzt die Größe (S/M/L)
   ▼
Planungs-Team ───── Architektin, Skeptiker, Security & Qualität, Pragmatiker
   │                 Runde 1: alle schlagen parallel vor
   │                 ab Runde 2: sie antworten einander, bis alle einverstanden sind
   │                 Moderatorin entscheidet und schreibt den Plan (Tasks + Abhängigkeiten)
   ▼
Du gibst den Plan frei (oder schickst ihn mit Feedback zurück)
   │
   ▼
Coder-Team ──────── bis zu 3 Coder parallel, jeder in seinem eigenen git-Worktree
   │                 sie reden über ein Team-Board miteinander und fragen die Architektin
   │                 Reviewer prüft jede Task und schickt sie bei Bedarf zurück
   │                 fertige Tasks werden gemergt, bei Konflikten löst der Integrator
   ▼
Testerin ────────── prüft das Gesamtergebnis, behebt Kleinigkeiten, schreibt den Abschlussbericht
   │
   ▼
Du: fertig, nachbessern (das Team macht auf demselben Branch weiter) oder direkt mergen
```

Alle Agents sind vollwertige Claude-Code-Agents (über das [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk)): sie lesen deinen Code, führen Befehle aus und halten sich an die `CLAUDE.md` deines Projekts.

## Voraussetzungen

- Node.js 20 oder neuer
- Claude Code, eingeloggt (`claude` einmal starten und anmelden). hivemind nutzt diesen Login, läuft also über dein Claude-Abo. Mit gesetztem `ANTHROPIC_API_KEY` wird stattdessen pro Token über die API abgerechnet.
- Für das Coder-Team muss das Projekt ein git-Repo mit mindestens einem Commit sein.

## Installation

```bash
cd hivemind
npm install
npm link
```

Danach gibt es überall den Befehl `hivemind`.

## Benutzung

Im Projektordner:

```bash
hivemind "füg einen Dark Mode zu den Einstellungen hinzu"
```

Ohne Prompt fragt hivemind dich danach. Im Terminal siehst du:

- **Verlauf** mit Markdown: wer was sagt, welche Tools laufen, Nachrichten auf dem Team-Board (💬)
- **Live-Text**: was ein Agent gerade schreibt, Wort für Wort
- **Team-Übersicht**: alle Agents nach Teams, mit Status, aktuellem Tool und Kosten
- **Kopfzeile**: Phase, Laufzeit, Gesamtkosten

Bei Fragen wählst du mit Pfeiltasten und Enter oder direkt mit der Zahl. Im Textfeld gehen ←/→, Pos1/Ende und ↑/↓ für frühere Eingaben.

| Option | Bedeutung |
|---|---|
| `-p`, `--plan-only` | nur Optimizer und Planungs-Team, kein Code |
| `-f`, `--full` | immer das ganze Planungs-Team, egal wie klein der Auftrag ist |
| `-r`, `--rounds <n>` | höchstens so viele Diskussionsrunden (Standard 3) |
| `-c`, `--coders <n>` | parallele Coder (Standard 3) |
| `-m`, `--model <id>` | ein Modell für alle Agents, statt es pro Aufgabe zu wählen |
| `-a`, `--ask` | Agents fragen vor heiklen Aktionen, statt mit vollen Rechten zu laufen |
| `-C`, `--cwd <ordner>` | anderer Projektordner |

### Wer welches Modell bekommt

hivemind wählt das Modell pro Agent selbst, je nachdem, wie schwer seine Aufgabe ist. Im UI steht es neben jedem Agent.

| Agent | Modell |
|---|---|
| Prompt-Optimizer | Sonnet 5.5 |
| Planer | Sonnet 5.5 bei kleinen Aufträgen (S), sonst Opus 5.5 |
| Moderatorin, Integrator, Architektin bei Rückfragen | Opus 5.5 |
| Coder | je nach Task: leicht → Haiku 5.5, normal → Sonnet 5.5, schwer → Opus 5.5 |
| Reviewer | Opus 5.5 bei schweren Tasks, sonst Sonnet 5.5 |
| Testerin | Sonnet 5.5 |

Die Schwierigkeit jeder Task legt die Moderatorin im Plan fest, du siehst sie vor der Freigabe (`· leicht/normal/schwer`). Welches Modell zu welcher Stufe gehört, stellst du mit `models` in der Config ein; eine Rolle mit eigenem `model` behält das immer. `--model` oder `"routing": false` schaltet die Wahl ab.

### Rechte

Die Agents laufen standardmäßig mit vollen Rechten: Sie führen jeden Befehl ohne Nachfrage aus, damit nie einer hängt und auf dich wartet. Sie arbeiten zwar in eigenen Worktrees, aber ein Befehl kann trotzdem alles auf deinem Rechner erreichen. Mit `--ask` fragen sie dich vor heiklen Aktionen (`ja`, `nein` oder `immer` für den Rest des Laufs). Die Planer lesen nur und können nie etwas ändern.

Fragen, die immer kommen: Rückfragen des Optimizers, die Freigabe des Plans und am Ende „Wie geht's weiter?“.

### Dein Code bleibt unangetastet

Die Coder arbeiten nie in deinem Checkout. Alles landet auf einem eigenen Branch `hivemind/<datum-uhrzeit>`. Am Ende wählst du:

- **fertig**: der Branch bleibt, du schaust ihn dir in Ruhe an (`git diff HEAD...hivemind/…`) und mergst selbst
- **nachbessern**: du sagst, was nicht passt, die Moderatorin plant die Änderungen, das Team setzt sie auf demselben Branch um
- **in meinen Branch mergen**: hivemind mergt für dich, aber nur, wenn dein Checkout sauber ist; bei Konflikten wird nichts geändert

Uncommittete Änderungen sehen die Coder nicht, sie starten vom letzten Commit.

### Läufe fortsetzen und anschauen

```bash
hivemind runs              # alle Läufe in diesem Projekt: Status, Kosten, Phase, Auftrag
hivemind --resume          # den letzten abgebrochenen Lauf fortsetzen
hivemind --resume <id>     # einen bestimmten
```

Strg+C bricht sauber ab: alle Agents stoppen, die Worktrees werden aufgeräumt, der Stand bleibt gespeichert. Beim Fortsetzen überspringt hivemind, was schon fertig ist (Auftrag, Plan, gemergte Tasks).

Pro Lauf liegen in `.hivemind/<id>/` das komplette Protokoll (`transcript.md`), der Plan (`plan.json`) und der Zustand (`state.json`). Der Ordner wird automatisch aus git rausgehalten.

## Teams anpassen

Lege `hivemind.config.json` ins Projekt (gilt nur dort) oder `~/.hivemind/config.json` (gilt überall). Alles ist optional und überschreibt nur, was du angibst:

```json
{
  "routing": true,
  "models": { "easy": "claude-haiku-5-5", "normal": "claude-sonnet-5-5", "hard": "claude-opus-5-5" },
  "discussionRounds": 3,
  "triage": true,
  "coders": 2,
  "maxReviewLoops": 2,
  "architectQuestions": 4,
  "permissionMode": "bypassPermissions",
  "planners": ["architect", "skeptic", "security", "pragmatist", "roblox"],
  "roles": {
    "roblox": {
      "title": "Roblox-Profi",
      "effort": "high",
      "persona": "Du kennst Roblox und Luau in- und auswendig. Achte auf Client/Server-Trennung, RemoteEvents und Exploits."
    },
    "coder": { "model": "claude-sonnet-5-5" }
  }
}
```

- **Rollen:** `optimizer`, `architect`, `skeptic`, `security`, `pragmatist`, `moderator`, `coder`, `reviewer`, `integrator`, `tester`, plus beliebig viele eigene. Jede Rolle hat `title`, `persona` (Systemprompt), optional `model` und `effort` (`low` bis `max`).
- **`planners`:** wer im Planungs-Team mitdiskutiert, in dieser Reihenfolge. Die Moderatorin ist immer dabei. Bei kleinen Aufträgen (S) planen nur die ersten zwei.
- **`routing` / `models`:** siehe „Wer welches Modell bekommt“. Mit `"routing": false` nutzen alle Agents `model` (Standard `claude-opus-5-5`).
- **`triage`:** `false` heißt: immer das ganze Team und alle Runden (wie `--full`).
- **`architectQuestions`:** wie oft die Coder pro Lauf die Architektin fragen dürfen.
- **`permissionMode`:** `bypassPermissions` (Standard) fragt nie. `auto` lässt einen Klassifikator harmlose Aktionen freigeben und fragt dich nur bei unklaren (das macht auch `--ask`). `acceptEdits` erlaubt Dateiänderungen ohne Nachfrage und fragt bei jedem Befehl. `default` fragt bei allem.

## Kosten

Mehrere Agents verbrauchen mehr als einer. Mit dem Abo heißt das: deine Nutzungslimits sind schneller erreicht. hivemind spart, wo es geht:

- **Isolierte Agents:** Die Agents laden weder deine MCP-Server noch Plugins, Skills oder Hooks aus `~/.claude`, nur die Projekt-Settings und die `CLAUDE.md`. Mit vielen MCP-Servern spart das pro Agent-Schritt leicht 90 % der Tokens.
- **Schlanke Planer:** Lesende Agents bekommen einen kurzen eigenen Systemprompt statt des kompletten Claude-Code-Prompts.
- **Triage:** Kleine Aufträge bekommen zwei Planer und eine Runde, mittlere alle Planer und höchstens zwei Runden.
- **Früher Schluss:** Die Diskussion endet, sobald alle einverstanden sind.
- **Passende Modelle:** Leichte Aufgaben laufen auf Haiku oder Sonnet statt auf Opus.

Weiter sparen kannst du mit `--rounds 1`, `--coders 1` oder einem kleineren Modell für einzelne Rollen. Die angezeigten Dollar-Beträge sind Schätzungen des SDK.

## Entwicklung

```bash
npm test           # Tests (Scheduler, git-Workspace, Markdown, Config), ohne Agents, kostenlos
npm run typecheck
```

| Datei | Inhalt |
|---|---|
| `src/cli.tsx` | Argumente, `runs`, `--resume`, startet UI und Pipeline |
| `src/config.ts` | Standard-Rollen und Config laden |
| `src/agent.ts` | ein Agent = eine isolierte Claude-Code-Session mit Rolle, Rechten, Live-Events und einem Retry |
| `src/team.ts` | Team-Board und Team-Tools (post, read, ask_architect) als In-Process-MCP-Server |
| `src/bus.ts` | Event-Bus zwischen Pipeline, UI und Protokoll, plus Fragen an dich |
| `src/git.ts` | Worktrees, Branches, Merges, Aufräumen |
| `src/state.ts` | Lauf-Zustand für `runs` und `--resume` |
| `src/pipeline/` | `optimize.ts`, `plan.ts`, `code.ts`, `schedule.ts`, `run.ts` |
| `src/ui/` | Terminal-UI (Ink): `App.tsx`, `Markdown.tsx`, `TextInput.tsx`, `parseMarkdown.ts` |
