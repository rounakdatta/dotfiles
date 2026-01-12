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

  # Create .mcp.json at the dotfiles project root for MCP server configuration
  # This is a static config file that won't interfere with dynamic ~/.claude.json
  home.file."dotfiles/.mcp.json" = {
    text = builtins.toJSON mcpConfig;
  };

  # Ensure the .claude directory has correct permissions
  home.activation.createClaudeDirectory = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p ${config.home.homeDirectory}/.claude
    chmod 700 ${config.home.homeDirectory}/.claude
  '';

  # Intelligently merge MCP servers into ~/.claude.json
  # This preserves all dynamic state while updating only the mcpServers section
  home.activation.mergeMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_JSON="${config.home.homeDirectory}/.claude.json"

    # Only proceed if jq is available
    if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
      if [ -f "$CLAUDE_JSON" ]; then
        # Backup the original file
        cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak"

        # Merge mcpServers section, preserving everything else
        ${pkgs.jq}/bin/jq --argjson newServers '${builtins.toJSON mcpConfig.mcpServers}' \
          '.mcpServers = $newServers' \
          "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"

        echo "✓ Merged MCP servers into ~/.claude.json"
      else
        # If file doesn't exist yet, create it with minimal structure
        echo '{"mcpServers":${builtins.toJSON mcpConfig.mcpServers}}' | ${pkgs.jq}/bin/jq '.' > "$CLAUDE_JSON"
        echo "✓ Created ~/.claude.json with MCP servers"
      fi
    else
      echo "⚠ jq not found, skipping MCP server merge"
    fi
  '';
}
