import { Box, Static, Text, useApp, useInput, useWindowSize } from "ink";
import { useEffect, useRef, useState } from "react";
import { bus, type AgentStatus, type HiveEvent } from "../bus.js";
import { modelLabel } from "../config.js";
import { Markdown } from "./Markdown.js";
import { TextInput } from "./TextInput.js";

/** `compact` is decided when the event arrives: lines already printed can't change anymore. */
type LogEvent = Exclude<HiveEvent, { type: "agent" | "cost" | "ask" | "delta" | "limit" }> & { key: number; compact: boolean };
type Ask = Extract<HiveEvent, { type: "ask" }>;

interface Member {
  name: string;
  team: string;
  status: AgentStatus;
  note?: string;
  model?: string;
  usd: number;
}

const COLORS = ["cyan", "magenta", "yellow", "green", "blue", "redBright", "cyanBright", "magentaBright", "greenBright", "yellowBright"];
const colorOf = (name: string) => COLORS[[...name].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % COLORS.length]!;

const ICON: Record<AgentStatus, string> = { idle: "○", thinking: "◐", working: "●", waiting: "⏸", done: "✓", error: "✗" };
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
/** How many lines of an agent's live text stay visible while it writes. */
const LIVE_LINES = 4;
/** In the compact view, longer messages are cut to this many lines; the transcript keeps everything. */
const COMPACT_LINES = 8;

function shorten(text: string): string {
  const lines = text.split("\n");
  if (lines.length <= COMPACT_LINES + 2) return text;
  // Never cut inside a code block: that would swallow the rest of the message into it.
  let cut = lines.slice(0, COMPACT_LINES);
  if (cut.filter((l) => l.trimStart().startsWith("```")).length % 2 === 1) cut = [...cut, "```"];
  return `${cut.join("\n")}\n\n*… ${lines.length - COMPACT_LINES} Zeilen mehr im Protokoll (Tab zeigt künftig alles)*`;
}

function LogLine({ event }: { event: LogEvent }) {
  switch (event.type) {
    case "phase":
      return (
        <Box marginTop={1}>
          <Text bold color="black" backgroundColor="cyan">{` ${event.phase} `}</Text>
        </Box>
      );
    case "say":
      return (
        <Box flexDirection="column" marginTop={1}>
          <Text bold color={colorOf(event.agent)}>● {event.agent}</Text>
          <Box paddingLeft={2}>
            <Markdown text={event.compact ? shorten(event.text) : event.text} />
          </Box>
        </Box>
      );
    case "chat":
      return (
        <Text>
          <Text color="magenta">💬 </Text>
          <Text bold color={colorOf(event.from)}>{event.from}</Text>
          <Text color="magenta"> ▸ Team: </Text>
          {event.text}
        </Text>
      );
    case "note":
      return (
        <Text>
          <Text color="cyan">✉ </Text>
          <Text bold color="cyan">Du</Text>
          <Text color="cyan"> ▸ Team: </Text>
          {event.text}
        </Text>
      );
    case "tool":
      if (event.compact) return null;
      return (
        <Text dimColor>
          {"  "}
          <Text color={colorOf(event.agent)}>{event.agent}</Text> ⎿ {event.tool} {event.detail}
        </Text>
      );
    case "info":
      return <Text color="yellow">» {event.text}</Text>;
    case "error":
      return <Text color="red">✗ {event.text}</Text>;
    case "finished":
      return (
        <Box borderStyle="round" borderColor="green" flexDirection="column" paddingX={1} marginTop={1}>
          <Text bold color="green">Ergebnis</Text>
          <Markdown text={event.summary} />
        </Box>
      );
  }
}

