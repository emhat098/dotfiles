#!/usr/bin/env bash
# bootstrap-macos.sh — reproduce a full zsh + oh-my-zsh dev setup on a fresh
# Mac. For Linux use bootstrap-linux.sh instead — the two used to be one
# script, but Linux's package-manager sprawl (apt/dnf/pacman/zypper) and
# macOS's single Homebrew path don't share enough step-for-step logic to
# justify branching on OS inside every step. Shared, OS-agnostic logic
# (oh-my-zsh, zsh plugins, fzf/zoxide/direnv, Node via nvm, kubectl/kubectx/
# helm, the generated ~/.zshrc) lives in bootstrap-common.sh, which both
# scripts source.
#
# Covers both terminal UX (oh-my-zsh, plugins, Powerlevel10k, fzf/zoxide/
# direnv, modern CLI tools) and a Node/TS/Nest + Postgres/Mongo/Valkey +
# AWS/GCP + Docker/K8s + jq/yq/gh/tmux/delta/xh/overmind/tldr dev toolchain.
#
# Usage (on a brand new Mac):
#   curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-macos.sh | bash
# or, if you already have the repo:
#   ~/dotfiles/bootstrap-macos.sh
#
# Safe to re-run: every step checks for existing state first (git pull instead
# of re-clone, skip if binary already on PATH, .zshrc backed up before
# overwrite). Steps 6-10 (dev toolchain) are best-effort: an individual
# brew formula failure prints a warning and the script continues rather than
# aborting.

set -euo pipefail

# Pull in shared helpers/steps (log/ok, clone_or_pull, oh-my-zsh, zsh
# plugins, fzf/zoxide/direnv, Node toolchain, gcloud/kubectl/kubectx/helm,
# claude/cursor-agent, ~/.zshrc generation, default-shell). Prefer the copy
# next to this script (cloned-repo usage); fall back to fetching it from
# GitHub so `curl -fsSL .../bootstrap-macos.sh | bash` still works standalone.
case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *)   SCRIPT_DIR="." ;;
esac
SCRIPT_DIR="$(cd "$SCRIPT_DIR" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bootstrap-common.sh" ]; then
  # shellcheck source=bootstrap-common.sh
  . "$SCRIPT_DIR/bootstrap-common.sh"
else
  COMMON_TMP="$(mktemp -t bootstrap-common.XXXXXX.sh)"
  trap 'rm -f "$COMMON_TMP"' EXIT
  curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-common.sh -o "$COMMON_TMP"
  # shellcheck source=/dev/null
  . "$COMMON_TMP"
  rm -f "$COMMON_TMP"
  trap - EXIT
fi

if [ "$OS_NAME" != "Darwin" ]; then
  echo "bootstrap-macos.sh only supports macOS — this machine reports '$OS_NAME'. Use bootstrap-linux.sh instead." >&2
  exit 1
fi

# Always Homebrew on macOS — kept as a variable (rather than a literal
# string sprinkled through this file) only so it reads consistently
# alongside bootstrap-linux.sh's PKG_MGR.
PKG_MGR="brew"

# Test hook: BOOTSTRAP_SELF_TEST=1 prints the detection result and exits
# before anything real happens (no network, no file writes). Lets
# tests/test-bootstrap.sh exercise the arch-mapping branch safely by mocking
# `uname` under `env -i`.
if [ "${BOOTSTRAP_SELF_TEST:-0}" = "1" ]; then
  echo "OS_NAME=$OS_NAME ARCH=$ARCH PKG_MGR=$PKG_MGR K8S_OS=$K8S_OS K8S_ARCH=$K8S_ARCH"
  exit 0
fi

mkdir -p "$HOME/.local/bin"

# ---------------------------------------------------------------------------
log "1/12  Homebrew + base packages (zsh, git, curl)"
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
ok "base packages present"

# ---------------------------------------------------------------------------
log "2/12  Oh My Zsh"
install_ohmyzsh

# ---------------------------------------------------------------------------
log "3/12  Zsh plugins + Powerlevel10k theme"
install_zsh_plugins

# ---------------------------------------------------------------------------
log "4/12  fzf / zoxide / direnv"
install_fzf_zoxide_direnv

# ---------------------------------------------------------------------------
log "5/12  Modern CLI tools (bat, fd, eza, ripgrep, lazygit, glow)"
# Homebrew publishes darwin builds of all six directly — simpler and more
# reliable than chasing per-arch GitHub release asset names.
brew install -q bat eza fd ripgrep lazygit glow >/dev/null 2>&1 || brew install bat eza fd ripgrep lazygit glow
ok "bat, eza, fd, ripgrep, lazygit, glow installed via Homebrew"

# ---------------------------------------------------------------------------
log "6/12  Node.js (via nvm) + NestJS/TypeScript tooling"
install_node_toolchain

# ---------------------------------------------------------------------------
log "7/12  Database clients (psql, mongosh, redis/valkey-cli)"
brew install -q libpq redis mongosh >/dev/null 2>&1 || brew install libpq redis mongosh
brew link --force libpq >/dev/null 2>&1 || true
ok "database client step complete (psql, mongosh, redis-cli — see warnings above for anything skipped)"
echo "  (valkey speaks the Redis protocol — redis-cli works against it directly; a 'valkey-cli' alias is added to .zshrc)"

# ---------------------------------------------------------------------------
log "8/12  Cloud CLIs (AWS, Google Cloud)"
if ! command -v aws >/dev/null 2>&1; then
  brew install -q awscli >/dev/null 2>&1 || brew install awscli
fi
install_gcloud_sdk
ok "AWS CLI $(aws --version 2>&1 | awk '{print $1}' || echo 'skipped'), Google Cloud SDK step complete"

# ---------------------------------------------------------------------------
log "9/12  Containers & Kubernetes (Docker, kubectl, k9s, kubectx/kubens, helm)"
if [ ! -d "/Applications/Docker.app" ] && ! command -v docker >/dev/null 2>&1; then
  echo "  !! Docker Desktop not found — it's a GUI app and can't be scripted headlessly. Install manually: https://www.docker.com/products/docker-desktop/" >&2
fi

install_kubectl_bin
command -v k9s >/dev/null 2>&1 || { brew install -q k9s >/dev/null 2>&1 || brew install k9s; }
install_kubectx_kubens
install_helm_bin
ok "containers & k8s tooling step complete (see warnings above for anything skipped)"

# ---------------------------------------------------------------------------
log "10/12  Fullstack & Linux power tools (jq, yq, gh, tmux, git-delta, xh, overmind, tldr, claude, cursor-agent)"
brew install -q jq tmux gh yq git-delta xh overmind tlrc >/dev/null 2>&1 \
  || brew install jq tmux gh yq git-delta xh overmind tlrc

install_claude_and_cursor
wire_up_delta_gitconfig
ok "power tools step complete (see warnings above for anything skipped)"

# ---------------------------------------------------------------------------
log "11/12  Writing ~/.zshrc"
write_zshrc

# ---------------------------------------------------------------------------
log "12/12  Default shell"
set_default_shell

echo
log "Done. Start a new shell with: exec zsh"
log "First run launches the Powerlevel10k wizard — rerun anytime with: p10k configure"
log "Next: 'aws configure' / 'gcloud init' to authenticate cloud CLIs, 'docker login' as needed"
