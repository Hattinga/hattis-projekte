import assert from "node:assert/strict";
import { test } from "node:test";
import { parseInline, parseMarkdown } from "../src/ui/parseMarkdown.js";

test("inline: bold, italic, code and links", () => {
  assert.deepEqual(parseInline("ein **fetter** und *schräger* Text mit `code` und [Link](https://x.y)"), [
    { text: "ein " },
    { text: "fetter", bold: true },
    { text: " und " },
    { text: "schräger", italic: true },
    { text: " Text mit " },
    { text: "code", code: true },
    { text: " und " },
    { text: "Link", link: "https://x.y" },
  ]);
});

test("inline: code inside bold and snake_case stay intact", () => {
  assert.deepEqual(parseInline("**`calc.js` ändern**"), [{ text: "calc.js", code: true, bold: true }, { text: " ändern", bold: true }]);
  assert.deepEqual(parseInline("die Variable my_var_name"), [{ text: "die Variable my_var_name" }]);
});

test("blocks: headings, lists, quotes, rules", () => {
  const blocks = parseMarkdown("## Plan\n\n- eins\n  - zwei\n1. drei\n> Zitat\n---\nText");
  assert.deepEqual(
    blocks.map((b) => b.kind),
    ["heading", "blank", "item", "item", "item", "quote", "rule", "paragraph"],
  );
  assert.deepEqual(blocks[3], { kind: "item", depth: 1, marker: "•", spans: [{ text: "zwei" }] });
  assert.deepEqual(blocks[4], { kind: "item", depth: 0, marker: "1.", spans: [{ text: "drei" }] });
});

test("blocks: code fences keep their content untouched", () => {
  const blocks = parseMarkdown("vorher\n```ts\nconst a = **b**;\n\n# kein Heading\n```\nnachher");
  assert.deepEqual(blocks[1], { kind: "code", lang: "ts", lines: ["const a = **b**;", "", "# kein Heading"] });
  assert.equal(blocks[2]?.kind, "paragraph");
});

test("blocks: tables drop the separator row", () => {
  const blocks = parseMarkdown("| A | B |\n|---|:-:|\n| 1 | 2 |");
  assert.deepEqual(blocks, [{ kind: "table", lines: ["| A | B |", "| 1 | 2 |"] }]);
});

test("blocks: windows line endings and surrounding blank lines", () => {
  assert.deepEqual(parseMarkdown("\r\n\r\nHallo\r\n\r\n\r\n"), [{ kind: "paragraph", spans: [{ text: "Hallo" }] }]);
});
