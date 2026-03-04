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

    # Sync private repo and link skills based on per-skill metadata.
    home.activation.syncPrivateSkills = lib.mkIf cfg.enablePrivate (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        SKILLS_DIR="$HOME/.claude/skills"
        CACHE_DIR="$HOME/.cache/agent-smith"
        MANAGED_LINKS_FILE="$HOME/.cache/agent-smith-managed-links"
        JQ_BIN="${pkgs.jq}/bin/jq"

        mkdir -p "$SKILLS_DIR"
        mkdir -p "$(dirname "$MANAGED_LINKS_FILE")"

        if [ ! -d "$CACHE_DIR" ]; then
          git clone -b ${cfg.privateRepo.ref} ${cfg.privateRepo.url} "$CACHE_DIR"
        else
          git -C "$CACHE_DIR" pull --ff-only origin ${cfg.privateRepo.ref} || true
        fi

        # Remove only previously managed links.
        if [ -f "$MANAGED_LINKS_FILE" ]; then
          while IFS= read -r old_link; do
            [ -L "$old_link" ] && rm -f "$old_link"
          done < "$MANAGED_LINKS_FILE"
        fi
        : > "$MANAGED_LINKS_FILE"

        # A skill is any directory containing SKILL.md.
        while IFS= read -r skill_md; do
          skill_dir="$(dirname "$skill_md")"
          manifest="$skill_dir/skill.json"
          skill_name="$(basename "$skill_dir")"

          enabled="true"
          destinations="$SKILLS_DIR"

          # Optional skill metadata:
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

    # Sync HOW_TO_*.MD files into destination/CLAUDE.md using frontmatter metadata.
    # Supported metadata:
    # ---
    # enabled: true
    # destinations:
    #   - "~/work/byoc"
    # ---
    home.activation.syncClaudeDocs = lib.mkIf cfg.enablePrivate (
      lib.hm.dag.entryAfter [ "syncPrivateSkills" ] ''
        CACHE_DIR="$HOME/.cache/agent-smith"

        find "$CACHE_DIR" -maxdepth 1 -type f \( -name 'HOW_TO_*.MD' -o -name 'HOW_TO_*.md' \) | sort | while IFS= read -r doc; do
          enabled="true"
          destinations=""

          if [ "$(head -n 1 "$doc")" = "---" ]; then
            frontmatter="$(awk 'NR == 1 && $0 == "---" {in_frontmatter=1; next} in_frontmatter && $0 == "---" {exit} in_frontmatter {print}' "$doc")"
            enabled="$(printf '%s\n' "$frontmatter" | awk -F': *' '$1 == "enabled" {print $2; found=1} END {if (!found) print "true"}')"
            destinations="$(printf '%s\n' "$frontmatter" | awk '/^[[:space:]]*-[[:space:]]*/ {sub(/^[[:space:]]*-[[:space:]]*/, "", $0); gsub(/^"|"$/, "", $0); print}')"
          fi

          if [ "$enabled" != "true" ]; then
            continue
          fi

          body_file="$(mktemp)"
          if [ "$(head -n 1 "$doc")" = "---" ]; then
            awk 'NR == 1 && $0 == "---" {in_frontmatter=1; next} in_frontmatter && $0 == "---" {in_frontmatter=0; next} !in_frontmatter {print}' "$doc" > "$body_file"
          else
            cat "$doc" > "$body_file"
          fi

          while IFS= read -r destination; do
            [ -n "$destination" ] || continue

            case "$destination" in
              "~")
                destination="$HOME"
                ;;
              "~/"*)
                destination="$HOME/''${destination#"~/"}"
                ;;
            esac

            if [ ! -d "$destination" ]; then
              continue
            fi

            cp "$body_file" "$destination/CLAUDE.md"
          done <<EOF
        $destinations
        EOF

          rm -f "$body_file"
        done
      ''
    );
  };
}
