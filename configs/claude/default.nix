{ config
, pkgs
, lib
, ...
}:
let
  # Claude Code settings as a Nix attrset for better maintainability
  claudeSettings = {
    alwaysThinkingEnabled = true;
    statusLine = {
      type = "command";
      command = "npx ccusage@latest statusline";
    };
  };

  # all the mcp conigs live here
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
    };
  };
in
{
  # Create ~/.claude directory and settings.json
  home.file.".claude/settings.json" = {
    text = builtins.toJSON claudeSettings;
  };

  # Create ~/.claude/mcp.json for MCP server configuration
  home.file.".claude/mcp.json" = {
    text = builtins.toJSON mcpConfig;
  };

  # Ensure the .claude directory has correct permissions
  home.activation.createClaudeDirectory = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p ${config.home.homeDirectory}/.claude
    chmod 700 ${config.home.homeDirectory}/.claude
  '';
}
