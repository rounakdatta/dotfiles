// The MCP servers Claude Code gets on this machine, given to the other agents
// Paseo runs. dotfiles' configs/claude declares them once and writes the
// inventory this reads; Claude Code itself loads them natively (~/.claude.json
// and <dir>/.mcp.json), so it is left alone here.
//
// The servers are added as each agent session opens, never written to Codex's
// or OpenCode's own config. A bearer token is fetched at that moment by the
// same pass-backed helper Claude Code runs (headersHelper), and goes to the
// provider in memory.
import { execFile } from "node:child_process";
import { constants } from "node:fs";
import { access, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import type { PluginServerContext } from "@getpaseo/plugin/server";

const run = promisify(execFile);

const INVENTORY = path.join(homedir(), ".config", "agent-mcp", "inventory.json");

// Codex only. Claude Code reads the same inventory natively, and OpenCode and
// Antigravity get it in their own config (dotfiles configs/agents): Paseo's
// OpenCode adapter starts a dedicated server per session for servers added
// here and fails the agent if any one does not connect, and its Antigravity
// provider takes none.
const PROVIDERS = new Set(["codex"]);

const HELPER_TIMEOUT_MS = 20_000;
const PROBE_TIMEOUT_MS = 8_000;

interface Entry {
  type?: string;
  url?: string;
  headersHelper?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
}

interface Inventory {
  global?: Record<string, Entry>;
  projectLocal?: { path: string; mcpServers: Record<string, Entry> }[];
}

type Server =
  | { type: "stdio"; command: string; args?: string[]; env?: Record<string, string> }
  | { type: "http" | "sse"; url: string; headers?: Record<string, string> };

function within(dir: string, root: string): boolean {
  const relative = path.relative(root, dir);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

// Global servers, plus those of the deepest declared directory containing
// cwd. Claude Code reads <cwd>/.mcp.json only; here an agent working below
// ~/work, in one of its repositories, gets ~/work's servers too.
function serversFor(inventory: Inventory, cwd: string): Record<string, Entry> {
  const profile = (inventory.projectLocal ?? [])
    .filter((candidate) => within(cwd, candidate.path))
    .sort((a, b) => b.path.length - a.path.length)[0];
  return { ...inventory.global, ...profile?.mcpServers };
}

// headersHelper is a store path plus one argument, kept free of quotes on
// purpose (configs/claude), so splitting on whitespace recovers its argv.
async function headersFrom(helper: string): Promise<Record<string, string>> {
  const [command, ...args] = helper.trim().split(/\s+/);
  const { stdout } = await run(command, args, { timeout: HELPER_TIMEOUT_MS });
  const headers: unknown = JSON.parse(stdout);
  if (typeof headers !== "object" || headers === null) throw new Error("helper printed no header object");
  return headers as Record<string, string>;
}

// A server is only handed over once it has answered an MCP initialize: an
// unreachable host, or one that wants OAuth (which this path cannot do), is
// left out rather than left for the agent to time out on.
async function probe(url: string, headers: Record<string, string> = {}): Promise<void> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      ...headers,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 0,
      method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "agent-mcp", version: "1" } },
    }),
    signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
  });
  await response.body?.cancel();
  const session = response.headers.get("mcp-session-id");
  if (session) {
    fetch(url, { method: "DELETE", headers: { ...headers, "mcp-session-id": session } }).catch(() => {});
  }
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
}

async function onPath(command: string): Promise<boolean> {
  const candidates = command.includes("/")
    ? [command]
    : (process.env.PATH ?? "").split(":").filter(Boolean).map((dir) => path.join(dir, command));
  for (const candidate of candidates) {
    try {
      await access(candidate, constants.X_OK);
      return true;
    } catch {}
  }
  return false;
}

async function toServer(entry: Entry): Promise<Server> {
  if (entry.url) {
    const type = entry.type === "sse" ? "sse" : "http";
    const headers = entry.headersHelper ? await headersFrom(entry.headersHelper) : undefined;
    await probe(entry.url, headers);
    return { type, url: entry.url, ...(headers ? { headers } : {}) };
  }
  if (!entry.command) throw new Error("neither url nor command");
  if (!(await onPath(entry.command))) throw new Error(`${entry.command} is not on PATH`);
  return {
    type: "stdio",
    command: entry.command,
    ...(entry.args ? { args: entry.args } : {}),
    ...(entry.env ? { env: entry.env } : {}),
  };
}

export default function contribute(server: PluginServerContext) {
  // Never throws: a failing agent.open.before hook stops the agent opening,
  // so the worst case here is an agent with fewer servers, and the log says
  // which and why.
  return server.addHook("agent.open.before", async ({ request }) => {
    if (!PROVIDERS.has(request.provider) || request.purpose !== "interactive") return request;
    let inventory: Inventory;
    try {
      inventory = JSON.parse(await readFile(INVENTORY, "utf8")) as Inventory;
    } catch (error) {
      console.error(`[agent-mcp] no inventory at ${INVENTORY}: ${String(error)}`);
      return request;
    }
    const wanted = Object.entries(serversFor(inventory, request.cwd));
    const results = await Promise.allSettled(wanted.map(([, entry]) => toServer(entry)));
    const added: string[] = [];
    const skipped: string[] = [];
    results.forEach((result, index) => {
      const name = wanted[index][0];
      if (result.status === "fulfilled") {
        request.mcpServers[name] = result.value;
        added.push(name);
      } else {
        skipped.push(`${name} (${result.reason instanceof Error ? result.reason.message.split("\n")[0] : "failed"})`);
      }
    });
    console.log(
      `[agent-mcp] ${request.provider} in ${request.cwd}: ${added.join(", ") || "none"}` +
        (skipped.length ? `; skipped ${skipped.join("; ")}` : ""),
    );
    return request;
  });
}
