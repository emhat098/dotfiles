# dotfiles

Personal shell setup: oh-my-zsh + plugins + Powerlevel10k + modern CLI tools,
plus a Node/NestJS/TypeScript + Postgres/MongoDB/Valkey + AWS/GCP +
Docker/Kubernetes + general Linux/fullstack power-tool toolchain.

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

**Terminal / shell UX (steps 1-5):**
- Base packages (zsh, git, curl):
  - Linux — via whichever package manager is found: `apt-get`, `dnf`,
    `pacman`, or `zypper`
  - macOS — via Homebrew (installed automatically if missing)
- Oh My Zsh (unattended)
- Plugins: zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions,
  you-should-use, fzf-tab, git-open + built-ins (git, nvm, npm, node, docker,
  docker-compose, kubectl, helm, aws, gh, tmux, sudo, extract,
  command-not-found, fzf)
- Theme: Powerlevel10k
- fzf, zoxide, direnv — official installers, which already auto-detect
  Linux/macOS and arch themselves (installed to `~/.fzf` / `~/.local/bin`,
  no sudo)
- bat, eza, fd, ripgrep, lazygit, glow (Markdown renderer):
  - Linux — static binaries pulled straight from GitHub releases into
    `~/.local/bin`, arch-aware (`x86_64`/`aarch64`), no sudo
  - macOS — via Homebrew

**Dev toolchain (steps 6-10 — best-effort: a failed package/download prints a
warning and the script keeps going rather than aborting):**
- Node.js via nvm (installs nvm itself, then the latest LTS), plus
  `@nestjs/cli`, `typescript`, `ts-node` installed globally, and `corepack
  enable` for `pnpm`/`yarn` (ships with Node, just needs enabling)
- DB clients: `psql` (postgresql-client), `mongosh` (official binary,
  arch-aware), `redis-cli` (works against Valkey directly — protocol
  compatible; a `valkey-cli` alias is added too)
- Cloud CLIs: AWS CLI v2, Google Cloud SDK (`gcloud`)
- Containers & Kubernetes: Docker (engine on Linux via each distro's
  official method; macOS gets a manual Docker Desktop reminder since it's a
  GUI app), `kubectl`, `k9s`, `kubectx`/`kubens`, `helm`. A `docker-compose`
  (hyphenated, legacy v1 syntax) alias to `docker compose` is added in
  `.zshrc` — apt/dnf/zypper Docker installs only ship the newer space-syntax
  plugin, and this is Docker's own documented fix for that gap. The alias is
  skipped if a real standalone `docker-compose` binary is already present
  (e.g. Arch's `pacman` install), so it never overrides a working one.
- Fullstack & Linux power tools: `jq` + `yq` (JSON/YAML processors), `gh`
  (GitHub CLI), `tmux`, `git-delta` (wired up as git's diff pager
  automatically), `xh` (terminal HTTP client), `overmind` (Procfile-based
  multi-process runner — handy for running several microservices locally),
  `tldr` via the official `tlrc` client
- AI coding agents: Claude Code (`claude`) and Cursor CLI (`cursor-agent`,
  also symlinked as `agent`) — both via their official installers, which
  self-detect OS/arch and install to `~/.local/bin`

**Wrap-up (steps 11-12):**
- Writes `~/.zshrc` (backs up any existing one first)
- Sets zsh as your default shell

Safe to re-run — every step checks existing state first (git pull instead of
re-clone, skips already-installed binaries, backs up `.zshrc` before
overwriting).

After it finishes: `aws configure` / `gcloud init` to authenticate the cloud
CLIs, `docker login` as needed. If Docker was freshly installed on Linux,
log out/in (or run `newgrp docker`) for the new `docker` group membership to
take effect without sudo.

## Important: Nerd Font for icons

`eza --icons` and the Powerlevel10k icon segments need a **Nerd Font**
installed in your *terminal app* (Windows Terminal, iTerm2, Terminal.app,
etc.) — this lives outside the OS/distro this script runs in and can't be
scripted. Install one from https://www.nerdfonts.com/ (e.g. "MesloLGS NF",
which `p10k configure` recommends) and set it as your terminal's font.
