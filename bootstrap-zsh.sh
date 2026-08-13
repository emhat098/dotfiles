#!/usr/bin/env bash
# bootstrap-zsh.sh — reproduce a full zsh + oh-my-zsh dev setup on a fresh
# machine: Linux (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE) or macOS.
#
# Usage (on a brand new WSL distro / VM / container / Mac):
#   curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-zsh.sh | bash
# or, if you already have the repo:
#   ~/dotfiles/bootstrap-zsh.sh
#
# Safe to re-run: every step checks for existing state first (git pull instead
# of re-clone, skip if binary already on PATH, .zshrc backed up before overwrite).

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ->\033[0m %s\n' "$1"; }

OS_NAME="$(uname -s)"   # Linux | Darwin
ARCH="$(uname -m)"      # x86_64 | aarch64 (Linux) | arm64 (macOS)

# Linux-only asset-name mapping for the GitHub-release binary installs in
# step 5. macOS uses Homebrew instead, so it doesn't need these.
if [ "$OS_NAME" = "Linux" ]; then
  case "$ARCH" in
    x86_64)  GNU_ARCH="x86_64-unknown-linux-gnu"; MUSL_ARCH="x86_64-unknown-linux-musl"; LG_ARCH="x86_64" ;;
    aarch64) GNU_ARCH="aarch64-unknown-linux-gnu"; MUSL_ARCH="aarch64-unknown-linux-musl"; LG_ARCH="arm64" ;;
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
  echo "OS_NAME=$OS_NAME ARCH=$ARCH PKG_MGR=$PKG_MGR GNU_ARCH=${GNU_ARCH:-} MUSL_ARCH=${MUSL_ARCH:-} LG_ARCH=${LG_ARCH:-}"
  exit 0
fi

CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "$HOME/.local/bin"

# ---------------------------------------------------------------------------
log "1/7  System packages (zsh, git, curl)"
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
log "2/7  Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "installed"
else
  ok "already installed"
fi

# ---------------------------------------------------------------------------
log "3/7  Zsh plugins + Powerlevel10k theme"
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
log "4/7  fzf / zoxide / direnv"
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
log "5/7  Modern CLI tools (bat, fd, eza, ripgrep, lazygit)"

if [ "$OS_NAME" = "Darwin" ]; then
  # Homebrew publishes darwin builds of all five directly — simpler and more
  # reliable than chasing per-arch GitHub release asset names on macOS.
  brew install -q bat eza fd ripgrep lazygit >/dev/null 2>&1 || brew install bat eza fd ripgrep lazygit
  ok "bat, eza, fd, ripgrep, lazygit installed via Homebrew"
else
  get_url() { # $1 = owner/repo   $2 = grep pattern for asset filename
    curl -sS "https://api.github.com/repos/$1/releases/latest" \
      | grep -o '"browser_download_url": *"[^"]*"' \
      | sed -E 's/.*"(https[^"]+)"/\1/' \
      | grep -E "$2" | head -1
  }

  install_release_bin() { # $1 owner/repo  $2 asset-regex  $3 binary-name-inside-tarball  $4 install-name
    local repo="$1" pattern="$2" innerbin="$3" outname="$4"
    command -v "$outname" >/dev/null 2>&1 && { ok "$outname already installed"; return; }
    local url; url=$(get_url "$repo" "$pattern")
    [ -z "$url" ] && { echo "  !! could not resolve download URL for $repo, skipping" >&2; return; }
    local work; work=$(mktemp -d)
    curl -sSL "$url" -o "$work/pkg.tar.gz"
    tar xzf "$work/pkg.tar.gz" -C "$work"
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

  install_release_bin sharkdp/bat              "${GNU_ARCH}\.tar\.gz\$"       bat      bat
  install_release_bin sharkdp/fd               "${GNU_ARCH}\.tar\.gz\$"      fd       fd
  install_release_bin eza-community/eza        "${GNU_ARCH}\.tar\.gz\$"      eza      eza
  install_release_bin BurntSushi/ripgrep       "${MUSL_ARCH}\.tar\.gz\$"     rg       rg
  install_release_bin jesseduffield/lazygit    "linux_${LG_ARCH}\.tar\.gz\$" lazygit  lazygit
fi

# ---------------------------------------------------------------------------
log "6/7  Writing ~/.zshrc"
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
# Note: `fd` and `rg` are left as their own commands (not aliased over
# find/grep) since their syntax differs — just use `fd <pattern>` / `rg <pattern>` directly.
ZSHRC
ok "~/.zshrc written (previous one backed up if it existed)"

# ---------------------------------------------------------------------------
log "7/7  Default shell"
if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
  chsh -s "$(command -v zsh)" || echo "  (run 'chsh -s \$(command -v zsh)' yourself if this failed non-interactively)"
fi
ok "default shell is zsh (or chsh command printed above)"

echo
log "Done. Start a new shell with: exec zsh"
log "First run launches the Powerlevel10k wizard — rerun anytime with: p10k configure"
