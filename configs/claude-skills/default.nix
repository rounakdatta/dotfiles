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
        EXTERNAL_CACHE_DIR="$HOME/.cache/agent-smith-externals"
        GENERATED_SKILLS_DIR="$HOME/.cache/agent-smith-generated-skills"
        MANAGED_LINKS_FILE="$HOME/.cache/agent-smith-managed-links"
        JQ_BIN="${pkgs.jq}/bin/jq"

        mkdir -p "$SKILLS_DIR"
        mkdir -p "$EXTERNAL_CACHE_DIR"
        mkdir -p "$GENERATED_SKILLS_DIR"
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

        # A skill is any directory containing skill.json or SKILL.md.
        while IFS= read -r skill_dir; do
          manifest="$skill_dir/skill.json"
          skill_name="$(basename "$skill_dir")"
          resolved_skill_dir="$skill_dir"

          enabled="true"
          destinations="$SKILLS_DIR"
          source=""

          # Optional skill metadata:
          # {
          #   "enabled": true,
          #   "destinations": ["~/.claude/skills", "~/work/byoc/.claude/skills"],
          #   "source": "https://github.com/owner/repo/tree/main/path/to/skill"
          # }
          if [ -f "$manifest" ]; then
            enabled="$("$JQ_BIN" -r '.enabled // true' "$manifest" 2>/dev/null || echo true)"
            if [ "$enabled" != "true" ]; then
              continue
            fi
            destinations="$("$JQ_BIN" -r '(.destinations // ["~/.claude/skills"])[]' "$manifest" 2>/dev/null || echo "~/.claude/skills")"
            source="$("$JQ_BIN" -r '.source // empty' "$manifest" 2>/dev/null || true)"
          fi

          if [ -n "$source" ]; then
            case "$source" in
              https://github.com/*/tree/*)
                repo_path="''${source#https://github.com/}"
                repo_path="''${repo_path%%/tree/*}"
                ref_and_subpath="''${source#https://github.com/$repo_path/tree/}"
                ref="''${ref_and_subpath%%/*}"
                subpath="''${ref_and_subpath#"$ref"/}"
                repo_url="https://github.com/''${repo_path}.git"
                repo_cache_dir="$EXTERNAL_CACHE_DIR/$(printf '%s' "''${repo_path}" | tr '/' '_')"

                if [ ! -d "$repo_cache_dir/.git" ]; then
                  git clone -b "$ref" "$repo_url" "$repo_cache_dir"
                else
                  git -C "$repo_cache_dir" fetch origin "$ref"
                  git -C "$repo_cache_dir" checkout "$ref" || true
                  git -C "$repo_cache_dir" pull --ff-only origin "$ref" || true
                fi

                resolved_skill_dir="$repo_cache_dir/''${subpath}"
                ;;
              *)
                echo "Unsupported skill source for $skill_name: $source"
                continue
                ;;
            esac
          fi

          if [ ! -f "$resolved_skill_dir/SKILL.md" ]; then
            echo "Skipping $skill_name because SKILL.md is missing at $resolved_skill_dir"
            continue
          fi

          if [ -n "$source" ]; then
            generated_skill_dir="$GENERATED_SKILLS_DIR/$skill_name"
            rm -rf "$generated_skill_dir"
            mkdir -p "$generated_skill_dir"
            cp -R "$resolved_skill_dir"/. "$generated_skill_dir"/

            skill_md="$generated_skill_dir/SKILL.md"
            rewritten_skill_md="$generated_skill_dir/SKILL.md.tmp"
            awk -v skill_name="$skill_name" '
              NR == 1 && $0 == "---" { in_frontmatter = 1; print; next }
              in_frontmatter && $1 == "name:" && !rewritten {
                print "name: " skill_name
                rewritten = 1
                next
              }
              in_frontmatter && $0 == "---" {
                if (!rewritten) {
                  print "name: " skill_name
                  rewritten = 1
                }
                print
                in_frontmatter = 0
                next
              }
              { print }
            ' "$skill_md" > "$rewritten_skill_md"
            mv "$rewritten_skill_md" "$skill_md"

            resolved_skill_dir="$generated_skill_dir"
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
            ln -sfn "$resolved_skill_dir" "$target"
            echo "$target" >> "$MANAGED_LINKS_FILE"
          done <<EOF
        $destinations
        EOF
        done <<EOF
        $(find "$CACHE_DIR" \( -type f -name 'skill.json' -o -type f -name 'SKILL.md' \) -print0 | xargs -0 -I{} dirname "{}" | sort -u)
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
