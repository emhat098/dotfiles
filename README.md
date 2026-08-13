# dotfiles

Personal shell setup: oh-my-zsh + plugins + Powerlevel10k + modern CLI tools
(fzf, zoxide, direnv, bat, eza, fd, ripgrep, lazygit).

Supports Linux (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE) and macOS.

## Use on a brand new machine (fresh `wsl --install` distro, VM, or Mac)

```bash
curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-zsh.sh | bash
exec zsh
```

Or, if you've cloned the repo already:

```bash
git clone https://github.com/emhat098/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap-zsh.sh
exec zsh
```

First shell launch runs the Powerlevel10k config wizard. Rerun it anytime with
`p10k configure`.

## What it installs

- Base packages (zsh, git, curl):
  - Linux — via whichever package manager is found: `apt-get`, `dnf`,
    `pacman`, or `zypper`
  - macOS — via Homebrew (installed automatically if missing)
- Oh My Zsh (unattended)
- Plugins: zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions,
  you-should-use, fzf-tab, git-open + built-ins (git, nvm, npm, node, sudo,
  extract, command-not-found, fzf)
- Theme: Powerlevel10k
- fzf, zoxide, direnv — official installers, which already auto-detect
  Linux/macOS and arch themselves (installed to `~/.fzf` / `~/.local/bin`,
  no sudo)
- bat, eza, fd, ripgrep, lazygit:
  - Linux — static binaries pulled straight from GitHub releases into
    `~/.local/bin`, arch-aware (`x86_64`/`aarch64`), no sudo
  - macOS — via Homebrew
- Writes `~/.zshrc` (backs up any existing one first)
- Sets zsh as your default shell

Safe to re-run — every step checks existing state first (git pull instead of
re-clone, skips already-installed binaries, backs up `.zshrc` before
overwriting).

## Important: Nerd Font for icons

`eza --icons` and the Powerlevel10k icon segments need a **Nerd Font**
installed in your *terminal app* (Windows Terminal, iTerm2, Terminal.app,
etc.) — this lives outside the OS/distro this script runs in and can't be
scripted. Install one from https://www.nerdfonts.com/ (e.g. "MesloLGS NF",
which `p10k configure` recommends) and set it as your terminal's font.
