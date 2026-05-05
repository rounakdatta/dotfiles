{ config
, pkgs
, lib
, ...
}:
let
  homeDir = config.home.homeDirectory;
  claudeWrapperScript = ''
    set -euo pipefail

    REAL_CLAUDE="''${CLAUDE_REAL_BINARY:-/opt/homebrew/bin/claude}"

    case "''${1:-}" in
      -h | --help | -v | --version | auth | auto-mode | doctor | install | mcp | plugin | plugins | setup-token | update | upgrade)
        exec "$REAL_CLAUDE" "$@"
        ;;
    esac

    for arg in "$@"; do
      case "$arg" in
        --bare)
          exec "$REAL_CLAUDE" "$@"
          ;;
      esac
    done

    if [ "''${CLAUDE_HIERARCHICAL_SKILLS_DISABLE:-}" = "1" ]; then
      exec "$REAL_CLAUDE" "$@"
    fi

    if [ ! -x "$REAL_CLAUDE" ]; then
      printf 'claude wrapper: real Claude binary not executable: %s\n' "$REAL_CLAUDE" >&2
      exit 127
    fi

    canonical_dir() {
      (
        cd "$1" 2>/dev/null && pwd -P
      )
    }

    HOME_REAL="$(canonical_dir "''${HOME:-.}" || printf '%s\n' "''${HOME:-}")"
    PWD_REAL="$(pwd -P)"

    ancestor_skill_dirs=()
    current="$PWD_REAL"

    while [ "$current" != "/" ]; do
      if [ -n "$HOME_REAL" ] && [ "$current" = "$HOME_REAL" ]; then
        break
      fi

      skill_dir="$current/.claude/skills"
      if [ -d "$skill_dir" ]; then
        ancestor_skill_dirs+=("$skill_dir")
      fi

      parent="$(dirname "$current")"
      if [ "$parent" = "$current" ]; then
        break
      fi
      current="$parent"
    done

    # Drop the closest ancestor: Claude already loads it natively as project-scope skills.
    # The wrapper only contributes the ancestors *above* it, which Claude wouldn't discover.
    if [ "''${#ancestor_skill_dirs[@]}" -gt 0 ]; then
      ancestor_skill_dirs=("''${ancestor_skill_dirs[@]:1}")
    fi

    if [ "''${#ancestor_skill_dirs[@]}" -eq 0 ]; then
      if [ "''${CLAUDE_HIERARCHICAL_SKILLS_PRINT:-}" = "1" ]; then
        printf 'real=%s\n' "$REAL_CLAUDE"
        printf 'overlay=\n'
        printf 'skills=0\n'
        printf 'argv:'
        printf ' %q' "$REAL_CLAUDE" "$@"
        printf '\n'
        exit 0
      fi
      exec "$REAL_CLAUDE" "$@"
    fi

    overlay_hash="$(printf '%s' "$PWD_REAL" | sha256sum | cut -d ' ' -f 1 | cut -c 1-16)"
    overlay_parent="$HOME/.cache/claude-skill-overlays"
    overlay_root="$overlay_parent/$overlay_hash.$$"
    overlay_skills="$overlay_root/skills"
    plugin_manifest="$overlay_root/.claude-plugin/plugin.json"

    mkdir -p "$overlay_parent"
    # Best-effort prune of orphaned per-session overlays older than a week.
    find "$overlay_parent" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true

    mkdir -p "$overlay_skills"
    mkdir -p "$(dirname "$plugin_manifest")"
    printf '%s\n' \
      '{' \
      '  "name": "hierarchical-skills",' \
      '  "version": "0.1.0",' \
      '  "author": {' \
      '    "name": "dotfiles"' \
      '  },' \
      '  "description": "Session-only inherited skills assembled by the dotfiles Claude wrapper"' \
      '}' > "$plugin_manifest"

    declare -A seen_skills=()
    selected_count=0

    shopt -s nullglob
    for skill_dir in "''${ancestor_skill_dirs[@]}"; do
      for skill_path in "$skill_dir"/*; do
        [ -d "$skill_path" ] || [ -L "$skill_path" ] || continue
        [ -f "$skill_path/SKILL.md" ] || continue

        skill_name="$(basename "$skill_path")"
        if [ -n "''${seen_skills[$skill_name]+x}" ]; then
          continue
        fi

        target="$overlay_skills/$skill_name"
        ln -sfn "$(realpath "$skill_path")" "$target"
        seen_skills["$skill_name"]=1
        selected_count=$((selected_count + 1))
      done
    done
    shopt -u nullglob

    if [ "$selected_count" -eq 0 ]; then
      rm -rf "$overlay_root"
      if [ "''${CLAUDE_HIERARCHICAL_SKILLS_PRINT:-}" = "1" ]; then
        printf 'real=%s\n' "$REAL_CLAUDE"
        printf 'overlay=\n'
        printf 'skills=0\n'
        printf 'argv:'
        printf ' %q' "$REAL_CLAUDE" "$@"
        printf '\n'
        exit 0
      fi
      exec "$REAL_CLAUDE" "$@"
    fi

    if [ "''${CLAUDE_HIERARCHICAL_SKILLS_DEBUG:-}" = "1" ]; then
      printf 'claude wrapper: inherited skill overlay: %s\n' "$overlay_root" >&2
      printf 'claude wrapper: ancestor skill dirs:\n' >&2
      printf '  %s\n' "''${ancestor_skill_dirs[@]}" >&2
    fi

    if [ "''${CLAUDE_HIERARCHICAL_SKILLS_PRINT:-}" = "1" ]; then
      printf 'real=%s\n' "$REAL_CLAUDE"
      printf 'overlay=%s\n' "$overlay_root"
      printf 'skills=%s\n' "$selected_count"
      find "$overlay_skills" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print | sort
      printf 'argv:'
      printf ' %q' "$REAL_CLAUDE" --plugin-dir "$overlay_root" "$@"
      printf '\n'
      exit 0
    fi

    exec "$REAL_CLAUDE" --plugin-dir "$overlay_root" "$@"
  '';
  claudeWrapper = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
    ];
    text = claudeWrapperScript;
  };

  # Claude Code settings as a Nix attrset for better maintainability
  claudeSettings = {
    autoUpdaterStatus = "disabled";
    cleanupPeriodDays = 99999;
    alwaysThinkingEnabled = true;
    statusLine = {
      type = "command";
      command = "bash -c 'basename $(dirname $(pwd))/$(basename $(pwd)); git branch --show-current 2>/dev/null | xargs -I{} echo \" ({})\" || true; echo -n \" | \"; npx ccusage@latest statusline' | tr -d '\\n'";
    };
    env = {
      CLAUDE_CODE_EFFORT_LEVEL = "max";
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
      # playwright = {
      #   command = "npx";
      #   args = [
      #     "@playwright/mcp@latest"
      #     "--extension"
      #   ];
      #   env = {
      #     # I think this is ok to be pubic, it's local to my browser anyway
      #     PLAYWRIGHT_MCP_EXTENSION_TOKEN = "7-yFGyEzSGhYDUCvdQXnZ0fzgEr0g2HuTyMhuWKgiLI";
      #   };
      # };
      bash-history = {
        command = "bunx";
        args = [
          "github:nitsanavni/bash-history-mcp"
          "mcp"
        ];
      };
      android-remote-control = {
        command = "npx";
        args = [
          "-y"
          "mcp-remote@latest"
          "http://roundroid:8080/mcp"
          "--allow-http"
          "--header"
          "Authorization: Bearer "
        ];
      };
      google-maps = {
        command = "bash";
        args = [
          "-c"
          ''
            exec env GOOGLE_MAPS_API_KEY="$(pass show api-keys/google-maps)" \
              npx -y @cablate/mcp-google-map --stdio
          ''
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
  home.packages = lib.optionals pkgs.stdenv.isDarwin [
    claudeWrapper
  ];

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
