# Claude Skills

This directory contains skill files that will be deployed to `~/.claude/skills` via Nix home-manager.

## Structure

- Local skills (public, safe to commit) should be placed directly in this directory
- Private skills can be fetched from a private repository (see configuration below)
- Both sources will be merged into `~/.claude/skills` on your system

## Configuration

The skills deployment is configured in `configs/claude-skills/default.nix`.

### Private Skills Repository

To enable fetching additional skills from a private repository:

1. Set `enablePrivateSkills = true` in the configuration
2. Configure the private repository URL (SSH format recommended)
3. Optionally specify a subdirectory within the private repo if skills aren't at the root

Example configuration:
```nix
{
  enablePrivateSkills = true;
  privateSkillsRepo = {
    url = "git@github.com:your-username/private-skills.git";
    ref = "main";
    # Optional: pin to specific commit
    # rev = "abc123def456...";
  };
  # If skills are in a subdirectory of the private repo
  privateSkillsSubdir = "skills";  # or "" for root
}
```

## Skill File Format

Skill files should typically be markdown files (`.md`) that Claude can reference. Name them descriptively:

- `example-skill.md` - A sample skill demonstrating the format
- `coding-standards.md` - Team coding standards
- `project-context.md` - Project-specific context

Feel free to organize with subdirectories as needed.
