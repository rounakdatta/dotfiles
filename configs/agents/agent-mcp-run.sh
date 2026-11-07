# agent-mcp-run [--scoped] <server>
#
# Starts one server of the MCP inventory that configs/claude writes (the one
# Claude Code is configured from) as a stdio MCP server, for agents whose own
# config can neither fetch a token nor scope a server to a directory:
#
#   - a stdio server runs as declared;
#   - an HTTP server is bridged by mcp-proxy. A bearer token comes from the
#     same pass-backed headersHelper Claude Code runs, and reaches mcp-proxy
#     in its environment (API_ACCESS_TOKEN), never on a command line.
#
# --scoped: serve the server only where Claude Code would have it, the
# inventory's global servers plus those of the deepest declared directory
# containing $PWD (an agent starts its stdio servers in its own working
# directory). Elsewhere it answers as an empty server, so a work server in a
# personal session is absent rather than broken.

inventory="${AGENT_MCP_INVENTORY:-$HOME/.config/agent-mcp/inventory.json}"

scoped=0
if [ "${1:-}" = "--scoped" ]; then
  scoped=1
  shift
fi
name="${1:?usage: agent-mcp-run [--scoped] <server>}"

session=1
if [ "$scoped" = 1 ] && [ -r "/proc/$PPID/cmdline" ]; then
  # agy starts every configured server on each run, `agy models` and
  # `agy --version` included, which Paseo calls to check the provider. On
  # those, real servers only slow the check past Paseo's timeout: answer empty
  # unless the parent is an agent session.
  mapfile -d '' parent <"/proc/$PPID/cmdline"
  case "${parent[1]:-}" in
    models | --version | agent | agents | changelog | help | mcp | plugin | plugins | update | install | remote-control | mic-serve)
      session=0
      ;;
  esac
fi

if [ "$session" = 0 ]; then
  entry=""
elif [ "$scoped" = 1 ]; then
  entry="$(jq -c --arg n "$name" --arg cwd "$PWD" '
    def within($root): $cwd == $root or ($cwd | startswith($root + "/"));
    .global[$n] // (
      [.projectLocal[] | select(.path as $p | within($p))]
      | sort_by(.path | length) | last | .mcpServers[$n]?
    ) // empty' "$inventory")"
else
  entry="$(jq -c --arg n "$name" '
    .global[$n] // ([.projectLocal[].mcpServers[$n] | values] | first) // empty' "$inventory")"
fi

# An MCP server with no tools: answers initialize and tools/list, refuses the
# rest, and ignores notifications.
empty_server() {
  while IFS= read -r line; do
    jq -c --arg n "$name" '
      select(has("id") and .id != null)
      | if .method == "initialize" then
          {jsonrpc: "2.0", id, result: {
            protocolVersion: (.params.protocolVersion // "2025-06-18"),
            capabilities: {tools: {}},
            serverInfo: {name: "\($n) (not used in this directory)", version: "1"}}}
        elif .method == "tools/list" then {jsonrpc: "2.0", id, result: {tools: []}}
        elif .method == "ping" then {jsonrpc: "2.0", id, result: {}}
        else {jsonrpc: "2.0", id, error: {code: -32601, message: "\($n) is not used in this directory"}}
        end' <<<"$line" || true
  done
}

if [ -z "$entry" ]; then
  if [ "$scoped" = 1 ]; then
    empty_server
    exit 0
  fi
  echo "agent-mcp-run: no server named $name in $inventory" >&2
  exit 1
fi

url="$(jq -r '.url // empty' <<<"$entry")"
if [ -n "$url" ]; then
  helper="$(jq -r '.headersHelper // empty' <<<"$entry")"
  if [ -n "$helper" ]; then
    # The helper is a store path plus one argument (configs/claude), so word
    # splitting recovers its argv.
    # shellcheck disable=SC2086
    API_ACCESS_TOKEN="$($helper | jq -r '.Authorization // empty | sub("^Bearer "; "")')"
    if [ -z "$API_ACCESS_TOKEN" ]; then
      echo "agent-mcp-run: $name's headersHelper gave no bearer token" >&2
      exit 1
    fi
    export API_ACCESS_TOKEN
  fi
  exec mcp-proxy --transport streamablehttp --log-level WARNING "$url"
fi

mapfile -d '' argv < <(jq --raw-output0 '.command, (.args // [])[]' <<<"$entry")
while IFS= read -r -d '' pair; do
  export "${pair?}"
done < <(jq --raw-output0 '.env // {} | to_entries[] | "\(.key)=\(.value)"' <<<"$entry")
exec "${argv[@]}"
