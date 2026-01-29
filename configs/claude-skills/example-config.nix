# Example configuration for Claude Skills with private repository
#
# To use this configuration, add these settings to your host-specific home.nix
# (e.g., hosts/ninezeroes/home.nix or hosts/trueswiftie/home.nix)

{
  # Basic usage (local skills only - already enabled by default)
  programs.claude-skills.enable = true;

  # Advanced usage: Enable private skills from a private repository
  programs.claude-skills = {
    enable = true;
    enablePrivateSkills = true;

    privateSkillsRepo = {
      # Use SSH format for private repos (requires SSH key authentication)
      url = "git@github.com:your-username/private-skills.git";

      # Branch to fetch from
      ref = "main";

      # Optional: Pin to a specific commit for reproducibility
      # This ensures the exact same skills are fetched every time
      # rev = "abc123def456789...";
    };

    # If your skills are in a subdirectory of the private repo
    # Leave as "" if skills are at the root of the repo
    privateSkillsSubdir = "";  # or "skills" or "claude-skills" etc.
  };
}

# After configuration, your skills will be organized as:
# ~/.claude/skills/
# ├── local/          (from this dotfiles repo - public skills)
# │   ├── README.md
# │   └── example-skill.md
# └── private/        (from private repo - sensitive skills)
#     └── (your private skill files)

# To add local (public) skills:
# - Add .md files to the skills/ directory in this repo
# - They will be automatically deployed to ~/.claude/skills/local/

# To add private skills:
# 1. Create a private Git repository
# 2. Add your skill .md files to it
# 3. Configure the privateSkillsRepo settings above
# 4. Rebuild your home-manager configuration
