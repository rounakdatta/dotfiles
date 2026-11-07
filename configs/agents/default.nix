{ config, lib, pkgs, ... }:

# Codex, OpenCode and Antigravity, given what Claude Code has on this machine:
# its MCP servers, its skills and its instructions. Claude Code's config stays
# the one source (configs/claude, configs/claude-skills); this points the
# other agents at it, in each one's own terms.
#
#   MCP           Codex: the agent-mcp Paseo plugin adds the servers as each
#                 agent opens (configs/paseo, hosts/festie). OpenCode: the
#                 `mcp` of <dir>/opencode.json for each declared directory,
#                 which it finds from anywhere below. Antigravity: its one
#                 global mcp_config.json, every server behind
#                 `agent-mcp-run --scoped`.
#   skills        OpenCode reads .claude/skills itself. Codex and Antigravity
#                 get each skill linked where they look (below).
#   instructions  AGENTS.md beside each CLAUDE.md (configs/claude-skills).
#
# A bearer token never lands in any of these files: whatever needs one runs
# the same pass-backed helper Claude Code does, when the server starts.
let
  cfg = config.programs.agentToolchain;

  # Written by configs/claude, from the inventory Claude Code is configured by.
  inventory = "${config.xdg.configHome}/agent-mcp/inventory.json";

  launcher = pkgs.writeShellApplication {
    name = "agent-mcp-run";
    runtimeInputs = with pkgs; [ coreutils jq mcp-proxy ];
    text = builtins.readFile ./agent-mcp-run.sh;
  };
  launcherBin = "${launcher}/bin/agent-mcp-run";
in
{
  options.programs.agentToolchain.enable = lib.mkEnableOption
    "Claude Code's MCP servers, skills and instructions for Codex, OpenCode and Antigravity";

  config = lib.mkIf cfg.enable {
    home.packages = [ launcher ];

    home.activation.agentToolchain = lib.hm.dag.entryAfter
      # linkGeneration explicitly: home-manager breaks ties by name, and
      # without it this entry, and the agent-smith clone it waits for, sorted
      # before the relink, so a failing clone left every link pointing into
      # the previous image's store, and this read stale links.
      [ "linkGeneration" "writeProjectLocalMcpServers" "syncPrivateSkills" "syncClaudeDocs" ]
      ''
        JQ="${pkgs.jq}/bin/jq"
        INVENTORY="${inventory}"
        MANAGED="$HOME/.cache/agent-toolchain-managed-links"

        # merge_json <file> <update> <fresh> <value>: applies a jq update with
        # $v bound to the value, or writes the fresh document where the file is
        # missing or empty. One jq cannot parse (OpenCode and agy both accept
        # comments) is left as it was, and said so.
        merge_json() {
          if [ -s "$1" ]; then
            if "$JQ" --argjson v "$4" "$2" "$1" >"$1.tmp"; then
              mv "$1.tmp" "$1"
            else
              rm -f "$1.tmp"
              echo "agent toolchain: could not parse $1, so left it as it was" >&2
            fi
          else
            "$JQ" -n --argjson v "$4" "$3" >"$1"
          fi
        }

        if [ ! -f "$INVENTORY" ]; then
          echo "agent toolchain: no MCP inventory at $INVENTORY, so no MCP servers for Codex, OpenCode or Antigravity" >&2
        else
          # OpenCode: replaced wholesale, like Claude Code's .mcp.json.
          while IFS= read -r dir; do
            mkdir -p "$dir"
            if servers="$("$JQ" -c --arg dir "$dir" --arg launcher "${launcherBin}" -f ${./opencode-mcp.jq} "$INVENTORY")"; then
              merge_json "$dir/opencode.json" '.mcp = $v' '{"$schema": "https://opencode.ai/config.json", mcp: $v}' "$servers"
            fi
          done < <("$JQ" -r '.projectLocal[].path' "$INVENTORY")

          # Antigravity.
          mkdir -p "$HOME/.gemini/config"
          if servers="$("$JQ" -c --arg launcher "${launcherBin}" -f ${./antigravity-mcp.jq} "$INVENTORY")"; then
            merge_json "$HOME/.gemini/config/mcp_config.json" '.mcpServers = $v' '{mcpServers: $v}' "$servers"
          fi

          # Codex looks for instructions and skills from a project's root down
          # to the session's directory, the root being the nearest directory
          # with a marker, and never above it. Marking the top declared
          # directories (~/personal, ~/work), and starting Codex with
          # project_root_markers = [".agents-root"] (hosts/festie), lets a
          # session in a repository below ~/work still read ~/work's AGENTS.md
          # and skills, as Claude Code does.
          while IFS= read -r root; do
            touch "$root/.agents-root"
          done < <("$JQ" -r '
            [.projectLocal[].path] as $all
            | $all[] as $p
            | select(any($all[]; . as $q | $p != $q and ($p | startswith($q + "/"))) | not)
            | $p' "$INVENTORY")
        fi

        # Skills. OpenCode reads every .claude/skills from a session's directory
        # up to /, so it needs nothing. Codex and Antigravity read neither
        # ~/.claude/skills nor <dir>/.claude/skills, so each skill there is
        # linked into the directories they do read: ~/.agents/skills and
        # ~/.gemini/config/skills for Claude Code's user skills, and
        # <dir>/.agents/skills beside each <dir>/.claude/skills that agent-smith
        # installs into. A link points at the directory holding the skill's real
        # SKILL.md: Codex skips a SKILL.md that is itself a link, which is how
        # home-manager installs dotfiles' own skills.
        if [ -f "$MANAGED" ]; then
          while IFS= read -r link; do
            if [ -L "$link" ]; then rm -f "$link"; fi
          done <"$MANAGED"
        fi
        mkdir -p "$(dirname "$MANAGED")"
        : >"$MANAGED"

        # mirror_skills <from> <to>...
        mirror_skills() {
          local from="$1" to skill target link
          shift
          [ -d "$from" ] || return 0
          for to in "$@"; do
            mkdir -p "$to"
            for skill in "$from"/*; do
              [ -e "$skill" ] || continue
              if [ -f "$skill/SKILL.md" ]; then
                target="$(dirname "$(readlink -f "$skill/SKILL.md")")"
              else
                # A grouping directory, such as the claude.ai synced skills.
                target="$(readlink -f "$skill")"
              fi
              link="$to/$(basename "$skill")"
              # A real file or directory there is not this one's to replace.
              if [ -e "$link" ] && [ ! -L "$link" ]; then continue; fi
              ln -sfn "$target" "$link"
              echo "$link" >>"$MANAGED"
            done
          done
        }

        mirror_skills "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.gemini/config/skills"
        if [ -f "$HOME/.cache/agent-smith-managed-links" ]; then
          while IFS= read -r skills; do
            case "$skills" in
              "$HOME/.claude/skills") ;;
              */.claude/skills) mirror_skills "$skills" "''${skills%/.claude/skills}/.agents/skills" ;;
            esac
          done < <(sed 's|/[^/]*$||' "$HOME/.cache/agent-smith-managed-links" | sort -u)
        fi
      '';
  };
}
