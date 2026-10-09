# hivemind

Eine kleine KI-Firma im Terminal. Statt dass ein einzelner Agent alles allein macht, geht dein Prompt durch mehrere Teams aus Claude-Agents, die wie in einer Firma zusammenarbeiten:

```
Dein Prompt
   │
   ▼
Prompt-Optimizer ── schaut sich das Projekt an, macht einen präzisen Auftrag draus,
   │                 fragt dich bei Unklarheiten nach, schätzt die Größe (S/M/L)
   │                 und schreibt einen Projektüberblick für alle anderen
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
   │                 Tasks mit denselben Dateien laufen nacheinander statt gegeneinander
   │                 sie reden über ein Team-Board miteinander und fragen die Architektin
   │                 Reviewer prüft jede Task und schickt sie bei Bedarf zurück
   │                 fertige Tasks werden gemergt, bei Konflikten löst der Integrator
   ▼
Testerin ────────── prüft das Gesamtergebnis; was sie findet, geht als Fix-Task zurück an die Coder
   │
   ▼
Du: fertig, nachbessern, in deinen Branch mergen oder Pull Request erstellen
   │
   ▼
Chronistin ──────── hält fest, was das Team über dein Projekt gelernt hat, für den nächsten Lauf
```

Alle Agents sind vollwertige Claude-Code-Agents (über das [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk)): sie lesen deinen Code, führen Befehle aus und halten sich an die `CLAUDE.md` deines Projekts.

## Voraussetzungen

