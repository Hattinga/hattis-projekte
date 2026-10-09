#!/usr/bin/env node
// Runs the TypeScript sources directly through tsx, so there is no build step.
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tsx = createRequire(import.meta.url).resolve("tsx/cli");
// tsx looks for tsconfig.json in the current folder, which is your project, not hivemind; point it at ours.
const args = [tsx, "--tsconfig", join(root, "tsconfig.json"), join(root, "src", "cli.tsx"), ...process.argv.slice(2)];
const { status } = spawnSync(process.execPath, args, { stdio: "inherit" });
process.exit(status ?? 1);
