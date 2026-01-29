{ config, lib, ... }:

let
  cfg = config.programs.claude-skills;

  localSkills = ./skills;

  privateSkills = if cfg.enablePrivate then
    builtins.fetchGit ({
      url = cfg.privateRepo.url;
      ref = cfg.privateRepo.ref;
    } // lib.optionalAttrs (cfg.privateRepo.rev != null) {
      rev = cfg.privateRepo.rev;
    })
  else null;

  privateSource = if privateSkills != null && cfg.privateRepo.subdir != "" then
    "${privateSkills}/${cfg.privateRepo.subdir}"
  else privateSkills;
in
{
  options.programs.claude-skills = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    enablePrivate = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    privateRepo = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
      };

      ref = lib.mkOption {
        type = lib.types.str;
        default = "main";
      };

      rev = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      subdir = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !cfg.enablePrivate || cfg.privateRepo.url != "";
      message = "privateRepo.url must be set when enablePrivate is true";
    }];

    home.file.".claude/skills/local" = {
      source = localSkills;
      recursive = true;
    };

    home.file.".claude/skills/private" = lib.mkIf (cfg.enablePrivate && privateSource != null) {
      source = privateSource;
      recursive = true;
    };
  };
}
