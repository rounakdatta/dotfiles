{ config, lib, pkgs, ... }:

# Make `Asia/Kolkata` actually true on a host that has no system underneath it.
#
# This exists because the intent was already declared twice and honoured neither
# time on festie:
#
#   - hosts/ninezeroes sets `time.timeZone`, which is a NixOS option. A standalone
#     home-manager profile has no NixOS layer, so festie never saw it.
#   - configs/fish sets `TZ` in interactiveShellInit, which reaches an interactive
#     fish and nothing else -- not bash, not a script, not a command an agent runs.
#
# And underneath both, festie ships **no zoneinfo at all**: no /usr/share/zoneinfo,
# no /etc/zoneinfo, TZDIR unset. glibc cannot resolve a zone name it has no
# database for, and its failure mode is to fall back to UTC *silently*:
#
#     $ TZ=Asia/Kolkata date -d 'tomorrow 12:30' '+%Y-%m-%dT%H:%M:%S%:z'
#     2026-08-25T12:30:00+00:00      # zone prints as "Asia"; the offset is wrong
#
# Nothing errors, the output looks entirely plausible, and everything derived from
# it is 5h30m off. That is a poor property for a machine whose whole job is doing
# work unattended, so the database and the variable are declared together here --
# either alone is worse than useless, because TZ without tzdata is exactly the
# silent-wrong case above.

let
  cfg = config.programs.timezone;
in
{
  options.programs.timezone = {
    enable = lib.mkEnableOption "a zoneinfo database and an exported TZ, for hosts with no system layer";

    zone = lib.mkOption {
      type = lib.types.str;
      default = "Asia/Kolkata";
      example = "Europe/Berlin";
      description = "IANA zone name exported as TZ.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.tzdata ];

    home.sessionVariables = {
      # Without this glibc has no database to look the zone up in, and TZ is
      # silently ignored. Set them as a pair or not at all.
      TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      TZ = cfg.zone;
    };
  };
}
