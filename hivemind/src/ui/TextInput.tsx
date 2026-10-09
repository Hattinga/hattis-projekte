import { Text, useInput, usePaste } from "ink";
import { useState } from "react";

/** What you typed before, newest last. Shared by every input of this session. */
const history: string[] = [];

/**
 * Single-line input with a cursor: ←/→ move, Pos1/Ende or Strg+A/E jump, ↑/↓ browse earlier
 * answers, Enter sends. Pasted line breaks become spaces.
 */
export function TextInput({ onSubmit, placeholder }: { onSubmit: (value: string) => void; placeholder?: string }) {
  const [value, setValue] = useState("");
  const [cursor, setCursor] = useState(0);
  const [browsing, setBrowsing] = useState(history.length);

  const set = (next: string, at = next.length) => {
    setValue(next);
    setCursor(Math.max(0, Math.min(at, next.length)));
  };
  const insert = (text: string) => set(value.slice(0, cursor) + text + value.slice(cursor), cursor + text.length);

  usePaste((pasted) => insert(pasted.replace(/\r?\n/g, " ")));

  useInput((input, key) => {
    if (key.return) {
      const text = value.trim();
      if (!text) return;
      if (history.at(-1) !== text) history.push(text);
      setBrowsing(history.length);
      set("");
      onSubmit(text);
    } else if (key.leftArrow) setCursor((c) => Math.max(0, c - 1));
    else if (key.rightArrow) setCursor((c) => Math.min(value.length, c + 1));
    else if (key.home || (key.ctrl && input === "a")) setCursor(0);
    else if (key.end || (key.ctrl && input === "e")) setCursor(value.length);
    else if (key.upArrow && browsing > 0) {
      setBrowsing(browsing - 1);
      set(history[browsing - 1]!);
    } else if (key.downArrow && browsing < history.length) {
      setBrowsing(browsing + 1);
      set(history[browsing + 1] ?? "");
    } else if (key.backspace) {
      if (cursor > 0) set(value.slice(0, cursor - 1) + value.slice(cursor), cursor - 1);
    } else if (key.delete) {
      // Many terminals send Delete for the Backspace key, so delete backwards when at the end.
      if (cursor < value.length) set(value.slice(0, cursor) + value.slice(cursor + 1), cursor);
      else if (cursor > 0) set(value.slice(0, cursor - 1), cursor - 1);
    } else if (key.ctrl && input === "u") set("");
    else if (input && !key.ctrl && !key.meta && !key.escape && !key.tab) insert(input);
  });

  if (!value && placeholder) {
    return (
      <Text>
        <Text color="cyan">› </Text>
        <Text inverse> </Text>
        <Text dimColor>{placeholder}</Text>
      </Text>
    );
  }
  return (
    <Text>
      <Text color="cyan">› </Text>
      {value.slice(0, cursor)}
      <Text inverse>{value[cursor] ?? " "}</Text>
      {value.slice(cursor + 1)}
    </Text>
  );
}
