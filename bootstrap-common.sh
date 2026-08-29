#!/usr/bin/env bash
# bootstrap-common.sh — shared helpers + OS-agnostic install steps, sourced
# by both bootstrap-macos.sh and bootstrap-linux.sh. Not meant to be run
# directly (it only defines variables/functions — nothing here has a side
# effect until an entrypoint script calls one of these functions).
#
# Anything that installs the *same way* regardless of OS (git-clone-based
# plugins, official curl-piped installers that already auto-detect
# platform/arch themselves, the generated ~/.zshrc) lives here so it isn't
# duplicated between the macOS and Linux entrypoints. Anything that differs
# by package manager (Homebrew vs apt/dnf/pacman/zypper, or GitHub-release
# binary installs that only make sense on Linux) stays in the entrypoint
# scripts themselves.

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ->\033[0m %s\n' "$1"; }

OS_NAME="$(uname -s)"   # Linux | Darwin
ARCH="$(uname -m)"      # x86_64 | aarch64 (Linux) | arm64 (macOS)

# kubectl's dl.k8s.io release layout needs OS/arch tokens on both platforms,
# so this is computed here rather than in either entrypoint.
K8S_OS="linux"; [ "$OS_NAME" = "Darwin" ] && K8S_OS="darwin"
K8S_ARCH="amd64"; { [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; } && K8S_ARCH="arm64"

clone_or_pull() { # $1 = repo url  $2 = dest dir
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    git -C "$dest" pull --ff-only -q || true
  else
    git clone --depth=1 -q "$repo" "$dest"
  fi
}

# ---------------------------------------------------------------------------
install_ohmyzsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "installed"
  else
    ok "already installed"
  fi
}

# ---------------------------------------------------------------------------
install_zsh_plugins() {
  # Computed here (not at source time) so sourcing this file never
  # dereferences $HOME before a caller is ready for that — e.g. the
  # entrypoint scripts' BOOTSTRAP_SELF_TEST hook runs under `env -i` with no
  # HOME set, and sources this file before that hook's early exit.
  local CUSTOM="$HOME/.oh-my-zsh/custom"
  clone_or_pull https://github.com/zsh-users/zsh-autosuggestions       "$CUSTOM/plugins/zsh-autosuggestions"
  clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting   "$CUSTOM/plugins/zsh-syntax-highlighting"
  clone_or_pull https://github.com/zsh-users/zsh-completions           "$CUSTOM/plugins/zsh-completions"
  clone_or_pull https://github.com/MichaelAquilina/zsh-you-should-use  "$CUSTOM/plugins/you-should-use"
  clone_or_pull https://github.com/Aloxaf/fzf-tab                      "$CUSTOM/plugins/fzf-tab"
  clone_or_pull https://github.com/paulirish/git-open                  "$CUSTOM/plugins/git-open"
  clone_or_pull https://github.com/romkatv/powerlevel10k               "$CUSTOM/themes/powerlevel10k"
  ok "plugins ready"
}

# ---------------------------------------------------------------------------
install_fzf_zoxide_direnv() {
  # These three ship official install scripts that already auto-detect
  # Linux vs macOS and the right arch — no branching needed here.
  if [ ! -d "$HOME/.fzf" ]; then
    git clone --depth 1 -q https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --bin --no-update-rc --no-key-bindings --no-completion >/dev/null
  fi
  command -v zoxide >/dev/null 2>&1 || curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash -s -- --bin-dir "$HOME/.local/bin" >/dev/null 2>&1
  command -v direnv >/dev/null 2>&1 || curl -sfL https://direnv.net/install.sh | bin_path="$HOME/.local/bin" bash >/dev/null 2>&1
  ok "fzf $(~/.fzf/bin/fzf --version 2>/dev/null | awk '{print $1}'), zoxide, direnv ready"
}

# ---------------------------------------------------------------------------
install_node_toolchain() {
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    local NVM_AUTH=(); [ -n "${GITHUB_TOKEN:-}" ] && NVM_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
    local NVM_TAG; NVM_TAG=$(curl -sS "${NVM_AUTH[@]}" https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | sed -E 's/.*"(v[0-9.]+)".*/\1/')
    [ -z "$NVM_TAG" ] && NVM_TAG="v0.40.6"
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" 2>/dev/null | bash >/dev/null 2>&1 \
      || echo "  !! nvm install script failed, skipping Node/Nest tooling (install nvm yourself: https://github.com/nvm-sh/nvm)" >&2
  fi
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # nvm.sh is not nounset-clean: `nvm use` dereferences unset variables, which
    # under this script's `set -u` doesn't just fail that command — it kills the
    # whole shell (exit 127), taking the rest of the run down with it, and
    # `|| true` can't catch it. Relax -u for the nvm calls only, then restore it.
    set +u
    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh"
    # -b downloads the prebuilt binary for this platform and never falls back to
    # compiling from source (nvm's default fallback needs a full C++ toolchain
    # and takes ~30 min on a fresh box). Older nvm builds predate -b, hence the
    # plain retry. Run unconditionally rather than gating on `command -v node`:
    # nvm install is idempotent, and a distro-packaged/Homebrew node on PATH
    # must not win here or the global installs below land in the wrong prefix.
    nvm install -b --lts >/dev/null 2>&1 || nvm install --lts >/dev/null 2>&1 \
      || echo "  !! nvm could not install a Node LTS release, skipping" >&2
    nvm alias default 'lts/*' >/dev/null 2>&1 || true
    # Activate it for the rest of this step so `npm i -g` writes into
    # $NVM_DIR/versions/node/<ver>/lib/node_modules, not a system prefix.
    nvm use --lts >/dev/null 2>&1 || true
    set -u
    if command -v npm >/dev/null 2>&1; then
      npm install -g @nestjs/cli typescript ts-node >/dev/null 2>&1 \
        || echo "  !! failed to install @nestjs/cli/typescript/ts-node globally (run 'npm i -g @nestjs/cli typescript ts-node' yourself later)" >&2
      # yarn/pnpm come from npm rather than `corepack enable`: corepack only
      # drops lazy shims that fetch the real package manager on first use (and
      # can refuse when a project pins a different `packageManager`), while it
      # is itself still flagged experimental. npm globals are real binaries,
      # available offline, and upgradeable with the same `npm i -g` everything
      # else here uses. Note they live under the active Node version, so a
      # later `nvm install` of a new major needs this step re-run (or
      # `nvm reinstall-packages <old-version>`).
      # Earlier versions of this script ran `corepack enable`, which leaves
      # corepack-owned yarn/pnpm shims in the very bin dir npm wants to write —
      # npm refuses to clobber files it doesn't own and the install dies with
      # EEXIST, silently leaving the old shims behind. `corepack disable`
      # removes only the shims corepack itself created, so it is safe to run
      # unconditionally and is a no-op on a machine that never enabled it.
      command -v corepack >/dev/null 2>&1 && corepack disable >/dev/null 2>&1 || true
      npm install -g yarn pnpm >/dev/null 2>&1 \
        || echo "  !! failed to install yarn/pnpm globally (run 'npm i -g yarn pnpm' yourself later)" >&2
    else
      echo "  !! npm not on PATH after nvm install, skipping global Node packages" >&2
    fi
    ok "node $(node --version 2>/dev/null || echo '?'), nest CLI + typescript, yarn $(yarn --version 2>/dev/null || echo '?') / pnpm $(pnpm --version 2>/dev/null || echo '?')"
  else
    echo "  !! nvm not available, skipping Node/Nest tooling" >&2
  fi
}

# ---------------------------------------------------------------------------
install_gcloud_sdk() {
  if [ ! -d "$HOME/google-cloud-sdk" ]; then
    curl -sS https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$HOME" >/dev/null 2>&1 \
      || echo "  !! Google Cloud SDK install failed, skipping (install manually: https://cloud.google.com/sdk/docs/install)" >&2
  fi
}

# ---------------------------------------------------------------------------
install_kubectl_bin() {
  # official binary, arch/OS-aware (K8S_OS/K8S_ARCH computed above), no
  # package manager needed on either platform.
  if ! command -v kubectl >/dev/null 2>&1; then
    local K8S_STABLE; K8S_STABLE=$(curl -sSL https://dl.k8s.io/release/stable.txt 2>/dev/null)
    if [ -n "$K8S_STABLE" ] && curl -sSL "https://dl.k8s.io/release/${K8S_STABLE}/bin/${K8S_OS}/${K8S_ARCH}/kubectl" -o "$HOME/.local/bin/kubectl"; then
      chmod +x "$HOME/.local/bin/kubectl"
    else
      echo "  !! kubectl download failed, skipping" >&2
    fi
  fi
}

install_kubectx_kubens() {
  # plain shell scripts, identical install on every OS
  if ! command -v kubectx >/dev/null 2>&1; then
    local KCTX_WORK; KCTX_WORK=$(mktemp -d)
    if git clone --depth=1 -q https://github.com/ahmetb/kubectx.git "$KCTX_WORK" 2>/dev/null; then
      cp "$KCTX_WORK/kubectx" "$KCTX_WORK/kubens" "$HOME/.local/bin/"
      chmod +x "$HOME/.local/bin/kubectx" "$HOME/.local/bin/kubens"
    else
      echo "  !! could not clone kubectx/kubens, skipping" >&2
    fi
    rm -rf "$KCTX_WORK"
  fi
}

install_helm_bin() {
  # official installer, arch/OS-aware, installed without sudo
  if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      | USE_SUDO=false HELM_INSTALL_DIR="$HOME/.local/bin" bash >/dev/null 2>&1 \
      || echo "  !! helm install script failed, skipping" >&2
  fi
}

# ---------------------------------------------------------------------------
install_claude_and_cursor() {
  # Claude Code (Anthropic's terminal coding agent) — official installer,
  # auto-detects OS/arch itself (Linux + macOS), no sudo, non-interactive,
  # lands at ~/.local/bin/claude which our PATH already covers.
  if ! command -v claude >/dev/null 2>&1; then
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
      || echo "  !! Claude Code installer failed, skipping (install manually: https://claude.ai/install.sh)" >&2
  fi

  # Cursor CLI (cursor-agent) — official installer, same shape as above:
  # auto-detects OS/arch, no sudo, non-interactive. Symlinks land at
  # ~/.local/bin/agent and ~/.local/bin/cursor-agent (both point to the same
  # binary; we guard on the more specific 'cursor-agent' name since a bare
  # 'agent' is generic enough that something else could already occupy it).
  if ! command -v cursor-agent >/dev/null 2>&1; then
    curl -fsSL https://cursor.com/install | bash >/dev/null 2>&1 \
      || echo "  !! Cursor CLI installer failed, skipping (install manually: https://cursor.com/install)" >&2
  fi
}

wire_up_delta_gitconfig() {
  # Wire up delta as git's diff pager if it installed successfully —
  # additive config keys only, won't touch user.name/user.email or anything
  # existing. Called after delta is installed regardless of which OS-specific
  # step installed it.
  if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta 2>/dev/null || true
    git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
    git config --global delta.navigate true 2>/dev/null || true
    git config --global merge.conflictstyle diff3 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
write_zshrc() {
  local PREV_ZSHRC_EXISTED=0
  if [ -f "$HOME/.zshrc" ]; then
    PREV_ZSHRC_EXISTED=1
    ZSHRC_BACKUP="$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
    cp "$HOME/.zshrc" "$ZSHRC_BACKUP"
  fi

  # ~/.zshrc.local: this function fully overwrites ~/.zshrc every run (that's
  # what makes re-runs reproducible), so anything hand-added directly to
  # ~/.zshrc — API tokens, personal aliases, machine-specific exports — gets
  # silently dropped on the next run. Created once here (never touched again
  # after) and sourced at the very end of the generated ~/.zshrc below, so
  # custom additions go here instead and survive every future re-run.
  if [ ! -f "$HOME/.zshrc.local" ]; then
    cat > "$HOME/.zshrc.local" <<'ZSHRC_LOCAL'
# Personal additions that should survive bootstrap re-runs go here — it's
# sourced from ~/.zshrc but never written to by the script itself.
# Examples: API tokens/exports, machine-specific PATH tweaks, personal aliases.
#
#   export GITHUB_ACCESS_TOKEN=...
ZSHRC_LOCAL
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
  gh
  tmux
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

# docker-compose (legacy hyphenated v1 syntax): apt/dnf/zypper installs of
# Docker only bring the newer `docker compose` (space) plugin, not this
# standalone binary — this is Docker's own documented fix for that gap.
# Checked at shell-startup time (not install time) and skipped if a real
# docker-compose binary is already present, so distros that ship the actual
# standalone binary (e.g. Arch, via pacman) keep using it untouched.
if ! command -v docker-compose >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  alias docker-compose='docker compose'
fi

# Personal additions (tokens, custom aliases, machine-specific exports) live
# in ~/.zshrc.local, which this script creates once and never overwrites —
# see the comment header in that file. Sourced last so it can override
# anything set above if needed.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
ZSHRC
  # shellcheck disable=SC2088 # intentional literal '~' for a human-readable path in the message, not expansion
  ok "~/.zshrc written (previous one backed up if it existed)"
  if [ "$PREV_ZSHRC_EXISTED" -eq 1 ]; then
    echo "  (~/.zshrc.local created for personal additions that survive future re-runs —"
    echo "   if your previous ~/.zshrc had custom lines like API tokens, check"
    echo "   $ZSHRC_BACKUP and move them into ~/.zshrc.local)"
  fi
}

# ---------------------------------------------------------------------------
set_default_shell() {
  if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
    chsh -s "$(command -v zsh)" || echo "  (run 'chsh -s \$(command -v zsh)' yourself if this failed non-interactively)"
  fi
  ok "default shell is zsh (or chsh command printed above)"
}
