{ pkgs, lib, ... }:
let
  buildGoInstall = { owner, repo, rev ? "main", sha256, vendorHash, subPackages ? [ "." ] }:
    pkgs.buildGoModule {
      pname = repo;
      version = rev;
      src = pkgs.fetchFromGitHub { inherit owner repo rev sha256; };
      inherit vendorHash subPackages;
    };
in
{
  home.packages = [
    # Custom Go packages (use lib.fakeHash initially, build will show correct hash)
    (buildGoInstall {
      owner = "blacktop";
      repo = "mcp-tts";
      sha256 = lib.fakeHash;
      vendorHash = lib.fakeHash;
    })

    # Many Go tools already exist in nixpkgs:
    # pkgs.gopls
    # pkgs.golangci-lint
  ];
}
