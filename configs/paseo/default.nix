{ config, lib, pkgs, ... }:

# Paseo's host-side state, declared rather than clicked: the defaults every
# client (phone, desktop, CLI) starts an agent with on this machine, the saved
# agent profiles, and the projects in the sidebar. All of it lives with the
# daemon, not the app, which is what makes the phone and the desktop behave
# the same: they read one host's settings.
#
# Two kinds of state, handled differently because Paseo treats them
# differently:
#
#   ~/.paseo/config.json  Paseo's own config file. The daemon rewrites it at
#                         runtime — pairing flips the relay on through it, and
#                         the app saves agent profiles into it — so it is
#                         merged on every activation rather than owned:
#                         declared keys win, everything else is left alone.
#                         NOT home.file, for the reason configs/codeman gives:
#                         a store symlink would turn every save from the app
#                         into EROFS.
#
#   projects              Not config at all. Paseo keeps projects as records
#                         under ~/.paseo/projects, created through its API, so
#                         they are declared here as a list and applied by
#                         `paseo-apply-declared` against the running daemon.
#                         agentfest runs it after every daemon start; anywhere
#                         else, run it by hand once the daemon is up.
#
# Merge rules for lists: `daemon.agentProfiles` and every
# `agents.providers.<id>.additionalModels` merge by `id` — declared entries
# replace their namesakes and come first, and anything created in the app
# survives. Every other value is replaced wholesale, as jq's `*` does.
#
# Nothing here validates the result: the daemon does, at start. An invalid
# key stops Paseo from starting, so try a settings change against a scratch
# daemon (`PASEO_HOME=$(mktemp -d) paseo daemon run`) before shipping it.

let
  cfg = config.programs.paseo;
  paseoHome = "${config.home.homeDirectory}/.paseo";
  configFile = "${paseoHome}/config.json";
  declaredSettings = { version = 1; } // cfg.settings;

  # Both go through store files rather than being spliced into the activation
  # script, so that no quote in a profile's notes can end a shell string early.
  declaredFile = pkgs.writeText "paseo-declared-config.json" (builtins.toJSON declaredSettings);

  # jq program: $declared merged into the file's current contents.
  mergeFile = pkgs.writeText "paseo-merge-config.jq" ''
    def merge_by_id($current; $wanted):
      ($wanted | map(.id)) as $ids
      | $wanted + ($current | map(select(.id as $id | $ids | index($id) | not)));

    . as $current
    | ($current * $declared)
    | if ($declared.daemon.agentProfiles? != null) then
        .daemon.agentProfiles =
          merge_by_id(($current.daemon.agentProfiles // []); $declared.daemon.agentProfiles)
      else . end
    | reduce (($declared.agents.providers // {})
              | to_entries[]
              | select(.value.additionalModels? != null)) as $provider (.;
        .agents.providers[$provider.key].additionalModels =
          merge_by_id(($current.agents.providers[$provider.key].additionalModels // []);
                      $provider.value.additionalModels))
  '';

  applyDeclared = pkgs.writeShellApplication {
    name = "paseo-apply-declared";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      # Applies what configs/paseo declares to the RUNNING daemon on this
      # machine: reloads config.json (agent profiles and provider models are
      # runtime-safe, so no restart), then registers the declared projects.
      # Idempotent: an existing project comes back unchanged.
      #
      # `paseo` is not a dependency of this script on purpose: the machine
      # decides where Paseo comes from (agentfest pins it into ~/.paseo-app).
      if ! command -v paseo >/dev/null 2>&1; then
        echo "paseo-apply-declared: paseo is not installed; nothing to do" >&2
        exit 0
      fi

      if ! paseo reload >/dev/null 2>&1; then
        echo "paseo-apply-declared: 'paseo reload' failed (is the daemon running?)" >&2
      fi

      declared="${config.xdg.configHome}/paseo/projects.json"
      [ -f "$declared" ] || exit 0

      jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$declared" |
        while IFS=$'\t' read -r name path; do
          mkdir -p "$path"
          if ! out="$(paseo project create "$path" --json 2>&1)"; then
            echo "paseo-apply-declared: could not register $name ($path): $out" >&2
            continue
          fi
          id="$(printf '%s' "$out" | jq -r '.projectId')"
          current="$(printf '%s' "$out" | jq -r '.name')"
          if [ "$current" != "$name" ]; then
            paseo project rename "$id" "$name" >/dev/null
          fi
          echo "project $name -> $path"
        done
    '';
  };
in
{
  options.programs.paseo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Manage Paseo's daemon configuration and projects on this host. Only
        meaningful where a Paseo daemon runs — the agentfest computer.
      '';
    };

    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      example = lib.literalExpression ''
        {
          daemon.agentProfiles = [
            { id = "review"; name = "Review"; provider = "claude"; modeId = "plan"; }
          ];
        }
      '';
      description = ''
        Merged into ~/.paseo/config.json on every activation, with the list
        rules described at the top of this module. Uses Paseo's own schema
        (https://paseo.sh/schemas/paseo.config.v1.json); `version = 1` is
        added when absent.
      '';
    };

    projects = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { work = "/home/rounak/work"; };
      description = ''
        Project name -> absolute path, as shown in the app's sidebar. Each path
        is created at activation; registration happens in
        `paseo-apply-declared`, which needs the daemon running.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ applyDeclared ];

    xdg.configFile."paseo/projects.json".text = builtins.toJSON cfg.projects;

    home.activation.paseoConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        JQ_BIN="${pkgs.jq}/bin/jq"
        mkdir -p "${paseoHome}"
        ${lib.concatMapStringsSep "\n  " (path: ''mkdir -p "${path}"'')
          (builtins.attrValues cfg.projects)}

        # Same shape as configs/codeman's settings merge, including what it
        # does with a file it cannot parse: leave it. It holds pairing state,
        # the daemon password hash and anything saved from the app, and a
        # parse error is likelier to be a half-finished write than corruption.
        if [ ! -s "${configFile}" ]; then
          "$JQ_BIN" '.' "${declaredFile}" > "${configFile}"
        elif "$JQ_BIN" -e . "${configFile}" >/dev/null 2>&1; then
          "$JQ_BIN" --argjson declared "$(cat "${declaredFile}")" -f "${mergeFile}" \
            "${configFile}" > "${configFile}.tmp" \
            && mv "${configFile}.tmp" "${configFile}"
        else
          rm -f "${configFile}.tmp"
          echo "WARNING: ${configFile} is not valid JSON; Paseo settings left unmerged" >&2
        fi
      ) || true
    '';
  };
}
