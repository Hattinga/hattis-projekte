import { Box, Text } from "ink";
import { parseMarkdown, type Span } from "./parseMarkdown.js";

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
                <Text color="gray">{block.marker} </Text>
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
            return (
              <Box key={i} flexDirection="column">
                {block.lines.map((line, j) => (
                  <Text key={j} bold={j === 0}>{line}</Text>
                ))}
              </Box>
            );
          case "rule":
            return <Text key={i} dimColor>{"─".repeat(40)}</Text>;
          case "blank":
            return <Text key={i}> </Text>;
        }
      })}
    </Box>
  );
}