function Roster({ members, tick }: { members: Member[]; tick: number }) {
  const teams = [...new Set(members.map((m) => m.team))];
  return (
    <Box flexDirection="row" columnGap={4} flexWrap="wrap">
      {teams.map((team) => (
        <Box key={team} flexDirection="column">
          <Text bold dimColor>{team.toUpperCase()}</Text>
          {members
            .filter((m) => m.team === team)
            .map((m) => {
              const busy = m.status === "thinking" || m.status === "working" || m.status === "waiting";
              const icon = m.status === "waiting" ? ICON.waiting : busy ? SPINNER[tick % SPINNER.length] : ICON[m.status];
              return (
                <Text key={m.name} dimColor={m.status === "done" || m.status === "idle"}>
                  <Text color={m.status === "error" ? "red" : colorOf(m.name)}>
                    {icon} {m.name}
                  </Text>
                  {m.model ? <Text dimColor> · {modelLabel(m.model)}</Text> : null}
                  {busy ? <Text dimColor> {m.note ?? "denkt nach"}</Text> : null}
                  {m.usd > 0 ? <Text dimColor> ${m.usd.toFixed(2)}</Text> : null}
                </Text>
              );
            })}
        </Box>
      ))}
    </Box>
  );
}

/** What agents are writing right now, a few lines each, until the finished text lands in the log. */
function LiveText({ live, width }: { live: Record<string, string>; width: number }) {
  const writing = Object.entries(live).filter(([, text]) => text.trim());
  if (!writing.length) return null;
  return (
    <Box flexDirection="column" marginTop={1}>
      {writing.map(([agent, text]) => {
        const lines = text.trimEnd().split("\n").flatMap((line) => wrap(line, width - 4));
        return (
          <Box key={agent} flexDirection="column">
            <Text color={colorOf(agent)}>✎ {agent} schreibt …</Text>
            {lines.slice(-LIVE_LINES).map((line, i) => (
              <Text key={i} dimColor>{`  ${line}`}</Text>
            ))}
          </Box>
        );
      })}
    </Box>
  );
}

function wrap(line: string, width: number): string[] {
  if (width < 10 || line.length <= width) return [line];
  const out: string[] = [];
  for (let i = 0; i < line.length; i += width) out.push(line.slice(i, i + width));
  return out;
}

function Choices({ choices, onChoose }: { choices: string[]; onChoose: (choice: string) => void }) {
  const [selected, setSelected] = useState(0);
  useInput((input, key) => {
    if (key.leftArrow || key.upArrow) setSelected((s) => (s + choices.length - 1) % choices.length);
    else if (key.rightArrow || key.downArrow) setSelected((s) => (s + 1) % choices.length);
    else if (key.return) onChoose(choices[selected]!);
    else {
      // Number keys pick directly: 1 = first choice.
      const n = Number(input);
      if (n >= 1 && n <= choices.length) onChoose(choices[n - 1]!);
    }
  });
  return (
    <Box columnGap={2} flexWrap="wrap">
      {choices.map((c, i) => (
        <Text key={c} inverse={i === selected} color={i === selected ? "cyan" : undefined}>
          {` ${i + 1} ${c} `}
        </Text>
      ))}
    </Box>
  );
}

function Question({ question, choices, onAnswer }: { question: string; choices?: string[]; onAnswer: (a: string) => void }) {
  return (
    <Box borderStyle="round" borderColor="cyan" flexDirection="column" paddingX={1} marginTop={1}>
      <Text bold>{question}</Text>
      {choices ? <Choices choices={choices} onChoose={onAnswer} /> : <TextInput onSubmit={onAnswer} placeholder="Antwort eingeben, Enter schickt ab" />}
    </Box>
  );
}

function clock(ms: number): string {
  return new Date(ms).toLocaleTimeString("de-AT", { hour: "2-digit", minute: "2-digit" });
}

