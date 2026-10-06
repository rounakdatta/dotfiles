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
#   projects, schedules   Not config at all. Paseo keeps them as records
#                         under ~/.paseo, created through its API, so they are
#                         declared here and applied by `paseo-apply-declared`
#                         against the running daemon (schedules matched by
#                         name). agentfest runs it after every daemon start;
#                         anywhere else, run it by hand once the daemon is up.
#
# Merge rules for lists: `daemon.agentProfiles` and every
# `agents.providers.<id>.additionalModels` merge by `id` — declared entries
# replace their namesakes and come first, and anything created in the app
# survives. Every other value is replaced wholesale, as jq's `*` does.
#
# Plugins are config too: each declared one becomes a `plugins.<id>` directory
# source pointing at its npm package, unpacked in the store. Paseo compiles a
# plugin in memory at start and serves its client half to every connected app,
# so a plugin installed here appears on the phone and the desktop with nothing
# to do on either. A plugin dropped from the list loses its entry at the next
# activation; one installed by hand (`paseo plugin add`) is left alone.
#
# Beads, for the paseo-beads plugin and for agents: one tracker per declared
# project. Its database lives in ~/.local/share/beads/<project>, behind one
# shared Dolt server, and the project folder holds only `.beads/redirect`, so
# ~/personal and ~/work never become git repositories. The `bd` on PATH finds
# a project's tracker from anywhere below it, repos included, and restarts the
# server whenever a call finds it down (after every pod restart, at least).
#
# Nothing here validates the result: the daemon does, at start. An invalid
# key stops Paseo from starting, so try a settings change against a scratch
# daemon (`PASEO_HOME=$(mktemp -d) paseo daemon run`) before shipping it.

