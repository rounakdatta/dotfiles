{ config, lib, ... }:

# What every host running a Paseo daemon here offers its agents: Opus 5.5 at
# max effort, and the profiles that run each provider unattended. It merges
# with whatever the host declares itself (hosts/<host>/home.nix).
lib.mkIf config.programs.paseo.enable {
  programs.paseo.settings = {
    # Opus 5.5 at Max effort unless an agent says otherwise — the Paseo half
    # of CLAUDE_CODE_EFFORT_LEVEL=max, which Paseo overrides with the agent's
    # own thinking level. additionalModels updates Paseo's built-in entry in
    # place (the context window and everything else not named here survive),
    # but a model's thinkingOptions replace its list wholesale, so this is the
    # full list Paseo 0.10.2 ships for Opus 5.5 with the default moved from
    # Medium to Max. Re-check it when Paseo adds a level.
    #
    # The other half of "max + bypass" cannot be said in config: Paseo
    # hardcodes Claude's default mode to Auto. On festie, agentfest's
    # paseo.claudeDefaultMode chart value moves it to Bypass; trueswiftie
    # keeps Auto, with the profile below one tap away.
    agents.providers.claude.additionalModels = [
      {
        id = "claude-opus-5-5";
        label = "Opus 5.5";
        description = "Opus 5.5 · Latest release";
        isDefault = true;
        thinkingOptions = [
          { id = "low"; label = "Low"; }
          { id = "medium"; label = "Medium"; }
          { id = "high"; label = "High"; }
          { id = "xhigh"; label = "Extra High"; }
          { id = "max"; label = "Max"; isDefault = true; }
          { id = "ultracode"; label = "Ultra Code"; }
        ];
      }
    ];

    # One tap back to the unattended defaults after trying something else,
    # and what an orchestrating agent reads before launching a worker.
    daemon.agentProfiles = [
      {
        id = "claude-max-bypass";
        name = "Claude · Max · Bypass";
        provider = "claude";
        model = "claude-opus-5-5";
        modeId = "bypassPermissions";
        thinkingOptionId = "max";
        notes = "Opus 5.5 at max effort with no permission prompts. Use for work that should run to completion unattended.";
      }
      # Antigravity needs no profile: full access is its only mode.
      {
        id = "codex-full-access";
        name = "Codex · Full Access";
        provider = "codex";
        modeId = "full-access";
        notes = "Codex with no approval prompts and no sandbox, for work that should run to completion unattended. Model and effort are Codex's defaults for the signed-in account.";
      }
      {
        id = "opencode-build-auto";
        name = "OpenCode · Build · Auto-accept";
        provider = "opencode";
        modeId = "build";
        featureValues.auto_accept = true;
        notes = "OpenCode in Build mode with every permission prompt approved, for work that should run to completion unattended. The model is whichever one OpenCode is signed in to.";
      }
    ];
  };
}
