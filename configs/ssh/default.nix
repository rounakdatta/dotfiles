{ config, pkgs, ... }: {
    programs.ssh = {
        enable = true;
        extraConfig = ''
        Host github.com
        Preferredauthentications publickey
        User rounakdatta
        IdentityFile ~/.ssh/keys/personal.pem
    '';
    };
}