let
  cfg = config.programs.paseo;
  paseoHome = "${config.home.homeDirectory}/.paseo";
  configFile = "${paseoHome}/config.json";

  # The registry tarball, checked against npm's own integrity hash, so the
  # bytes are the ones `npm install` would accept. A plugin's dependencies
  # are not fetched: Paseo provides the SDK, React and zod to the plugins it
  # compiles, and a plugin that needs more is not one this can install.
  pluginPackage = id: plugin:
    let
      tarball = pkgs.fetchurl {
        url = "https://registry.npmjs.org/${plugin.npm}/-/${baseNameOf plugin.npm}-${plugin.version}.tgz";
        hash = plugin.integrity;
      };
    in
    pkgs.runCommand "paseo-plugin-${id}-${plugin.version}" { } ''
      mkdir -p $out
      tar -xzf ${tarball} -C $out --strip-components=1
    '';

  declaredPlugins = lib.mapAttrs
    (id: plugin: {
      source = "directory";
      path = "${pluginPackage id plugin}";
      enabled = plugin.enable;
    })
    cfg.plugins;

  declaredSettings = lib.recursiveUpdate ({ version = 1; } // cfg.settings)
    (lib.optionalAttrs (cfg.plugins != { }) {
      pluginsEnabled = true;
      plugins = declaredPlugins;
    });

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
    # An entry this module wrote, a store path named paseo-plugin-*, goes when
    # its plugin is no longer declared; the path would not outlive a GC anyway.
    | if (.plugins? != null) then
        .plugins |= with_entries(select(
          ((.value.path? // "") | test("^/nix/store/[^/]+-paseo-plugin-") | not)
          or ($declared.plugins[.key]? != null)))
      else . end
  '';

  beadsData = "${config.home.homeDirectory}/.local/share/beads";

  # bd as everything here calls it, with three fixes:
  #   - bd stops looking for a tracker at a git repository's root, so from
  #     inside a repo in ~/personal it would never find the personal tracker.
  #     A call about a path in a declared project names that project's
  #     tracker outright (BEADS_DIR), unless a .beads of its own sits closer;
  #   - in shared-server mode a read finds a stopped Dolt server unreachable
  #     rather than starting it, and the server dies with the pod. A call that
  #     fails that way starts it (`bd dolt start` is idempotent and serialised
  #     by bd's own lock) and runs once more. A terminal gets bd itself, so its
  #     errors stream and its prompts work;
  #   - DO_NOT_TRACK: bd otherwise queues a usage event for DoltHub per call,
  #     one per agent command and two per panel refresh.
  beadsProjectCases = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: path: "${lib.escapeShellArg path}) export BEADS_DIR=${lib.escapeShellArg "${beadsData}/${name}/.beads"}; break ;;")
    cfg.projects);

  bd = pkgs.writeShellApplication {
    name = "bd";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
    text = ''
      export DO_NOT_TRACK=1
      export PATH="${pkgs.dolt}/bin:$PATH"
      real=${cfg.beads.package}/bin/bd

      # The directory this call is about: -C's, or the working directory.
      dir=()
      target="$PWD"
      prev=""
      for arg in "$@"; do
        case "$prev" in -C | --directory) dir=(-C "$arg") && target="$arg" ;; esac
        case "$arg" in --directory=*) dir=(-C "''${arg#--directory=}") && target="''${arg#--directory=}" ;; esac
        prev="$arg"
      done
      case "$target" in /*) ;; *) target="$PWD/$target" ;; esac

      if [ -z "''${BEADS_DIR:-}" ]; then
        d="$target"
        while :; do
          case "$d" in
            ${beadsProjectCases}
          esac
          if [ -d "$d/.beads" ] || [ "$d" = / ]; then break; fi
          d="$(dirname "$d")"
        done
      fi

      if [ -t 0 ] || [ -t 2 ]; then exec "$real" "$@"; fi

      err="$(mktemp)"
      trap 'rm -f "$err"' EXIT
      rc=0
      "$real" "$@" 2>"$err" || rc=$?
      if [ "$rc" -ne 0 ] && grep -q 'Dolt server unreachable' "$err" \
        && "$real" "''${dir[@]}" dolt start >/dev/null 2>&1; then
        rm -f "$err"
        exec "$real" "$@"
      fi
      cat "$err" >&2
      exit "$rc"
    '';
  };

  # One tracker per declared project, created once, then the shared server
  # started. Run detached by paseo-apply-declared after every daemon start: a
  # first `bd init` can take minutes on a busy node.
  beadsEnsure = pkgs.writeShellApplication {
    name = "paseo-beads-ensure";
    runtimeInputs = [ bd pkgs.git pkgs.jq pkgs.coreutils ];
    text = ''
      # Dolt's own usage events, for the server it runs.
      mkdir -p "$HOME/.dolt"
      dolt_config="$HOME/.dolt/config_global.json"
      [ -s "$dolt_config" ] || echo '{}' > "$dolt_config"
      jq '. + {"metrics.disabled": "true"}' "$dolt_config" > "$dolt_config.tmp" \
        && mv "$dolt_config.tmp" "$dolt_config"

      jq -r 'to_entries[] | "\(.key)\t\(.value)"' "${config.xdg.configHome}/paseo/projects.json" |
        while IFS=$'\t' read -r name path; do
          data="${beadsData}/$name"
          if [ ! -d "$data/.beads" ]; then
            # bd init commits its files: to a repository of its own here, and
            # unsigned, since a fresh pod's GPG key is locked.
            mkdir -p "$data"
            git -C "$data" init -q
            git -C "$data" config commit.gpgsign false
            if ! (cd "$data" && bd init --shared-server --non-interactive --skip-agents --skip-hooks --prefix "$name" >/dev/null); then
              echo "paseo-beads-ensure: could not create the $name tracker" >&2
              continue
            fi
            echo "$name: tracker created"
          fi
          mkdir -p "$path/.beads"
          if [ "$(cat "$path/.beads/redirect" 2>/dev/null)" != "$data/.beads" ]; then
            printf '%s\n' "$data/.beads" > "$path/.beads/redirect"
          fi
          bd -C "$data" dolt start >/dev/null 2>&1 || true
          if bd --readonly -C "$path" list --json >/dev/null 2>&1; then
            echo "$name: ready"
          else
            echo "paseo-beads-ensure: the $name tracker does not open (try bd doctor in $data)" >&2
          fi
        done
    '';
  };

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

      projects="${config.xdg.configHome}/paseo/projects.json"
      if [ -f "$projects" ]; then
        jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$projects" |
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
      fi

      # Schedules, matched by name: an existing one is updated in place, which
      # keeps its id, history and run logs; a missing one is created. The
      # thinking level applies only at creation, because `schedule update`
      # cannot change it.
      schedules="${config.xdg.configHome}/paseo/schedules.json"
      if [ -f "$schedules" ]; then
        existing="$(paseo schedule ls --json 2>/dev/null || echo '[]')"
        jq -c 'to_entries[]' "$schedules" |
          while IFS= read -r entry; do
            field() { jq -r --arg f "$1" '.value[$f] // empty' <<<"$entry"; }
            name="$(jq -r '.key' <<<"$entry")"
            cwd="$(field cwd)"
            args=(--cron "$(field cron)" --timezone "$(field timezone)" --cwd "$cwd")
            provider="$(field provider)"
            mode="$(field mode)"
            [ -z "$provider" ] || args+=(--provider "$provider")
            [ -z "$mode" ] || args+=(--mode "$mode")
            mkdir -p "$cwd"
            id="$(jq -r --arg n "$name" 'map(select(.name == $n)) | .[0].id // empty' <<<"$existing")"
            if [ -n "$id" ]; then
              if paseo schedule update "$id" "''${args[@]}" --prompt "$(field prompt)" >/dev/null 2>&1; then
                echo "schedule $name updated"
              else
                echo "paseo-apply-declared: could not update schedule $name" >&2
              fi
            else
              thinking="$(field thinking)"
              [ -z "$thinking" ] || args+=(--thinking "$thinking")
              if paseo schedule create --name "$name" "''${args[@]}" "$(field prompt)" >/dev/null 2>&1; then
                echo "schedule $name created"
              else
                echo "paseo-apply-declared: could not create schedule $name" >&2
              fi
            fi
          done
      fi
    '' + lib.optionalString cfg.beads.enable ''

      # Beads trackers, in a session of their own so that a slow first init
      # outlives this script's caller; the lock keeps restarts from stacking.
      mkdir -p "$HOME/.local/state"
      ${pkgs.util-linux}/bin/setsid -f ${pkgs.util-linux}/bin/flock -n "$HOME/.local/state/paseo-beads.lock" \
        ${beadsEnsure}/bin/paseo-beads-ensure >>"$HOME/.local/state/paseo-beads.log" 2>&1 || true
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

    schedules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          cron = lib.mkOption {
            type = lib.types.str;
            example = "0 1,9,17 * * *";
            description = "Cron expression, evaluated in `timezone`.";
          };
          timezone = lib.mkOption {
            type = lib.types.str;
            default = "UTC";
            description = "IANA zone for `cron`. Paseo defaults to UTC, not the machine's zone.";
          };
          cwd = lib.mkOption {
            type = lib.types.str;
            description = "Where each run's fresh agent starts; skills and MCP servers load from here.";
          };
          prompt = lib.mkOption { type = lib.types.str; };
          provider = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "claude/claude-opus-5-5";
          };
          mode = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "bypassPermissions";
          };
          thinking = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "max";
            description = "Thinking level, applied when the schedule is first created.";
          };
        };
      });
      default = { };
      description = ''
        Name -> schedule. Each run starts a fresh agent with `prompt` in `cwd`
        and archives it when done — Codeman's cron with
        autoClosePreviousSession. Applied by `paseo-apply-declared`.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          npm = lib.mkOption {
            type = lib.types.str;
            example = "@omercnet/paseo-pr-radar";
            description = "The npm package the plugin is published as.";
          };
          version = lib.mkOption {
            type = lib.types.str;
            example = "1.0.1";
          };
          integrity = lib.mkOption {
            type = lib.types.str;
            example = "sha512-qY76jnjreXWeVzL+…";
            description = "The registry's hash for that version: `npm view <npm>@<version> dist.integrity`.";
          };
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Commands the plugin's server code runs, put on the daemon's PATH.";
          };
        };
      });
      default = { };
      description = ''
        Plugin id (the `id` in its paseo-plugin.json) -> npm package, loaded by
        the daemon at start and shown in every client. Plugins are trusted,
        unsandboxed code that runs as this user: read a version before pinning
        it, and the diff before bumping it.
      '';
    };

    beads = {
      enable = lib.mkEnableOption ''
        a Beads tracker for every declared project, with `bd` on PATH: what the
        paseo-beads plugin shows, and what agents file work in'';
      package = lib.mkOption {
        type = lib.types.package;
        description = "Beads 1.0 or newer, providing bin/bd. It is wrapped here (see `bd` above).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ applyDeclared ]
      ++ lib.concatMap (plugin: plugin.packages) (builtins.attrValues cfg.plugins)
      ++ lib.optional cfg.beads.enable bd;

    # The trackers belong to their owner; unset, bd warns on every call.
    programs.git.settings.beads.role = lib.mkIf cfg.beads.enable "maintainer";

    xdg.configFile."paseo/projects.json".text = builtins.toJSON cfg.projects;
    xdg.configFile."paseo/schedules.json".text = builtins.toJSON cfg.schedules;

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
