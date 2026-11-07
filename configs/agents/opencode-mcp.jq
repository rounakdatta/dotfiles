# One declared directory's MCP servers, the global ones included, as
# OpenCode's `mcp` config. OpenCode reaches plain HTTP servers itself (and
# signs in to an OAuth one with `opencode mcp auth <name>`); one whose bearer
# token comes from pass goes through $launcher, which fetches it.
#
# Input: the inventory configs/claude writes. Args: $dir, $launcher.
def server($name; $e):
  if $e.url then
    if $e.headersHelper then {type: "local", command: [$launcher, $name]}
    else {type: "remote", url: $e.url}
    end
  else
    {type: "local", command: ([$e.command] + ($e.args // []))}
    + (if $e.env then {environment: $e.env} else {} end)
  end;

(.global // {}) + ((.projectLocal[] | select(.path == $dir) | .mcpServers) // {})
| with_entries(.value = server(.key; .value))
