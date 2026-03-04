{ config
, pkgs
, lib
, ...
}:
let
  homeDir = config.home.homeDirectory;

  # Claude Code settings as a Nix attrset for better maintainability
  claudeSettings = {
    cleanupPeriodDays = 99999;
    alwaysThinkingEnabled = true;
    statusLine = {
      type = "command";
      command = "bash -c 'basename $(dirname $(pwd))/$(basename $(pwd)); git branch --show-current 2>/dev/null | xargs -I{} echo \" ({})\" || true; echo -n \" | \"; npx ccusage@latest statusline' | tr -d '\\n'";
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

  # Claude Code plugin marketplaces (GitHub repos)
  claudePluginMarketplaces = [
    "thedotmack/claude-mem"
  ];

  # Plugins to install (plugin-name or plugin-name@marketplace-name)
  claudePlugins = [
    "claude-mem"
  ];

  # Single MCP inventory for clarity:
  # - `global` -> merged into ~/.claude.json (user-level)
  # - `projectLocal` -> written into <path>/.mcp.json (directory-level)
  mcpInventory = {
    global = {
      playwright = {
        command = "npx";
        args = [
          "@playwright/mcp@latest"
          "--extension"
        ];
        env = {
          # I think this is ok to be pubic, it's local to my browser anyway
          PLAYWRIGHT_MCP_EXTENSION_TOKEN = "7-yFGyEzSGhYDUCvdQXnZ0fzgEr0g2HuTyMhuWKgiLI";
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

    projectLocal = [
      # Sample project-local MCP profile for ~/personal
      {
        path = "${homeDir}/personal";
        mcpServers = {
          zomato = {
            command = "npx";
            args = [
              "-y"
              "mcp-remote"
              "https://mcp-server.zomato.com/mcp"
            ];
          };
        };
      }
      {
        path = "${homeDir}/work";
        mcpServers = {
          notprod-grafana-lyric = {
            command = "bash";
            args = [
              "-c"
              ''
                GRAFANA_URL="https://notprod-grafana.lyric.tech"
                GRAFANA_SERVICE_ACCOUNT_TOKEN="$(pass show api-keys/notprod-grafana-lyric)"

                exec uvx mcp-grafana \
                  -t stdio \
                  -debug
              ''
            ];
          };
          prod-grafana-lyric = {
            command = "bash";
            args = [
              "-c"
              ''
                GRAFANA_URL="https://prod-grafana.lyric.tech/"
                GRAFANA_SERVICE_ACCOUNT_TOKEN="$(pass show api-keys/prod-grafana-lyric)"

                exec uvx mcp-grafana \
                  -t stdio \
                  -debug
              ''
            ];
          };
        };
      }
    ];
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

  # Install Claude Code plugins declaratively
  home.activation.installClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE="/opt/homebrew/bin/claude"
    if [ -x "$CLAUDE" ]; then
      ${lib.concatMapStringsSep "\n      " (m: ''
        $CLAUDE plugin marketplace add ${m} 2>/dev/null || true
      '') claudePluginMarketplaces}

      ${lib.concatMapStringsSep "\n      " (p: ''
        $CLAUDE plugin install ${p} --scope user 2>/dev/null || true
      '') claudePlugins}
    fi
  '';

  # Merge global MCP servers into ~/.claude.json, preserving all other state
  home.activation.mergeGlobalMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_JSON="${config.home.homeDirectory}/.claude.json"

    if [ -f "$CLAUDE_JSON" ]; then
      ${pkgs.jq}/bin/jq --argjson newServers '${builtins.toJSON mcpInventory.global}' \
        '.mcpServers = $newServers' \
        "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
    else
      echo '{"mcpServers":${builtins.toJSON mcpInventory.global}}' | ${pkgs.jq}/bin/jq '.' > "$CLAUDE_JSON"
    fi
  '';

  # Write project-local MCP servers into each configured <path>/.mcp.json
  home.activation.writeProjectLocalMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    JQ_BIN="${pkgs.jq}/bin/jq"
    ${lib.concatMapStringsSep "\n\n    " (profile: ''
      PROJECT_DIR="${profile.path}"
      PROJECT_MCP_JSON="$PROJECT_DIR/.mcp.json"

      if [ ! -d "$PROJECT_DIR" ]; then
        echo "Skipping local MCP sync for missing directory: $PROJECT_DIR"
      else
        if [ -f "$PROJECT_MCP_JSON" ]; then
          "$JQ_BIN" --argjson newServers '${builtins.toJSON profile.mcpServers}' \
            '.mcpServers = $newServers' \
            "$PROJECT_MCP_JSON" > "$PROJECT_MCP_JSON.tmp" && mv "$PROJECT_MCP_JSON.tmp" "$PROJECT_MCP_JSON"
        else
          echo '{"mcpServers":${builtins.toJSON profile.mcpServers}}' | "$JQ_BIN" '.' > "$PROJECT_MCP_JSON"
        fi
      fi
    '') mcpInventory.projectLocal}
  '';
}
