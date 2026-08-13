#!/usr/bin/env bash
# bootstrap-zsh.sh — reproduce a full zsh + oh-my-zsh dev setup on a fresh
# machine: Linux (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE) or macOS.
#
# Covers both terminal UX (oh-my-zsh, plugins, Powerlevel10k, fzf/zoxide/
# direnv, modern CLI tools) and a Node/TS/Nest + Postgres/Mongo/Valkey +
# AWS/GCP + Docker/K8s dev toolchain.
#
# Usage (on a brand new WSL distro / VM / container / Mac):
#   curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-zsh.sh | bash
# or, if you already have the repo:
#   ~/dotfiles/bootstrap-zsh.sh
#
# Safe to re-run: every step checks for existing state first (git pull instead
# of re-clone, skip if binary already on PATH, .zshrc backed up before
# overwrite). Steps 6-9 (dev toolchain) are best-effort: an individual
# package/download failure prints a warning and the script continues rather
# than aborting, since a stale package name on one distro shouldn't block
# everything else from installing.

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ->\033[0m %s\n' "$1"; }

# get_url/install_release_bin are hoisted here (rather than defined inline in
# step 5) so steps 5, 7, and 9 can all reuse them for GitHub-release-tarball
# installs on Linux (macOS uses Homebrew instead throughout).
get_url() { # $1 = owner/repo   $2 = grep pattern for asset filename
  curl -sS "https://api.github.com/repos/$1/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/.*"(https[^"]+)"/\1/' \
    | grep -iE "$2" | head -1
}

install_release_bin() { # $1 owner/repo  $2 asset-regex  $3 binary-name-inside-tarball  $4 install-name
  local repo="$1" pattern="$2" innerbin="$3" outname="$4"
  command -v "$outname" >/dev/null 2>&1 && { ok "$outname already installed"; return; }
  local url; url=$(get_url "$repo" "$pattern")
  [ -z "$url" ] && { echo "  !! could not resolve download URL for $repo, skipping" >&2; return; }
  local work; work=$(mktemp -d)
  curl -sSL "$url" -o "$work/pkg.tar.gz"
  tar xzf "$work/pkg.tar.gz" -C "$work" 2>/dev/null
  local found
  found=$(find "$work" -type f -name "$innerbin" | head -1)
  if [ -n "$found" ]; then
    cp "$found" "$HOME/.local/bin/$outname"
    chmod +x "$HOME/.local/bin/$outname"
    ok "$outname installed"
  else
    echo "  !! binary $innerbin not found in $repo archive, skipping" >&2
  fi
  rm -rf "$work"
}

OS_NAME="$(uname -s)"   # Linux | Darwin
ARCH="$(uname -m)"      # x86_64 | aarch64 (Linux) | arm64 (macOS)

# Linux-only asset-name mappings for the GitHub-release binary installs in
# steps 5/7/9 — different projects use different tokens for the same arch
# (x86_64 vs amd64 vs x64), so we keep one var per convention. macOS uses
# Homebrew instead, so it doesn't need any of these.
if [ "$OS_NAME" = "Linux" ]; then
  case "$ARCH" in
    x86_64)  GNU_ARCH="x86_64-unknown-linux-gnu"; MUSL_ARCH="x86_64-unknown-linux-musl"; LG_ARCH="x86_64"; AMD64_ARCH="amd64"; MONGOSH_ARCH="x64" ;;
    aarch64) GNU_ARCH="aarch64-unknown-linux-gnu"; MUSL_ARCH="aarch64-unknown-linux-musl"; LG_ARCH="arm64"; AMD64_ARCH="arm64"; MONGOSH_ARCH="arm64" ;;
    *) echo "Unsupported Linux arch: $ARCH" >&2; exit 1 ;;
  esac
elif [ "$OS_NAME" != "Darwin" ]; then
  echo "Unsupported OS: $OS_NAME (only Linux and macOS are supported)" >&2
  exit 1
fi

# Single source of truth for which package manager step 1 (and the test
# suite) will use — computed once here instead of re-detected inline.
PKG_MGR="none"
if [ "$OS_NAME" = "Darwin" ]; then
  PKG_MGR="brew"
