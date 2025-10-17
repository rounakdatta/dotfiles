{ config, pkgs, lib, ... }:
let
  # Claude Code settings as a Nix attrset for better maintainability
  claudeSettings = {
    alwaysThinkingEnabled = true;
    statusLine = {
      type = "command";
      command = "npx ccusage@latest statusline";
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
}
