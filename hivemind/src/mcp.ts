import type { McpServerConfig } from "@anthropic-ai/claude-agent-sdk";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import type { Config } from "./config.js";

interface ClaudeJson {
  mcpServers?: Record<string, McpServerConfig>;
  projects?: Record<string, { mcpServers?: Record<string, McpServerConfig> }>;
}

const normalize = (path: string) => resolve(path).replace(/\\/g, "/").replace(/\/$/, "").toLowerCase();

/**
 * Finds an MCP server by name: first in hivemind's config (`mcpServers`), then the way Claude Code
 * itself would see it from `cwd`: local/project scope of the closest folder in ~/.claude.json, then user scope.
 * So a role can say `"mcp": ["Roblox_Studio"]` and get exactly the server you use in Claude Code.
 */
export function findMcpServer(name: string, cwd: string, config: Config): McpServerConfig | undefined {
  if (config.mcpServers?.[name]) return config.mcpServers[name];
  const file = join(homedir(), ".claude.json");
  if (!existsSync(file)) return undefined;
  const claude = JSON.parse(readFileSync(file, "utf8")) as ClaudeJson;
  const here = normalize(cwd);
  const scopes = Object.entries(claude.projects ?? {})
    .filter(([path]) => here === normalize(path) || here.startsWith(`${normalize(path)}/`))
    .sort(([a], [b]) => b.length - a.length);
  for (const [, project] of scopes) {
    if (project.mcpServers?.[name]) return project.mcpServers[name];
  }
  return claude.mcpServers?.[name];
}

export function resolveMcpServers(names: string[], cwd: string, config: Config): Record<string, McpServerConfig> {
  const servers: Record<string, McpServerConfig> = {};
  for (const name of names) {
    const server = findMcpServer(name, cwd, config);
    if (!server) throw new Error(`MCP-Server "${name}" ist weder in der hivemind-Config noch in deinem Claude Code eingerichtet.`);
    servers[name] = server;
  }
  return servers;
}