elif command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v pacman >/dev/null 2>&1; then
  PKG_MGR="pacman"
elif command -v zypper >/dev/null 2>&1; then
  PKG_MGR="zypper"
fi

# Test hook: BOOTSTRAP_SELF_TEST=1 prints the detection result and exits
# before anything real happens (no sudo, no network, no file writes). Lets
# tests/test-bootstrap.sh exercise every OS/arch/package-manager branch
# safely by mocking `uname` and the package-manager binaries on PATH.
if [ "${BOOTSTRAP_SELF_TEST:-0}" = "1" ]; then
  echo "OS_NAME=$OS_NAME ARCH=$ARCH PKG_MGR=$PKG_MGR GNU_ARCH=${GNU_ARCH:-} MUSL_ARCH=${MUSL_ARCH:-} LG_ARCH=${LG_ARCH:-} AMD64_ARCH=${AMD64_ARCH:-} MONGOSH_ARCH=${MONGOSH_ARCH:-}"
  exit 0
fi

CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "$HOME/.local/bin"

# ---------------------------------------------------------------------------
log "1/11  System packages (zsh, git, curl)"
case "$PKG_MGR" in
  brew)
    if ! command -v brew >/dev/null 2>&1; then
      log "   Homebrew not found — installing"
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
    brew install -q zsh git curl >/dev/null 2>&1 || brew install zsh git curl
    ;;
  apt)
    sudo apt-get update -qq
    sudo apt-get install -y -qq zsh git curl fontconfig unzip tar ca-certificates >/dev/null
    ;;
  dnf)
    sudo dnf install -y -q zsh git curl fontconfig unzip tar ca-certificates >/dev/null
    ;;
  pacman)
    sudo pacman -Sy --noconfirm --needed zsh git curl fontconfig unzip tar ca-certificates >/dev/null
    ;;
  zypper)
    sudo zypper --non-interactive install zsh git curl fontconfig unzip tar ca-certificates >/dev/null
    ;;
  *)
    echo "No supported package manager found (apt-get/dnf/pacman/zypper). Install zsh git curl fontconfig manually, then re-run." >&2
    exit 1
    ;;
esac
ok "base packages present"

# ---------------------------------------------------------------------------
log "2/11  Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "installed"
else
  ok "already installed"
fi

# ---------------------------------------------------------------------------
log "3/11  Zsh plugins + Powerlevel10k theme"
clone_or_pull() {
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    git -C "$dest" pull --ff-only -q || true
  else
    git clone --depth=1 -q "$repo" "$dest"
  fi
}
clone_or_pull https://github.com/zsh-users/zsh-autosuggestions       "$CUSTOM/plugins/zsh-autosuggestions"
clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting   "$CUSTOM/plugins/zsh-syntax-highlighting"
clone_or_pull https://github.com/zsh-users/zsh-completions           "$CUSTOM/plugins/zsh-completions"
clone_or_pull https://github.com/MichaelAquilina/zsh-you-should-use  "$CUSTOM/plugins/you-should-use"
clone_or_pull https://github.com/Aloxaf/fzf-tab                      "$CUSTOM/plugins/fzf-tab"
clone_or_pull https://github.com/paulirish/git-open                  "$CUSTOM/plugins/git-open"
clone_or_pull https://github.com/romkatv/powerlevel10k               "$CUSTOM/themes/powerlevel10k"
ok "plugins ready"

# ---------------------------------------------------------------------------
log "4/11  fzf / zoxide / direnv"
# These three ship official install scripts that already auto-detect
# Linux vs macOS and the right arch — no branching needed here.
if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 -q https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --bin --no-update-rc --no-key-bindings --no-completion >/dev/null
fi
command -v zoxide >/dev/null 2>&1 || curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash -s -- --bin-dir "$HOME/.local/bin" >/dev/null 2>&1
command -v direnv >/dev/null 2>&1 || curl -sfL https://direnv.net/install.sh | bin_path="$HOME/.local/bin" bash >/dev/null 2>&1
ok "fzf $(~/.fzf/bin/fzf --version 2>/dev/null | awk '{print $1}'), zoxide, direnv ready"

