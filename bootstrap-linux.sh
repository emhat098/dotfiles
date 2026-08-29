#!/usr/bin/env bash
# bootstrap-linux.sh — reproduce a full zsh + oh-my-zsh dev setup on a fresh
# Linux machine (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE). For macOS use
# bootstrap-macos.sh instead — the two used to be one script, but Linux's
# package-manager sprawl (apt/dnf/pacman/zypper) and macOS's single Homebrew
# path don't share enough step-for-step logic to justify branching on OS
# inside every step. Shared, OS-agnostic logic (oh-my-zsh, zsh plugins,
# fzf/zoxide/direnv, Node via nvm, kubectl/kubectx/helm, the generated
# ~/.zshrc) lives in bootstrap-common.sh, which both scripts source.
#
# Covers both terminal UX (oh-my-zsh, plugins, Powerlevel10k, fzf/zoxide/
# direnv, modern CLI tools) and a Node/TS/Nest + Postgres/Mongo/Valkey +
# AWS/GCP + Docker/K8s + jq/yq/gh/tmux/delta/xh/overmind/tldr dev toolchain.
#
# Usage (on a brand new WSL distro / VM / container):
#   curl -fsSL https://raw.githubusercontent.com/emhat098/dotfiles/main/bootstrap-linux.sh | bash
# or, if you already have the repo:
#   ~/dotfiles/bootstrap-linux.sh
#
# Safe to re-run: every step checks for existing state first (git pull instead
# of re-clone, skip if binary already on PATH, .zshrc backed up before
# overwrite). Steps 6-10 (dev toolchain) are best-effort: an individual
# package/download failure prints a warning and the script continues rather
# than aborting, since a stale package name on one distro shouldn't block
# everything else from installing.

set -euo pipefail

# Pull in shared helpers/steps (log/ok, clone_or_pull, oh-my-zsh, zsh
# plugins, fzf/zoxide/direnv, Node toolchain, gcloud/kubectl/kubectx/helm,
# claude/cursor-agent, ~/.zshrc generation, default-shell). Prefer the copy
# next to this script (cloned-repo usage); fall back to fetching it from
# GitHub so `curl -fsSL .../bootstrap-linux.sh | bash` still works standalone.
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

if [ "$OS_NAME" != "Linux" ]; then
  echo "bootstrap-linux.sh only supports Linux — this machine reports '$OS_NAME'. Use bootstrap-macos.sh instead." >&2
  exit 1
fi

# get_url/install_release_bin are Linux-only: macOS uses Homebrew instead
# throughout, so these live here rather than in bootstrap-common.sh.
get_url() { # $1 = owner/repo   $2 = grep pattern for asset filename
  # Unauthenticated GitHub API calls are capped at 60/hour per IP — fine
  # for a one-off local run, but this script does ~13 of these calls and
  # CI runs it on several distros in parallel from a shared runner IP range,
  # so authenticate when a token's available (CI sets GITHUB_TOKEN; harmless
  # no-op locally where it usually isn't set).
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -sS "${auth[@]}" "https://api.github.com/repos/$1/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/.*"(https[^"]+)"/\1/' \
    | grep -iE "$2" | head -1
}

install_release_bin() { # $1 owner/repo  $2 asset-regex  $3 binary-name-inside-tarball  $4 install-name  $5 optional: identity substring to grep for in `$outname --version`
  local repo="$1" pattern="$2" innerbin="$3" outname="$4" identity="${5:-}"
  if command -v "$outname" >/dev/null 2>&1; then
    # `command -v` only checks the name resolves to *something* — it can't
    # tell a same-named-but-different tool (e.g. Python's kislyuk/yq vs this
    # script's Go mikefarah/yq) from the real thing. When an identity marker
    # is given, verify it actually matches instead of silently trusting the
    # name; warn loudly rather than silently skip if it doesn't.
    if [ -n "$identity" ] && ! "$outname" --version 2>&1 | grep -qi "$identity"; then
      echo "  !! $outname is already on PATH but its version output doesn't mention '$identity' — this looks like a different '$outname' than expected (not overwriting it). Check '$outname --version' yourself if this causes issues." >&2
    else
      ok "$outname already installed"
    fi
    return
  fi
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

# Linux-only asset-name mappings for the GitHub-release binary installs in
# steps 5/7/9 — different projects use different tokens for the same arch
# (x86_64 vs amd64 vs x64), so we keep one var per convention.
case "$ARCH" in
  x86_64)  GNU_ARCH="x86_64-unknown-linux-gnu"; MUSL_ARCH="x86_64-unknown-linux-musl"; LG_ARCH="x86_64"; AMD64_ARCH="amd64"; MONGOSH_ARCH="x64"; AWS_ZIP_ARCH="x86_64" ;;
  aarch64) GNU_ARCH="aarch64-unknown-linux-gnu"; MUSL_ARCH="aarch64-unknown-linux-musl"; LG_ARCH="arm64"; AMD64_ARCH="arm64"; MONGOSH_ARCH="arm64"; AWS_ZIP_ARCH="aarch64" ;;
  *) echo "Unsupported Linux arch: $ARCH" >&2; exit 1 ;;
