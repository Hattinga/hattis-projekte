import { Box, Text } from "ink";
import { parseInline, parseMarkdown, type Span } from "./parseMarkdown.js";

function Spans({ spans }: { spans: Span[] }) {
  return (
    <>
      {spans.map((s, i) =>
        s.code ? (
          <Text key={i} color="cyan">{s.text}</Text>
        ) : s.link ? (
          <Text key={i} underline color="blue">{s.text}</Text>
        ) : (
          <Text key={i} bold={s.bold} italic={s.italic}>{s.text}</Text>
        ),
      )}
    </>
  );
}

function Table({ rows }: { rows: string[][] }) {
  const [header = [], ...body] = rows;
  return (
    <Box flexDirection="column">
      {body.map((cells, j) => (
        <Box key={j}>
          <Box width={2} flexShrink={0}>
            <Text color="gray">•</Text>
          </Box>
          <Text>
            <Text bold>
              <Spans spans={parseInline(cells[0] ?? "")} />
            </Text>
            {cells.slice(1).map((cell, k) => (
              <Text key={k}>
                <Text dimColor>{k === 0 ? " — " : " · "}{header[k + 1] ? `${header[k + 1]}: ` : ""}</Text>
                <Spans spans={parseInline(cell)} />
              </Text>
            ))}
          </Text>
        </Box>
      ))}
    </Box>
  );
}

const HEADING_COLORS = ["", "cyanBright", "cyan", "white", "white", "white", "white"];

export function Markdown({ text }: { text: string }) {
  return (
    <Box flexDirection="column">
      {parseMarkdown(text).map((block, i) => {
        switch (block.kind) {
          case "heading":
            return (
              <Text key={i} bold underline={block.level === 1} color={HEADING_COLORS[block.level]}>
                <Spans spans={block.spans} />
              </Text>
            );
          case "paragraph":
            return (
              <Text key={i}>
                <Spans spans={block.spans} />
              </Text>
            );
          case "item":
            return (
              <Box key={i} paddingLeft={block.depth * 2}>
                {/* A fixed-width marker column keeps the space after "•" when the text wraps. */}
                <Box width={block.marker.length + 1} flexShrink={0}>
                  <Text color="gray">{block.marker}</Text>
                </Box>
                <Text>
                  <Spans spans={block.spans} />
                </Text>
              </Box>
            );
          case "quote":
            return (
              <Text key={i} dimColor>
                │ <Spans spans={block.spans} />
              </Text>
            );
          case "code":
            return (
              <Box key={i} borderStyle="single" borderColor="gray" borderLeft borderRight={false} borderTop={false} borderBottom={false} paddingLeft={1} flexDirection="column">
                {block.lines.map((line, j) => (
                  <Text key={j} color="greenBright">{line || " "}</Text>
                ))}
              </Box>
            );
          case "table":
            // Terminal tables with long cells wrap into chaos, so each row becomes a list entry:
            // "• first cell — header: cell · header: cell".
            return <Table key={i} rows={block.rows} />;
          case "rule":
            return <Text key={i} dimColor>{"─".repeat(40)}</Text>;
          case "blank":
            return <Text key={i}> </Text>;
        }
      })}
    </Box>
  );
}