# ---------------------------------------------------------------------------
log "5/11  Modern CLI tools (bat, fd, eza, ripgrep, lazygit, glow)"
if [ "$OS_NAME" = "Darwin" ]; then
  # Homebrew publishes darwin builds of all six directly — simpler and more
  # reliable than chasing per-arch GitHub release asset names on macOS.
  brew install -q bat eza fd ripgrep lazygit glow >/dev/null 2>&1 || brew install bat eza fd ripgrep lazygit glow
  ok "bat, eza, fd, ripgrep, lazygit, glow installed via Homebrew"
else
  install_release_bin sharkdp/bat              "${GNU_ARCH}\.tar\.gz\$"       bat      bat
  install_release_bin sharkdp/fd               "${GNU_ARCH}\.tar\.gz\$"      fd       fd
  install_release_bin eza-community/eza        "${GNU_ARCH}\.tar\.gz\$"      eza      eza
  install_release_bin BurntSushi/ripgrep       "${MUSL_ARCH}\.tar\.gz\$"     rg       rg
  install_release_bin jesseduffield/lazygit    "linux_${LG_ARCH}\.tar\.gz\$" lazygit  lazygit
  install_release_bin charmbracelet/glow       "Linux_${LG_ARCH}\.tar\.gz\$" glow     glow
fi

# ---------------------------------------------------------------------------
log "6/11  Node.js (via nvm) + NestJS/TypeScript tooling"
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  NVM_TAG=$(curl -sS https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | sed -E 's/.*"(v[0-9.]+)".*/\1/')
  [ -z "$NVM_TAG" ] && NVM_TAG="v0.40.6"
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" 2>/dev/null | bash >/dev/null 2>&1 \
    || echo "  !! nvm install script failed, skipping Node/Nest tooling (install nvm yourself: https://github.com/nvm-sh/nvm)" >&2
fi
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  \. "$NVM_DIR/nvm.sh"
  if ! command -v node >/dev/null 2>&1; then
    nvm install --lts >/dev/null 2>&1 && nvm alias default 'lts/*' >/dev/null 2>&1 \
      || echo "  !! nvm could not install a Node LTS release, skipping" >&2
  fi
  if command -v npm >/dev/null 2>&1; then
    npm install -g @nestjs/cli typescript ts-node >/dev/null 2>&1 \
      || echo "  !! failed to install @nestjs/cli/typescript/ts-node globally (run 'npm i -g @nestjs/cli typescript ts-node' yourself later)" >&2
  fi
  ok "node $(node --version 2>/dev/null || echo '?'), nest CLI + typescript ready"
else
  echo "  !! nvm not available, skipping Node/Nest tooling" >&2
fi

# ---------------------------------------------------------------------------
log "7/11  Database clients (psql, mongosh, redis/valkey-cli)"
case "$PKG_MGR" in
  brew)
    brew install -q libpq redis >/dev/null 2>&1 || brew install libpq redis
    brew link --force libpq >/dev/null 2>&1 || true
    ;;
  apt)
    sudo apt-get install -y -qq postgresql-client redis-tools >/dev/null 2>&1 \
      || echo "  !! apt install of postgresql-client/redis-tools failed, skipping" >&2
    ;;
  dnf)
    sudo dnf install -y -q postgresql redis >/dev/null 2>&1 \
      || echo "  !! dnf install of postgresql/redis failed, skipping" >&2
    ;;
  pacman)
    sudo pacman -S --noconfirm --needed postgresql redis >/dev/null 2>&1 \
      || echo "  !! pacman install of postgresql/redis failed, skipping" >&2
    ;;
  zypper)
    sudo zypper --non-interactive install postgresql redis >/dev/null 2>&1 \
      || echo "  !! zypper install of postgresql/redis failed, skipping (package name may differ on this openSUSE version)" >&2
    ;;
esac

# mongosh isn't reliably packaged across distros without adding MongoDB's own
# apt/yum repo, so pull the official binary directly instead (Homebrew
# already covers macOS above).
if [ "$PKG_MGR" != "brew" ] && ! command -v mongosh >/dev/null 2>&1; then
  install_release_bin mongodb-js/mongosh "linux-${MONGOSH_ARCH}\.tgz\$" mongosh mongosh
