{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-skills;
  localSkills = ./skills;
in
{
  options.programs.claude-skills = {
    enable = lib.mkOption { type = lib.types.bool; default = true; };

    enablePrivate = lib.mkEnableOption "private skills";

    privateRepo = {
      url = lib.mkOption { type = lib.types.str; default = ""; };
      ref = lib.mkOption { type = lib.types.str; default = "main"; };
    };
  };

  config = lib.mkIf cfg.enable {
    # Local skills from dotfiles (nix-managed)
    home.file.".claude/skills" = {
      source = localSkills;
      recursive = true;
    };

    # Private skills via git (activation script)
    home.activation.syncPrivateSkills = lib.mkIf cfg.enablePrivate (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                SKILLS_DIR="$HOME/.claude/skills"
                CACHE_DIR="$HOME/.cache/agent-private-skills"
                MANAGED_LINKS_FILE="$HOME/.cache/agent-private-skills-managed-links"
                JQ_BIN="${pkgs.jq}/bin/jq"

                mkdir -p "$SKILLS_DIR"
                mkdir -p "$(dirname "$MANAGED_LINKS_FILE")"

                if [ ! -d "$CACHE_DIR" ]; then
                  git clone -b ${cfg.privateRepo.ref} ${cfg.privateRepo.url} "$CACHE_DIR"
                else
                  git -C "$CACHE_DIR" pull --ff-only origin ${cfg.privateRepo.ref} || true
                fi

                # Clean only links that this activation previously managed.
                if [ -f "$MANAGED_LINKS_FILE" ]; then
                  while IFS= read -r old_link; do
                    [ -L "$old_link" ] && rm -f "$old_link"
                  done < "$MANAGED_LINKS_FILE"
                fi
                : > "$MANAGED_LINKS_FILE"

                # Discover skills recursively. A skill is any directory containing SKILL.md.
                while IFS= read -r skill_md; do
                  skill_dir="$(dirname "$skill_md")"
                  manifest="$skill_dir/skill.json"
                  skill_name="$(basename "$skill_dir")"

                  enabled="true"
                  destinations="$SKILLS_DIR"

                  # Optional per-skill metadata:
                  # {
                  #   "enabled": true,
                  #   "destinations": ["~/.claude/skills", "~/work/byoc/.claude/skills"]
                  # }
                  if [ -f "$manifest" ]; then
                    enabled="$("$JQ_BIN" -r '.enabled // true' "$manifest" 2>/dev/null || echo true)"
                    if [ "$enabled" != "true" ]; then
                      continue
                    fi

                    destinations="$("$JQ_BIN" -r '(.destinations // ["~/.claude/skills"])[]' "$manifest" 2>/dev/null || echo "~/.claude/skills")"
                  fi

                  while IFS= read -r destination; do
                    [ -n "$destination" ] || continue

                    # Expand "~" to $HOME for destination paths.
                    case "$destination" in
                      "~")
                        destination="$HOME"
                        ;;
                      "~/"*)
                        destination="$HOME/''${destination#"~/"}"
                        ;;
                    esac

                    mkdir -p "$destination"
                    target="$destination/$skill_name"
                    ln -sfn "$skill_dir" "$target"
                    echo "$target" >> "$MANAGED_LINKS_FILE"
                  done <<EOF
        $destinations
        EOF
                done <<EOF
        $(find "$CACHE_DIR" -type f -name SKILL.md)
        EOF
      ''
    );
  };
}
