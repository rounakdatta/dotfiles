<div align="center">
  <img src="logo.png" alt="dotfiles logo" width="300">
</div>

# dotfiles

Nix is my way of setting up and managing my computers. It's an entirely declarative way of saying what you want. Some people also say it's a cult.

## How broad it is

- **ninezeroes** — NixOS (x86_64-linux)
- **trueswiftie** — macOS (aarch64-darwin)

## How to navigate

- The `hosts/` directory contains the entrypoints to different architectures of machines.
- The `configs/` directory contains how individual software should be configured.

## Going ahead and using it

Apply a configuration:

```bash
# NixOS
sudo nixos-rebuild switch --flake .#ninezeroes

# macOS
sudo darwin-rebuild switch --flake .#trueswiftie
```

## What else

Sometimes you might have to ask Nix to skip cache, and the flag for that is `--option eval-cache false`.

---

My dotfiles setup has evolved over the years, starting from maybe ... Ansible? I used NixOS (the real thing) for about a year before moving on to application-level Nix on macOS. I think I value convenience over [BTW-ism](https://knowyourmeme.com/memes/btw-i-use-arch).