fi
ok "database client step complete (psql, mongosh, redis-cli — see warnings above for anything skipped)"
echo "  (valkey speaks the Redis protocol — redis-cli works against it directly; a 'valkey-cli' alias is added to .zshrc)"

# ---------------------------------------------------------------------------
log "8/11  Cloud CLIs (AWS, Google Cloud)"
if ! command -v aws >/dev/null 2>&1; then
  if [ "$OS_NAME" = "Darwin" ]; then
    brew install -q awscli >/dev/null 2>&1 || brew install awscli
  else
    AWS_ZIP_ARCH="x86_64"; [ "$ARCH" = "aarch64" ] && AWS_ZIP_ARCH="aarch64"
    AWS_WORK=$(mktemp -d)
    if curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ZIP_ARCH}.zip" -o "$AWS_WORK/awscliv2.zip"; then
      unzip -q "$AWS_WORK/awscliv2.zip" -d "$AWS_WORK"
      sudo "$AWS_WORK/aws/install" >/dev/null 2>&1 \
        || sudo "$AWS_WORK/aws/install" --update >/dev/null 2>&1 \
        || echo "  !! AWS CLI installer failed, skipping (install manually: https://docs.aws.amazon.com/cli/)" >&2
    else
      echo "  !! could not download AWS CLI installer, skipping" >&2
    fi
    rm -rf "$AWS_WORK"
  fi
fi

if [ ! -d "$HOME/google-cloud-sdk" ]; then
  curl -sS https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$HOME" >/dev/null 2>&1 \
    || echo "  !! Google Cloud SDK install failed, skipping (install manually: https://cloud.google.com/sdk/docs/install)" >&2
fi
ok "AWS CLI $(aws --version 2>&1 | awk '{print $1}' || echo 'skipped'), Google Cloud SDK step complete"

# ---------------------------------------------------------------------------
log "9/11  Containers & Kubernetes (Docker, kubectl, k9s, kubectx/kubens, helm)"

if [ "$OS_NAME" = "Darwin" ]; then
  if [ ! -d "/Applications/Docker.app" ] && ! command -v docker >/dev/null 2>&1; then
    echo "  !! Docker Desktop not found — it's a GUI app and can't be scripted headlessly. Install manually: https://www.docker.com/products/docker-desktop/" >&2
  fi
else
  if ! command -v docker >/dev/null 2>&1; then
    case "$PKG_MGR" in
      apt|dnf|zypper)
        curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1 \
          || echo "  !! Docker install script failed, skipping (install manually: https://docs.docker.com/engine/install/)" >&2
        ;;
      pacman)
        sudo pacman -S --noconfirm --needed docker docker-compose >/dev/null 2>&1 \
          || echo "  !! pacman install of docker failed, skipping" >&2
        ;;
    esac
    if command -v docker >/dev/null 2>&1; then
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        sudo systemctl enable --now docker >/dev/null 2>&1 || true
      fi
      echo "  (added $USER to the 'docker' group — log out/in, or run 'newgrp docker', for it to take effect without sudo)"
    fi
  fi
fi

