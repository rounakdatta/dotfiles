{ config, lib, pkgs, ... }:

# Codeman's runtime state, declared rather than clicked: which working
# directories it offers, and which permission mode it launches Claude in.
#
# A "case" is just a named working directory Codeman remembers. Cases created
# through the UI live under ~/codeman-cases/<name>, but Codeman can also point a
# case at a folder anywhere on disk, and it records those in
# ~/.codeman/linked-cases.json.
#
# That file is pure runtime state: it is written by `POST /api/cases/link` and
# rewritten on every link/unlink from the UI. On festie it sits on the PVC, so a
# case linked by hand survives restarts — and is lost the moment the machine is
# rebuilt somewhere else, with no trace in any repo explaining what used to be
# there. Declaring the links here is what makes the working directories a
# property of the configuration instead of a property of one volume.
#
# ~/.codeman/settings.json is the same kind of state, and `claudeMode` inside it
# is the single most consequential key on the machine: it decides the permission
# mode of EVERY Claude session started from the web UI, which on festie is all of
# them. Codeman turns it into an explicit CLI flag at spawn time
# (`--dangerously-skip-permissions` or `--permission-mode auto`, see its
# session-cli-builder), and a command-line argument outranks a settings file — so
# this key beats ~/.claude/settings.json's permissions.defaultMode and there is
# no way to see that from the Claude side. It had been set to "auto" from the
# Startup Mode dropdown, a change no repo records and no Claude setting reveals,
# so the machine ran classifier-guarded while the only permission setting anyone
# thought to check said nothing about it either way.
#
# Codeman exposes NO environment variable for it (there is no CODEMAN_* var for
# any settings key), so writing the file is the only way to declare it.

let
  cfg = config.programs.codeman;
  dataDir = "${config.home.homeDirectory}/.codeman";
  linkedCasesFile = "${dataDir}/linked-cases.json";
  settingsFile = "${dataDir}/settings.json";
in
{
  options.programs.codeman = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Manage Codeman's linked-case registry. Only meaningful on a host that
        actually runs Codeman — festie, the agentfest container.
      '';
    };

    linkedCases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { work = "/home/rounak/work"; };
      description = ''
        Case name -> absolute path, merged into ~/.codeman/linked-cases.json.
        Each path is created if missing, mirroring what the link API requires.
      '';
    };

    claudePermissionMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "dangerously-skip-permissions"
        "auto"
        "normal"
        "allowedTools"
      ]);
      default = null;
      example = "dangerously-skip-permissions";
      description = ''
        Value for `claudeMode` in ~/.codeman/settings.json — the permission mode
        Codeman launches every Claude session with. `null` leaves the key alone,
        which means whatever the UI last wrote, falling back to Codeman's own
        default of `dangerously-skip-permissions` when the key is absent.

        Names match Codeman's own vocabulary rather than Claude Code's, because
        this value is written verbatim into Codeman's config. The translation to
        Claude Code's `permissions.defaultMode` spelling lives in configs/claude,
        which derives its value from this one so the two cannot disagree.

        `dangerously-skip-permissions` runs every tool call with no prompt and no
        classifier. Only reasonable on a disposable machine: the Claude Code docs
        are explicit that bypass also skips the protected-path guards on `.git`
        and `.claude`. festie is a container behind Tinyauth, which is the whole
        argument for it — do not carry this to a laptop.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.linkedCases != { }) {
      home.activation.codemanLinkedCases = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          JQ_BIN="${pkgs.jq}/bin/jq"

          mkdir -p "${dataDir}"

          # Each declared path has to exist before Codeman will resolve a case to
          # it; the link API rejects a missing folder outright. Creating them here
          # keeps this module self-contained rather than depending on whichever
          # other activation step happens to run first.
          ${lib.concatMapStringsSep "\n        " (name: ''
          mkdir -p "${cfg.linkedCases.${name}}"
          '') (builtins.attrNames cfg.linkedCases)}

          # Merge, never clobber. Codeman owns this file at runtime, so anything
          # linked from the UI has to survive an activation — only the declared
          # names are asserted. Same shape as configs/claude's
          # mergeGlobalMcpServers, including the tolerance for a corrupt file:
          # a registry we cannot parse is replaced rather than allowed to wedge
          # every case on the machine.
          if [ -f "${linkedCasesFile}" ] && "$JQ_BIN" -e . "${linkedCasesFile}" >/dev/null 2>&1; then
            "$JQ_BIN" --argjson declared '${builtins.toJSON cfg.linkedCases}' \
              '. * $declared' "${linkedCasesFile}" > "${linkedCasesFile}.tmp" \
              && mv "${linkedCasesFile}.tmp" "${linkedCasesFile}"
          else
            printf '%s\n' '${builtins.toJSON cfg.linkedCases}' \
              | "$JQ_BIN" '.' > "${linkedCasesFile}"
          fi
        ) || true
      '';
    })

    (lib.mkIf (cfg.claudePermissionMode != null) {
      home.activation.codemanClaudePermissionMode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        (
          JQ_BIN="${pkgs.jq}/bin/jq"

          mkdir -p "${dataDir}"

          # NOT home.file: Codeman's PUT /api/settings does a read-modify-write
          # with fs.writeFile on this exact path, and writeFile follows a symlink
          # to its target — so a store symlink would make every settings save in
          # the UI fail with EROFS. That is the same trap #92 hit from the other
          # side, where /auto-mode-setup could not persist into a nix-managed
          # ~/.claude/settings.json and re-offered itself on every single boot.
          #
          # Set on EVERY activation, deliberately. The Startup Mode dropdown
          # writes this same key, so a hand-toggle is a runtime experiment that
          # gets reconciled back to this file on the next deploy. That is the
          # point: the drift this fixes was one dropdown nobody could trace.
          #
          # Ordering is safe on the path that matters: agentfest's entrypoint runs
          # home-manager activation (step 2) well before it execs `codeman web`
          # (step 5), so on a boot or a fresh PVC nothing is reading or writing
          # this file while we replace it. Running `home-manager switch` by hand
          # against a LIVE Codeman races its own read-modify-write of the same
          # file; the loser is one settings save, and Codeman re-reads within its
          # 2s cache window, so this is noted rather than locked against.
          if [ ! -s "${settingsFile}" ]; then
            # Fresh PVC: Codeman has never written its settings. A file holding
            # only this key is fine — Codeman merges the rest in on first save,
            # and every other setting it reads has a documented default.
            printf '%s\n' '${builtins.toJSON { claudeMode = cfg.claudePermissionMode; }}' \
              | "$JQ_BIN" '.' > "${settingsFile}"
          elif "$JQ_BIN" -e . "${settingsFile}" >/dev/null 2>&1; then
            "$JQ_BIN" --arg mode '${cfg.claudePermissionMode}' '.claudeMode = $mode' \
              "${settingsFile}" > "${settingsFile}.tmp" \
              && mv "${settingsFile}.tmp" "${settingsFile}"
          else
            # Unlike linked-cases.json above, do NOT replace an unparseable file.
            # This one carries notification, voice and UI state that is tedious to
            # rebuild by hand, and a parse error is far more likely to be a
            # half-finished write than genuine corruption. Warn and leave it:
            # Codeman reads an unparseable settings.json as {} and falls back to
            # its own bypass default, so the mode still lands where we wanted --
            # but by accident, so say so rather than let it pass silently.
            rm -f "${settingsFile}.tmp"
            echo "WARNING: ${settingsFile} is not valid JSON; claudeMode left unset" >&2
          fi
        ) || true
      '';
    })
  ]);
}
