#!/usr/bin/env node
// Runs the TypeScript sources directly through tsx, so there is no build step.
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tsx = createRequire(import.meta.url).resolve("tsx/cli");
const { status } = spawnSync(process.execPath, [tsx, join(root, "src", "cli.tsx"), ...process.argv.slice(2)], { stdio: "inherit" });
process.exit(status ?? 1);