# kubectl — official binary, arch/OS-aware, no package manager needed
if ! command -v kubectl >/dev/null 2>&1; then
  K8S_OS="linux"; [ "$OS_NAME" = "Darwin" ] && K8S_OS="darwin"
  K8S_ARCH="amd64"; { [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; } && K8S_ARCH="arm64"
  K8S_STABLE=$(curl -sSL https://dl.k8s.io/release/stable.txt 2>/dev/null)
  if [ -n "$K8S_STABLE" ] && curl -sSL "https://dl.k8s.io/release/${K8S_STABLE}/bin/${K8S_OS}/${K8S_ARCH}/kubectl" -o "$HOME/.local/bin/kubectl"; then
    chmod +x "$HOME/.local/bin/kubectl"
  else
    echo "  !! kubectl download failed, skipping" >&2
  fi
fi

# k9s
if [ "$OS_NAME" = "Darwin" ]; then
  command -v k9s >/dev/null 2>&1 || { brew install -q k9s >/dev/null 2>&1 || brew install k9s; }
else
  install_release_bin derailed/k9s "Linux_${AMD64_ARCH}\.tar\.gz\$" k9s k9s
fi

# kubectx / kubens — plain shell scripts, identical install on every OS
if ! command -v kubectx >/dev/null 2>&1; then
  KCTX_WORK=$(mktemp -d)
  if git clone --depth=1 -q https://github.com/ahmetb/kubectx.git "$KCTX_WORK" 2>/dev/null; then
    cp "$KCTX_WORK/kubectx" "$KCTX_WORK/kubens" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/kubectx" "$HOME/.local/bin/kubens"
  else
    echo "  !! could not clone kubectx/kubens, skipping" >&2
  fi
  rm -rf "$KCTX_WORK"
fi

# helm — official installer, arch/OS-aware, installed without sudo
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | USE_SUDO=false HELM_INSTALL_DIR="$HOME/.local/bin" bash >/dev/null 2>&1 \
    || echo "  !! helm install script failed, skipping" >&2
fi
ok "containers & k8s tooling step complete (see warnings above for anything skipped)"

# ---------------------------------------------------------------------------
log "10/11  Writing ~/.zshrc"
if [ -f "$HOME/.zshrc" ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
fi

cat > "$HOME/.zshrc" <<'ZSHRC'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Homebrew (macOS only) — must come early so its bin dir is on PATH below.
if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# NOTE: zsh-syntax-highlighting must stay last in this list.
plugins=(
  git
  git-open
  nvm
  npm
  node
  docker
  docker-compose
  kubectl
  helm
  aws
  sudo
  extract
  command-not-found
  fzf
  fzf-tab
  zsh-completions
  you-should-use
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"

# Google Cloud SDK
if [ -d "$HOME/google-cloud-sdk" ]; then
  export PATH="$HOME/google-cloud-sdk/bin:$PATH"
  [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ] && source "$HOME/google-cloud-sdk/completion.zsh.inc"
fi

# Homebrew libpq (macOS): the psql client isn't symlinked into the main brew
# prefix by default since it can conflict with a full postgresql install.
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
  LIBPQ_PREFIX="$(brew --prefix libpq 2>/dev/null)"
  [ -n "$LIBPQ_PREFIX" ] && export PATH="$LIBPQ_PREFIX/bin:$PATH"
fi

# fzf-tab: preview file contents / directory listings while tab-completing
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 --color=always $realpath'
zstyle ':fzf-tab:*' fzf-flags --height=40%

# zoxide: smarter `cd` — use `z <partial-name>` to jump to frequent/recent dirs
eval "$(zoxide init zsh)"

# direnv: auto-load per-project .envrc files
eval "$(direnv hook zsh)"

# Powerlevel10k instant prompt config (auto-generated by `p10k configure`)
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Modern CLI tool replacements (installed to ~/.local/bin on Linux, via
# Homebrew on macOS — either way they're already on PATH by this point)
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza --tree --icons --level=2'
alias cat='bat --paging=never --style=plain'
alias lg='lazygit'
# Note: the kubectl oh-my-zsh plugin already provides 'alias k=kubectl' + completion.
# valkey speaks the Redis wire protocol — redis-cli works against it directly
alias valkey-cli='redis-cli'
# Note: `fd` and `rg` are left as their own commands (not aliased over
# find/grep) since their syntax differs — just use `fd <pattern>` / `rg <pattern>` directly.
ZSHRC
ok "~/.zshrc written (previous one backed up if it existed)"

# ---------------------------------------------------------------------------
log "11/11  Default shell"
if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
  chsh -s "$(command -v zsh)" || echo "  (run 'chsh -s \$(command -v zsh)' yourself if this failed non-interactively)"
fi
ok "default shell is zsh (or chsh command printed above)"

echo
log "Done. Start a new shell with: exec zsh"
log "First run launches the Powerlevel10k wizard — rerun anytime with: p10k configure"
log "Next: 'aws configure' / 'gcloud init' to authenticate cloud CLIs, 'docker login' as needed"
