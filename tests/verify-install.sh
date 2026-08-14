#!/usr/bin/env bash
# tests/verify-install.sh — run *after* a real bootstrap-zsh.sh execution
# (locally or in CI) to confirm the tools that should be on PATH actually
# are. This is a smoke test, not a correctness test: it checks presence,
# not behavior — pairs with tests/test-bootstrap.sh, which checks the
# OS/arch/package-manager detection logic in isolation without ever
# actually installing anything.
#
# Usage: ~/dotfiles/bootstrap-zsh.sh && ~/dotfiles/tests/verify-install.sh

set -uo pipefail

FAIL=0
ok()   { printf '\033[1;32m  ok\033[0m   %s\n' "$1"; }
bad()  { printf '\033[1;31m  MISSING\033[0m %s\n' "$1"; FAIL=1; }
warn() { printf '\033[1;33m  warn\033[0m %s\n' "$1"; }

check_bin() { # $1 = command name  $2 = optional: treat as non-fatal (warn instead of fail)
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 -> $(command -v "$1")"
  elif [ "${2:-}" = "soft" ]; then
    warn "$1 not found (best-effort install, not fatal for this check)"
  else
    bad "$1"
  fi
}

echo "== Terminal UX =="
check_bin zsh
check_bin git
check_bin fzf
check_bin zoxide
check_bin direnv
check_bin bat
check_bin eza
check_bin fd
check_bin rg
check_bin lazygit
check_bin glow

echo
echo "== Dev toolchain (best-effort in the script, so soft-checked here too) =="
# node/npm and the globals installed alongside them (nest, yarn, pnpm) live
# under nvm, which only reaches PATH through the shell rc file — this script
# runs under bash, so source nvm directly or every check below is a false
# negative.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
check_bin node soft
check_bin npm soft
check_bin nest soft
check_bin yarn soft
check_bin pnpm soft
check_bin psql soft
check_bin mongosh soft
check_bin redis-cli soft
check_bin aws soft
check_bin gcloud soft
check_bin docker soft
check_bin kubectl soft
check_bin k9s soft
check_bin kubectx soft
check_bin kubens soft
check_bin helm soft
check_bin jq soft
check_bin yq soft
check_bin gh soft
check_bin tmux soft
check_bin delta soft
check_bin xh soft
check_bin overmind soft
check_bin tldr soft
check_bin claude soft
check_bin cursor-agent soft

echo
echo "== Config files =="
if [ -f "$HOME/.zshrc" ]; then
  ok ".zshrc exists"
  if command -v zsh >/dev/null 2>&1 && zsh -n "$HOME/.zshrc"; then
    ok ".zshrc passes zsh -n"
  else
    bad ".zshrc syntax check (zsh -n)"
  fi
else
  bad ".zshrc"
fi

if [ -f "$HOME/.zshrc.local" ]; then
  ok ".zshrc.local exists (config-clobbering fix)"
else
  bad ".zshrc.local"
fi

if grep -q 'zshrc.local' "$HOME/.zshrc" 2>/dev/null; then
  ok ".zshrc sources .zshrc.local"
else
  bad ".zshrc does not source .zshrc.local"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL REQUIRED CHECKS PASSED (soft-checked dev-toolchain tools that were missing, if any, are warnings above)"
  exit 0
else
  echo "SOME REQUIRED CHECKS FAILED"
  exit 1
fi
