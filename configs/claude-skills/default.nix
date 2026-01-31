{ config, lib, ... }:

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
        CACHE_DIR="$HOME/.cache/claude-private-skills"

        if [ ! -d "$CACHE_DIR" ]; then
          git clone -b ${cfg.privateRepo.ref} ${cfg.privateRepo.url} "$CACHE_DIR"
        else
          git -C "$CACHE_DIR" pull --ff-only origin ${cfg.privateRepo.ref} || true
        fi

        # Symlink each private skill into ~/.claude/skills/
        for skill in "$CACHE_DIR"/*/; do
          [ -d "$skill" ] || continue
          skill_name=$(basename "$skill")
          ln -sfn "$skill" "$SKILLS_DIR/$skill_name"
        done
      ''
    );
  };
}
