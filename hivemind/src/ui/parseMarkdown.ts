/** A tiny Markdown parser for agent messages: enough to look good in a terminal, nothing more. */

export interface Span {
  text: string;
  bold?: boolean;
  italic?: boolean;
  code?: boolean;
  link?: string;
}

export type Block =
  | { kind: "heading"; level: number; spans: Span[] }
  | { kind: "paragraph"; spans: Span[] }
  | { kind: "item"; depth: number; marker: string; spans: Span[] }
  | { kind: "quote"; spans: Span[] }
  | { kind: "code"; lang: string; lines: string[] }
  /** First row is the header. Cells are already split, with `\|` unescaped. */
  | { kind: "table"; rows: string[][] }
  | { kind: "rule" }
  | { kind: "blank" };

const INLINE = /(`[^`\n]+`)|(\*\*[^*\n]+\*\*|__[^_\n]+__)|(\*[^*\s][^*\n]*\*|(?<![\w])_[^_\s][^_\n]*_(?![\w]))|(\[[^\]\n]+\]\([^)\s]+\))/g;

export function parseInline(text: string): Span[] {
  const spans: Span[] = [];
  let last = 0;
  for (const match of text.matchAll(INLINE)) {
    if (match.index > last) spans.push({ text: text.slice(last, match.index) });
    const [whole, code, bold, italic, link] = match;
    if (code) spans.push({ text: code.slice(1, -1), code: true });
    else if (bold) spans.push(...parseInline(bold.slice(2, -2)).map((s) => ({ ...s, bold: true })));
    else if (italic) spans.push(...parseInline(italic.slice(1, -1)).map((s) => ({ ...s, italic: true })));
    else if (link) {
      const [, label, url] = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(link)!;
      spans.push({ text: label!, link: url });
    } else spans.push({ text: whole });
    last = match.index + whole.length;
  }
  if (last < text.length) spans.push({ text: text.slice(last) });
  return spans;
}

/** "| a | b \| c |" → ["a", "b | c"] */
function splitRow(line: string): string[] {
  const inner = line.trim().replace(/^\|/, "").replace(/(?<!\\)\|$/, "");
  return inner.split(/(?<!\\)\|/).map((cell) => cell.trim().replace(/\\\|/g, "|"));
}

export function parseMarkdown(markdown: string): Block[] {
  const blocks: Block[] = [];
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    const fence = /^\s*(```|~~~)\s*([\w+-]*)/.exec(line);
    if (fence) {
      const code: string[] = [];
      for (i++; i < lines.length && !lines[i]!.trimStart().startsWith(fence[1]!); i++) code.push(lines[i]!);
      blocks.push({ kind: "code", lang: fence[2] ?? "", lines: code });
      continue;
    }
    if (/^\s*\|/.test(line)) {
      const rows: string[][] = [];
      for (; i < lines.length && /^\s*\|/.test(lines[i]!); i++) {
        // The |---|---| separator row only matters to Markdown, not to readers.
        if (!/^\s*\|[\s:|-]+\|\s*$/.test(lines[i]!)) rows.push(splitRow(lines[i]!));
      }
      i--;
      blocks.push({ kind: "table", rows });
      continue;
    }
    if (!line.trim()) {
      if (blocks.at(-1)?.kind !== "blank") blocks.push({ kind: "blank" });
      continue;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      blocks.push({ kind: "heading", level: heading[1]!.length, spans: parseInline(heading[2]!) });
      continue;
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
      blocks.push({ kind: "rule" });
      continue;
    }
    const item = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(line);
    if (item) {
      const bullet = /[-*+]/.test(item[2]!);
      blocks.push({ kind: "item", depth: Math.floor(item[1]!.length / 2), marker: bullet ? "•" : item[2]!, spans: parseInline(item[3]!) });
      continue;
    }
    const quote = /^\s*>\s?(.*)$/.exec(line);
    if (quote) {
      blocks.push({ kind: "quote", spans: parseInline(quote[1]!) });
      continue;
    }
    blocks.push({ kind: "paragraph", spans: parseInline(line) });
  }
  while (blocks[0]?.kind === "blank") blocks.shift();
  while (blocks.at(-1)?.kind === "blank") blocks.pop();
  return blocks;
}