esac

# Single source of truth for which package manager step 1 (and the test
# suite) will use — computed once here instead of re-detected inline.
PKG_MGR="none"
if command -v apt-get >/dev/null 2>&1; then
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
# tests/test-bootstrap.sh exercise every arch/package-manager branch safely
# by mocking `uname` and the package-manager binaries on PATH.
if [ "${BOOTSTRAP_SELF_TEST:-0}" = "1" ]; then
  echo "OS_NAME=$OS_NAME ARCH=$ARCH PKG_MGR=$PKG_MGR GNU_ARCH=${GNU_ARCH:-} MUSL_ARCH=${MUSL_ARCH:-} LG_ARCH=${LG_ARCH:-} AMD64_ARCH=${AMD64_ARCH:-} MONGOSH_ARCH=${MONGOSH_ARCH:-} AWS_ZIP_ARCH=${AWS_ZIP_ARCH:-} K8S_OS=$K8S_OS K8S_ARCH=$K8S_ARCH"
  exit 0
fi

mkdir -p "$HOME/.local/bin"

# Prime sudo once upfront instead of prompting for a password at each of the
# ~15 separate sudo call sites scattered across steps 1/7/8/9/10 — a real
# run has long curl downloads in between them, so without this the cached
# credential can expire and re-prompt mid-run anyway. Skipped when there's no
# package manager to use it (PKG_MGR=none means step 1 is about to exit 1
# regardless, so there's nothing to prompt for).
if [ "$PKG_MGR" != "none" ]; then
  sudo -v
  # Keep the credential alive for the whole script run in the background;
  # dies with this script (checks kill -0 on our PID) rather than lingering.
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi

# ---------------------------------------------------------------------------
log "1/12  System packages (zsh, git, curl)"
case "$PKG_MGR" in
  apt)
    sudo apt-get update -qq
    sudo apt-get install -y -qq zsh git curl fontconfig unzip tar ca-certificates which openssl >/dev/null
    ;;
  dnf)
    sudo dnf install -y -q zsh git curl fontconfig unzip tar ca-certificates which openssl >/dev/null
    ;;
  pacman)
    sudo pacman -Sy --noconfirm --needed zsh git curl fontconfig unzip tar ca-certificates which openssl >/dev/null
    ;;
  zypper)
    sudo zypper --non-interactive install zsh git curl fontconfig unzip tar ca-certificates which openssl >/dev/null
    ;;
  *)
    echo "No supported package manager found (apt-get/dnf/pacman/zypper). Install zsh git curl fontconfig manually, then re-run." >&2
    exit 1
    ;;
esac
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
install_release_bin sharkdp/bat              "${GNU_ARCH}\.tar\.gz\$"       bat      bat
install_release_bin sharkdp/fd               "${GNU_ARCH}\.tar\.gz\$"      fd       fd
install_release_bin eza-community/eza        "${GNU_ARCH}\.tar\.gz\$"      eza      eza
install_release_bin BurntSushi/ripgrep       "${MUSL_ARCH}\.tar\.gz\$"     rg       rg
install_release_bin jesseduffield/lazygit    "linux_${LG_ARCH}\.tar\.gz\$" lazygit  lazygit
install_release_bin charmbracelet/glow       "Linux_${LG_ARCH}\.tar\.gz\$" glow     glow

# ---------------------------------------------------------------------------
log "6/12  Node.js (via nvm) + NestJS/TypeScript tooling"
install_node_toolchain