function elapsed(ms: number): string {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function App({
  initialRequest,
  autoStart,
  start,
  alwaysFull = [],
}: {
  initialRequest?: string;
  autoStart?: boolean;
  start: (request?: string) => void;
  /** Agents whose messages are never shortened, e.g. the moderator: you approve her plan. */
  alwaysFull?: string[];
}) {
  const { exit } = useApp();
  const { columns } = useWindowSize();
  const [log, setLog] = useState<LogEvent[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [asks, setAsks] = useState<Ask[]>([]);
  const [phase, setPhase] = useState("");
  const [finished, setFinished] = useState(false);
  const [startedAt, setStartedAt] = useState<number | null>(initialRequest || autoStart ? Date.now() : null);
  const [tick, setTick] = useState(0);
  const [compact, setCompact] = useState(true);
  const [limitUntil, setLimitUntil] = useState(0);
  const compactRef = useRef(true);
  const nextKey = useRef(0);
  // Deltas arrive per token; they are collected here and drawn on the next spinner tick.
  const live = useRef<Record<string, string>>({});

  useEffect(() => {
    const off = bus.onEvent((event) => {
      switch (event.type) {
        case "delta":
          live.current[event.agent] = (live.current[event.agent] ?? "") + event.text;
          return;
        case "agent":
          if (event.status !== "thinking" && event.status !== "working") delete live.current[event.agent];
          setMembers((ms) => {
            const existing = ms.find((m) => m.name === event.agent);
            if (!existing) return [...ms, { name: event.agent, team: event.team, status: event.status, note: event.note, model: event.model, usd: 0 }];
            return ms.map((m) => (m === existing ? { ...m, status: event.status, note: event.note, model: event.model ?? m.model } : m));
          });
          return;
        case "cost":
          setMembers((ms) => ms.map((m) => (m.name === event.agent ? { ...m, usd: m.usd + event.usd } : m)));
          return;
        case "ask":
          setAsks((a) => [...a, event]);
          return;
        case "limit":
          setLimitUntil((u) => Math.max(u, event.until));
          return;
        case "say":
        case "tool":
          // The text so far is now complete (say) or the agent moved on to a tool.
          delete live.current[event.agent];
          break;
        case "phase":
          setPhase(event.phase);
          break;
        case "finished":
          setFinished(true);
          break;
      }
      const isCompact = compactRef.current && !(event.type === "say" && alwaysFull.includes(event.agent));
      setLog((l) => [...l, { ...event, key: nextKey.current++, compact: isCompact }]);
    });
    if (initialRequest || autoStart) start(initialRequest);
    return off;
  }, []);

  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 100);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    if (finished) setTimeout(exit, 100);
  }, [finished]);

  useInput((_input, key) => {
    if (!key.tab) return;
    compactRef.current = !compactRef.current;
    setCompact(compactRef.current);
    bus.emitEvent({ type: "info", text: compactRef.current ? "Ansicht: kompakt" : "Ansicht: alles" });
  });

  const total = members.reduce((sum, m) => sum + m.usd, 0);
  const current = asks[0];

  return (
    <>
      <Static items={log}>{(event) => <LogLine key={event.key} event={event} />}</Static>
      {!finished && (
        <Box flexDirection="column" marginTop={1}>
          {startedAt !== null && <LiveText live={{ ...live.current }} width={columns} />}
          <Box columnGap={2} marginTop={1}>
            <Text bold color="black" backgroundColor="cyan"> hivemind </Text>
            {phase ? <Text bold>{phase}</Text> : null}
            {startedAt !== null ? <Text dimColor>{elapsed(Date.now() - startedAt)}</Text> : null}
            {total > 0 ? <Text color="green">${total.toFixed(2)}</Text> : null}
            <Text dimColor>Tab: {compact ? "alles zeigen" : "kompakt"} · Strg+C bricht ab</Text>
          </Box>
          {limitUntil > Date.now() && (
            <Text color="yellow">
              ⏸ Nutzungslimit erreicht. Es geht um {clock(limitUntil)} automatisch weiter (noch {elapsed(limitUntil - Date.now())}).
            </Text>
          )}
          {members.length > 0 && <Roster members={members} tick={tick} />}
          {startedAt === null ? (
            <Question
              question="Was soll das Team bauen?"
              onAnswer={(request) => {
                setStartedAt(Date.now());
                start(request);
              }}
            />
          ) : current ? (
            <Question
              key={current.id}
              question={current.question}
              choices={current.choices}
              onAnswer={(answer) => {
                bus.emitEvent({ type: "info", text: `${current.question.split("\n")[0]} → ${answer}` });
                setAsks((a) => a.slice(1));
                bus.answer(current.id, answer);
              }}
            />
          ) : (
            <Box marginTop={1}>
              <TextInput onSubmit={(text) => bus.emitEvent({ type: "note", text })} placeholder="Nachricht ans Team, Enter schickt ab" />
            </Box>
          )}
        </Box>
      )}
    </>
  );
}
