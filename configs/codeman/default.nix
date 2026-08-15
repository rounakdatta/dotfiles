{ config, lib, pkgs, ... }:

# Codeman's case registry, declared rather than clicked.
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

let
  cfg = config.programs.codeman;
  dataDir = "${config.home.homeDirectory}/.codeman";
  linkedCasesFile = "${dataDir}/linked-cases.json";
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
  };

  config = lib.mkIf (cfg.enable && cfg.linkedCases != { }) {
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
  };
}