- Node.js 20 oder neuer
- Claude Code, eingeloggt (`claude` einmal starten und anmelden). hivemind nutzt diesen Login, läuft also über dein Claude-Abo. Mit gesetztem `ANTHROPIC_API_KEY` wird stattdessen pro Token über die API abgerechnet.
- Für das Coder-Team muss das Projekt ein git-Repo sein. Hat es noch keinen Commit, bietet hivemind gleich am Anfang an, einen leeren Start-Commit anzulegen.
- Für Pull Requests: ein `origin` auf GitHub und die [GitHub CLI](https://cli.github.com/) (`gh`), eingeloggt.

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

- **Verlauf** mit Markdown: wer was sagt, Nachrichten auf dem Team-Board (💬), deine Nachrichten (✉)
- **Live-Text**: was ein Agent gerade schreibt, Wort für Wort
- **Team-Übersicht**: alle Agents nach Teams, mit Status, Modell, aktuellem Tool und Kosten
- **Kopfzeile**: Phase, Laufzeit, Gesamtkosten

**Mitreden:** Unten ist immer ein Textfeld. Was du dort schreibst (z.B. „bitte kein ESM“), geht als Nachricht ans Team: Jeder Agent, der danach startet, sieht sie, und laufende Coder finden sie auf dem Team-Board.

**Ansicht:** Standardmäßig ist sie kompakt: lange Beiträge werden nach 8 Zeilen gekürzt und Tool-Aufrufe ausgeblendet. Der Plan der Moderatorin kommt immer ganz. **Tab** schaltet um (gilt für alles, was danach kommt). Das komplette Protokoll steht immer in `transcript.md`.

Bei Fragen wählst du mit Pfeiltasten und Enter oder direkt mit der Zahl. Im Textfeld gehen ←/→, Pos1/Ende und ↑/↓ für frühere Eingaben.

| Option | Bedeutung |
|---|---|
| `-t`, `--team <name>` | Team-Vorlage, siehe unten |
| `-b`, `--budget <usd>` | höchstens so viele Dollar (Schätzung), dann sauber stoppen |
| `-p`, `--plan-only` | nur Optimizer und Planungs-Team, kein Code |
| `-f`, `--full` | immer das ganze Planungs-Team, egal wie klein der Auftrag ist |
| `-r`, `--rounds <n>` | höchstens so viele Diskussionsrunden (Standard 3) |
| `-c`, `--coders <n>` | parallele Coder (Standard 3) |
| `-m`, `--model <id>` | ein Modell für alle Agents, statt es pro Aufgabe zu wählen |
| `-a`, `--ask` | Agents fragen vor heiklen Aktionen, statt mit vollen Rechten zu laufen |
| `-C`, `--cwd <ordner>` | anderer Projektordner |

Weitere Befehle:

```bash
hivemind runs              # alle Läufe in diesem Projekt: Status, Kosten, Phase, Auftrag
hivemind --resume          # den letzten abgebrochenen Lauf fortsetzen
hivemind --resume <id>     # einen bestimmten
hivemind teams             # die Team-Vorlagen
hivemind memory            # was das Team über dieses Projekt weiß
```

### Team-Vorlagen

| Team | Für |
|---|---|
| `sparsam` | kleines Team, eine Runde, kein Opus bei den Codern: schont dein Limit |
| `roblox` | Roblox/Luau-Spiele, mit Roblox-Profi im Planungs-Team und Roblox-Regeln für alle (nie dem Client trauen …) |
| `web` | Webseiten und Web-Apps, mit UX-Designerin und Regeln zu Barrierefreiheit und responsivem Layout |

Eigene Teams legst du als `~/.hivemind/teams/<name>.json` an, im selben Aufbau wie `hivemind.config.json` plus `"description"`.

### Wer welches Modell bekommt

hivemind wählt das Modell pro Agent selbst, je nachdem, wie schwer seine Aufgabe ist. Im UI steht es neben jedem Agent.

| Agent | Modell |
|---|---|
| Prompt-Optimizer, Testerin | Sonnet 5.5 |
| Planer | Sonnet 5.5, bei großen Aufträgen (L) Opus 5.5 |
| Moderatorin, Integrator, Architektin bei Rückfragen | Opus 5.5 |
| Coder | je nach Task: leicht → Haiku 5.5, normal → Sonnet 5.5, schwer → Opus 5.5 |
| Reviewer | Opus 5.5 bei schweren Tasks, sonst Sonnet 5.5 |
| Chronistin | Haiku 5.5 |

Die Schwierigkeit jeder Task legt die Moderatorin im Plan fest, du siehst sie vor der Freigabe (`· leicht/normal/schwer`). Welches Modell zu welcher Stufe gehört, stellst du mit `models` in der Config ein; eine Rolle mit eigenem `model` behält das immer. `--model` oder `"routing": false` schaltet die Wahl ab.

### Nutzungslimit und Budget

- **Limit-Pause:** Ist das Nutzungslimit deines Abos erreicht, bricht nichts ab. hivemind zeigt „Es geht um 14:30 automatisch weiter“, wartet bis zum Reset und der Agent macht genau dort weiter, wo er war. Kurz vorher warnt es, wenn ein Limit fast voll ist.
- **Budget:** Mit `--budget 3` (oder `"budgetUsd": 3` in der Config) stoppt hivemind sauber, sobald die geschätzten Kosten 3 $ erreichen. Weiter geht's mit `hivemind --resume --budget 5`.

### Rechte

Die Agents laufen standardmäßig mit vollen Rechten: Sie führen jeden Befehl ohne Nachfrage aus, damit nie einer hängt und auf dich wartet. Sie arbeiten zwar in eigenen Worktrees, aber ein Befehl kann trotzdem alles auf deinem Rechner erreichen. Mit `--ask` fragen sie dich vor heiklen Aktionen (`ja`, `nein` oder `immer` für den Rest des Laufs). Die Planer lesen nur und können nie etwas ändern.

Fragen, die immer kommen: Rückfragen des Optimizers, die Freigabe des Plans und am Ende „Wie geht's weiter?“.

### Dein Code bleibt unangetastet

Die Coder arbeiten nie in deinem Checkout. Alles landet auf einem eigenen Branch `hivemind/<datum-uhrzeit>`. Am Ende wählst du:

- **fertig**: der Branch bleibt, du schaust ihn dir in Ruhe an (`git diff HEAD...hivemind/…`) und mergst selbst
- **nachbessern**: du sagst, was nicht passt, die Moderatorin plant die Änderungen, das Team setzt sie auf demselben Branch um
- **in meinen Branch mergen**: hivemind mergt für dich, aber nur, wenn dein Checkout sauber ist; bei Konflikten wird nichts geändert
- **Pull Request erstellen** (wenn `gh` und ein GitHub-`origin` da sind): pusht den Branch und öffnet einen PR in deinen aktuellen Branch, mit Plan und Testbericht als Beschreibung

Uncommittete Änderungen sehen die Coder nicht, sie starten vom letzten Commit.

Strg+C bricht sauber ab: alle Agents stoppen, die Worktrees werden aufgeräumt, der Stand bleibt gespeichert. Beim Fortsetzen überspringt hivemind, was schon fertig ist (Auftrag, Plan, gemergte Tasks).

### Wo was liegt

Alles liegt in `~/.hivemind/projects/<projekt>-<hash>/`, bewusst außerhalb deines Projekts: so landet nichts davon in git, und die Agents stolpern beim Umschauen nicht über alte Protokolle.

- `<lauf>/transcript.md`: das komplette Protokoll, wer was gesagt und gemacht hat
- `<lauf>/plan.json`, `<lauf>/state.json`: Plan und Zustand für `--resume`
- `memory.md`: das Gedächtnis des Teams für dieses Projekt. Die Chronistin aktualisiert es nach jedem fertigen Lauf, jeder Agent liest es. Du kannst es selbst bearbeiten oder mit `"memory": false` abschalten.

## Teams anpassen

Lege `hivemind.config.json` ins Projekt (gilt nur dort) oder `~/.hivemind/config.json` (gilt überall). Alles ist optional und überschreibt nur, was du angibst:

```json
{
  "routing": true,
  "models": { "easy": "claude-haiku-5-5", "normal": "claude-sonnet-5-5", "hard": "claude-opus-5-5" },
  "budgetUsd": 5,
  "discussionRounds": 3,
  "triage": true,
  "coders": 2,
  "maxReviewLoops": 2,
  "fixRounds": 1,
  "architectQuestions": 4,
  "memory": true,
  "permissionMode": "bypassPermissions",
  "guidance": "Alle Texte im UI auf Deutsch.",
  "planners": ["architect", "skeptic", "security", "pragmatist", "perf"],
  "roles": {
    "perf": {
      "title": "Performance-Profi",
      "effort": "high",
      "persona": "Du achtest auf Ladezeiten, Speicher und unnötige Arbeit."
    },
    "coder": { "model": "claude-sonnet-5-5" }
  }
}
```

- **Rollen:** `optimizer`, `architect`, `skeptic`, `security`, `pragmatist`, `moderator`, `coder`, `reviewer`, `integrator`, `tester`, `historian`, plus beliebig viele eigene. Jede Rolle hat `title`, `persona` (Systemprompt), optional `model` und `effort` (`low` bis `max`).
- **`planners`:** wer im Planungs-Team mitdiskutiert, in dieser Reihenfolge. Die Moderatorin ist immer dabei. Bei kleinen Aufträgen (S) planen nur die ersten zwei.
- **`guidance`:** Regeln, die jeder Agent bekommt.
- **`routing` / `models`:** siehe „Wer welches Modell bekommt“. Mit `"routing": false` nutzen alle Agents `model` (Standard `claude-opus-5-5`).
- **`triage`:** `false` heißt: immer das ganze Team und alle Runden (wie `--full`).
- **`fixRounds`:** wie oft Befunde der Testerin an die Coder zurückgehen (Standard 1, `0` = nur berichten).
- **`architectQuestions`:** wie oft die Coder pro Lauf die Architektin fragen dürfen.
- **`permissionMode`:** `bypassPermissions` (Standard) fragt nie. `auto` lässt einen Klassifikator harmlose Aktionen freigeben und fragt dich nur bei unklaren (das macht auch `--ask`). `acceptEdits` erlaubt Dateiänderungen ohne Nachfrage und fragt bei jedem Befehl. `default` fragt bei allem.

## Kosten

Mehrere Agents verbrauchen mehr als einer. Mit dem Abo heißt das: deine Nutzungslimits sind schneller erreicht. hivemind spart, wo es geht:

- **Isolierte Agents:** Die Agents laden weder deine MCP-Server noch Plugins, Skills oder Hooks aus `~/.claude`, nur die Projekt-Settings und die `CLAUDE.md`. Mit vielen MCP-Servern spart das pro Agent-Schritt leicht 90 % der Tokens.
- **Projektüberblick:** Der Optimizer erkundet das Projekt einmal für alle, statt dass jeder Agent selbst sucht.
- **Gedächtnis:** Was das Team schon weiß, muss es nicht neu herausfinden.
- **Schlanke Planer:** Lesende Agents bekommen einen kurzen eigenen Systemprompt statt des kompletten Claude-Code-Prompts.
- **Triage:** Kleine Aufträge bekommen zwei Planer und eine Runde, mittlere alle Planer und höchstens zwei Runden.
- **Kurze Beiträge:** Planer haben eine Wortgrenze (etwa 250 Wörter zum Start, 120 pro Antwort), weil jeder Beitrag in allen folgenden Runden mitgelesen wird.
- **Früher Schluss:** Die Diskussion endet, sobald alle einverstanden sind.
- **Passende Modelle:** Leichte Aufgaben laufen auf Haiku oder Sonnet statt auf Opus.

Weiter sparen kannst du mit `--team sparsam`, `--rounds 1`, `--coders 1` oder `--budget`. Die angezeigten Dollar-Beträge sind Schätzungen des SDK.

## Entwicklung

```bash
npm test           # Tests ohne echte Agents, kostenlos
npm run typecheck
```

Die Tests decken Scheduler, git-Workspace, Markdown und Config ab, und in `test/pipeline.test.ts` einen kompletten Lauf mit simulierten Agents (`setAgentImplementation`): Planung, parallele Coder, Konfliktvermeidung, Fix-Runde, Gedächtnis, Modellwahl, Budget-Stopp. `HIVEMIND_HOME` lenkt `~/.hivemind` dabei in einen Temp-Ordner um.

| Datei | Inhalt |
|---|---|
| `src/cli.tsx` | Argumente, Befehle, startet UI und Pipeline |
| `src/config.ts` | Standard-Rollen, Team-Vorlagen, Config laden |
| `src/agent.ts` | ein Agent = eine isolierte Claude-Code-Session; Limit-Pause, Budget, Retry, gemeinsamer Hintergrund |
| `src/team.ts` | Team-Board und Team-Tools (post, read, ask_architect) als In-Process-MCP-Server |
| `src/bus.ts` | Event-Bus zwischen Pipeline, UI und Protokoll, plus Fragen an dich |
| `src/git.ts` | Worktrees, Branches, Merges, Aufräumen |
| `src/pr.ts` | Pull Request über die GitHub CLI |
| `src/state.ts` | Lauf-Zustand für `runs` und `--resume` |
| `src/pipeline/` | `optimize.ts`, `plan.ts`, `code.ts`, `schedule.ts`, `memory.ts`, `run.ts` |
| `src/ui/` | Terminal-UI (Ink): `App.tsx`, `Markdown.tsx`, `TextInput.tsx`, `parseMarkdown.ts` |