# ---------------------------------------------------------------------------
log "7/12  Database clients (psql, mongosh, redis/valkey-cli)"
case "$PKG_MGR" in
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
# apt/yum repo, so pull the official binary directly instead.
if ! command -v mongosh >/dev/null 2>&1; then
  install_release_bin mongodb-js/mongosh "linux-${MONGOSH_ARCH}\.tgz\$" mongosh mongosh
fi
ok "database client step complete (psql, mongosh, redis-cli — see warnings above for anything skipped)"
echo "  (valkey speaks the Redis protocol — redis-cli works against it directly; a 'valkey-cli' alias is added to .zshrc)"

# ---------------------------------------------------------------------------
log "8/12  Cloud CLIs (AWS, Google Cloud)"
if ! command -v aws >/dev/null 2>&1; then
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

install_gcloud_sdk
ok "AWS CLI $(aws --version 2>&1 | awk '{print $1}' || echo 'skipped'), Google Cloud SDK step complete"

# ---------------------------------------------------------------------------
log "9/12  Containers & Kubernetes (Docker, kubectl, k9s, kubectx/kubens, helm)"

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
    # $USER isn't guaranteed to be set (e.g. under `set -u` in a
    # container/CI shell with no login manager) — fall back to `id -un`,
    # which always works.
    CURRENT_USER="${USER:-$(id -un)}"
    sudo usermod -aG docker "$CURRENT_USER" 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      sudo systemctl enable --now docker >/dev/null 2>&1 || true
    fi
    echo "  (added $CURRENT_USER to the 'docker' group — log out/in, or run 'newgrp docker', for it to take effect without sudo)"
  fi
fi

install_kubectl_bin
install_release_bin derailed/k9s "Linux_${AMD64_ARCH}\.tar\.gz\$" k9s k9s
install_kubectx_kubens
install_helm_bin
ok "containers & k8s tooling step complete (see warnings above for anything skipped)"

# ---------------------------------------------------------------------------
log "10/12  Fullstack & Linux power tools (jq, yq, gh, tmux, git-delta, xh, overmind, tldr, claude, cursor-agent)"
case "$PKG_MGR" in
  apt)
    sudo apt-get install -y -qq jq tmux >/dev/null 2>&1 \
      || echo "  !! apt install of jq/tmux failed, skipping" >&2
    ;;
  dnf)
    sudo dnf install -y -q jq tmux >/dev/null 2>&1 \
      || echo "  !! dnf install of jq/tmux failed, skipping" >&2
    ;;
  pacman)
    sudo pacman -S --noconfirm --needed jq tmux >/dev/null 2>&1 \
      || echo "  !! pacman install of jq/tmux failed, skipping" >&2
    ;;
  zypper)
    sudo zypper --non-interactive install jq tmux >/dev/null 2>&1 \
      || echo "  !! zypper install of jq/tmux failed, skipping" >&2
    ;;
esac

# yq's tarball keeps the arch-suffixed filename (yq_linux_amd64) rather
# than a plain "yq", unlike every other tool here — pass that as innerbin.
# identity check: guards against the well-known Python kislyuk/yq (a
# completely different, incompatible CLI) already occupying the name.
install_release_bin mikefarah/yq     "linux_${AMD64_ARCH}\.tar\.gz\$" "yq_linux_${AMD64_ARCH}" yq mikefarah
install_release_bin dandavison/delta "${GNU_ARCH}\.tar\.gz\$"          delta                    delta
install_release_bin ducaale/xh       "${MUSL_ARCH}\.tar\.gz\$"         xh                       xh
install_release_bin cli/cli          "linux_${AMD64_ARCH}\.tar\.gz\$"  gh                       gh
install_release_bin tldr-pages/tlrc  "${GNU_ARCH}\.tar\.gz\$"          tldr                     tldr

# overmind's Linux releases are plain gzip (a single compressed binary),
# not a tar archive, so it can't go through install_release_bin as-is.
if ! command -v overmind >/dev/null 2>&1; then
  OVERMIND_URL=$(get_url DarthSim/overmind "linux-${AMD64_ARCH}\.gz\$")
  if [ -n "$OVERMIND_URL" ]; then
    curl -sSL "$OVERMIND_URL" 2>/dev/null | gunzip > "$HOME/.local/bin/overmind" \
      && chmod +x "$HOME/.local/bin/overmind" \
      || echo "  !! overmind download/extract failed, skipping" >&2
  else
    echo "  !! could not resolve overmind download URL, skipping" >&2
  fi
fi

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
