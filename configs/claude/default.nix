{ config
, pkgs
, lib
, ...
}:
let
  # Claude Code settings as a Nix attrset for better maintainability
  claudeSettings = {
    cleanupPeriodDays = 99999;
    alwaysThinkingEnabled = true;
    statusLine = {
      type = "command";
      command = "npx ccusage@latest statusline";
    };
    hooks = {
      PostToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "bunx github:nitsanavni/bash-history-mcp hook";
            }
          ];
        }
      ];
    };
  };

  # MCP servers configuration - separate from settings
  mcpConfig = {
    mcpServers = {
      playwright = {
        command = "npx";
        args = [
          "@playwright/mcp@latest"
          "--extension"
        ];
        env = {
          # I think this is ok to be pubic, it's local to my browser anyway
          PLAYWRIGHT_MCP_EXTENSION_TOKEN = "wASkRXZOFCIn7QoeT2KiO7e8hj7dEV7I-K7vfl4gLjU";
        };
      };
      bash-history = {
        command = "bunx";
        args = [
          "github:nitsanavni/bash-history-mcp"
          "mcp"
        ];
      };
    };
  };
in
{
  # Create ~/.claude directory and settings.json
  home.file.".claude/settings.json" = {
    text = builtins.toJSON claudeSettings;
  };

  # Ensure the .claude directory has correct permissions
  home.activation.createClaudeDirectory = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p ${config.home.homeDirectory}/.claude
    chmod 700 ${config.home.homeDirectory}/.claude
  '';

  # Merge MCP servers into ~/.claude.json, preserving all other state
  home.activation.mergeMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_JSON="${config.home.homeDirectory}/.claude.json"

    if [ -f "$CLAUDE_JSON" ]; then
      ${pkgs.jq}/bin/jq --argjson newServers '${builtins.toJSON mcpConfig.mcpServers}' \
        '.mcpServers = $newServers' \
        "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
    else
      echo '{"mcpServers":${builtins.toJSON mcpConfig.mcpServers}}' | ${pkgs.jq}/bin/jq '.' > "$CLAUDE_JSON"
    fi
  '';
}
