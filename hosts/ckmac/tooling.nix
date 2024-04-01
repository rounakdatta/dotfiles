{ config, pkgs, ... }: {
    launchd.user.agents.snibox-to-memoet = {
        serviceConfig = {
            ProgramArguments = [ "/opt/homebrew/opt/node@18/bin/node" "${config.users.users.rounak.home}/.scripts/automata/snibox2memoet.js" ];
            EnvironmentVariables = {
                NODE_PATH = "/opt/homebrew/lib/node_modules";
            };
            StartInterval = 300; # signifies that this will run every 300s
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "/tmp/automata/snibox2memoet.output.log";
            StandardErrorPath = "/tmp/automata/snibox2memoet.error.log";
        };
    };
}
