{ config, pkgs, lib, ... }:

let
  cfg = config.programs.claude-skills;

  # Path to local skills in this repo
  localSkillsPath = ../../skills;

  # Fetch private skills if enabled
  privateSkills = if cfg.enablePrivateSkills then
    builtins.fetchGit ({
      url = cfg.privateSkillsRepo.url;
      ref = cfg.privateSkillsRepo.ref;
    } // lib.optionalAttrs (cfg.privateSkillsRepo.rev != null) {
      # If rev is set, use it for pinning to a specific commit
      rev = cfg.privateSkillsRepo.rev;
    })
  else null;

  # Determine the source path for private skills
  privateSkillsSource = if privateSkills != null then
    if cfg.privateSkillsSubdir != "" then
      "${privateSkills}/${cfg.privateSkillsSubdir}"
    else
      privateSkills
  else null;

in
{
  options.programs.claude-skills = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable Claude skills deployment";
    };

    enablePrivateSkills = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to fetch additional skills from a private repository";
    };

    privateSkillsRepo = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "URL of the private skills repository (SSH format recommended: git@github.com:user/repo.git)";
        example = "git@github.com:your-username/private-skills.git";
      };

      ref = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git reference (branch) to fetch from";
      };

      rev = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Specific commit hash to pin to (optional, for reproducibility)";
        example = "abc123def456...";
      };
    };

    privateSkillsSubdir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Subdirectory within the private repo where skills are located (empty string for root)";
      example = "skills";
    };
  };

  config = lib.mkIf cfg.enable {
    # Validate private skills configuration
    assertions = [
      {
        assertion = !cfg.enablePrivateSkills || cfg.privateSkillsRepo.url != "";
        message = "programs.claude-skills.privateSkillsRepo.url must be set when enablePrivateSkills is true";
      }
    ];

    # Deploy local skills from this repo
    home.file.".claude/skills/local" = {
      source = localSkillsPath;
      recursive = true;
    };

    # Deploy private skills if enabled
    home.file.".claude/skills/private" = lib.mkIf (cfg.enablePrivateSkills && privateSkillsSource != null) {
      source = privateSkillsSource;
      recursive = true;
    };

    # Create a nice activation script that reports what was deployed
    home.activation.reportClaudeSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "📚 Claude Skills deployed to ~/.claude/skills/"
      echo "  ✓ Local skills from dotfiles repo"
      ${lib.optionalString cfg.enablePrivateSkills ''
        echo "  ✓ Private skills from ${cfg.privateSkillsRepo.url} (${cfg.privateSkillsRepo.ref})"
      ''}
    '';
  };
}
