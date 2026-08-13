#!/usr/bin/env bash
# tests/test-bootstrap.sh — exercise every OS / arch / package-manager branch
# of ../bootstrap-zsh.sh without touching the real system: no sudo, no
# network installs, no file writes outside a scratch dir.
#
# How it works: bootstrap-zsh.sh has a BOOTSTRAP_SELF_TEST=1 hook that prints
# its OS/ARCH/PKG_MGR detection result and exits before doing anything real.
# For each case we run the real script under `env -i` (a completely empty
# environment) with only a fake PATH containing the `uname`/package-manager
# shims that case should see — so the host's real apt-get etc. can never
# leak in and produce a false pass.
#
# Usage: ./tests/test-bootstrap.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/../bootstrap-zsh.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Resolve bash's real absolute path *before* we start restricting PATH in
# subshells, and invoke it by that absolute path — env -i wipes PATH, and if
# we invoked "bash" by name the shell would need PATH just to find bash.
BASH_BIN="$(command -v bash)"

PASS=0
FAIL=0

fake_bin_dir() { # $1 = label -> returns dir path via echo
  local dir="$WORK/bin-$1"
  mkdir -p "$dir"
  echo "$dir"
}
add_fake() { # $1 = dir  $2 = command name — a no-op stub, always exits 0
  cat > "$1/$2" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$1/$2"
}
add_fake_uname() { # $1 = dir  $2 = OS (uname -s)  $3 = arch (uname -m)
  cat > "$1/uname" <<EOF
#!/bin/sh
case "\$1" in
  -s) echo "$2" ;;
  -m) echo "$3" ;;
  *) echo "unknown" ;;
esac
EOF
  chmod +x "$1/uname"
}

# run_case: $1=name $2=uname-s $3=uname-m $4="space separated fake pkg-mgr
# binaries" $5=expected-regex-against-stdout $6="fail" to instead assert a
# non-zero exit (used for the OS/arch guard clauses, which fire *before* the
# self-test hook and therefore always exit non-zero regardless of the flag).
run_case() {
  local name="$1" os="$2" arch="$3" mgrs="$4" expect="$5" mode="${6:-pass}"
  local dir; dir="$(fake_bin_dir "$name")"
  add_fake_uname "$dir" "$os" "$arch"
  for m in $mgrs; do add_fake "$dir" "$m"; done

  local out status
  out="$(env -i PATH="$dir" BOOTSTRAP_SELF_TEST=1 "$BASH_BIN" "$BOOTSTRAP" 2>&1)"
  status=$?

  if [ "$mode" = "fail" ]; then
    if [ "$status" -ne 0 ]; then
      echo "PASS: $name (correctly exited non-zero)"
      PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected non-zero exit, got 0. Output: $out"
      FAIL=$((FAIL+1))
    fi
    return
  fi

  if [ "$status" -eq 0 ] && [[ "$out" =~ $expect ]]; then
    echo "PASS: $name -> $out"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name — expected match /$expect/, got (exit $status): $out"
    FAIL=$((FAIL+1))
  fi
}

echo "== 1. Syntax check =="
if bash -n "$BOOTSTRAP"; then
  echo "PASS: bash -n"
  PASS=$((PASS+1))
else
  echo "FAIL: bash -n reported a syntax error"
  FAIL=$((FAIL+1))
fi

if command -v zsh >/dev/null 2>&1; then
  # The generated ~/.zshrc lives inside a 'cat > ... <<ZSHRC ... ZSHRC' heredoc.
  # Extract it and syntax-check it on its own with zsh -n.
  ZSHRC_TMP="$WORK/generated.zshrc"
  awk '/^cat > "\$HOME\/\.zshrc" <<.ZSHRC.$/{flag=1; next} /^ZSHRC$/{flag=0} flag' "$BOOTSTRAP" > "$ZSHRC_TMP"
  if [ -s "$ZSHRC_TMP" ] && zsh -n "$ZSHRC_TMP"; then
    echo "PASS: zsh -n on generated .zshrc"
    PASS=$((PASS+1))
  else
    echo "FAIL: generated .zshrc failed zsh -n (or heredoc extraction found nothing)"
    FAIL=$((FAIL+1))
  fi
else
  echo "SKIP: zsh not on PATH, cannot syntax-check generated .zshrc"
fi

echo
echo "== 2. OS / arch / package-manager detection matrix =="
run_case "ubuntu-x86_64 (apt)"      Linux  x86_64  "apt-get" \
  "PKG_MGR=apt .*GNU_ARCH=x86_64-unknown-linux-gnu .*MUSL_ARCH=x86_64-unknown-linux-musl .*LG_ARCH=x86_64"

run_case "ubuntu-aarch64 (apt)"     Linux  aarch64 "apt-get" \
  "PKG_MGR=apt .*GNU_ARCH=aarch64-unknown-linux-gnu .*MUSL_ARCH=aarch64-unknown-linux-musl .*LG_ARCH=arm64"

run_case "fedora-x86_64 (dnf)"      Linux  x86_64  "dnf" \
  "PKG_MGR=dnf"

run_case "arch-aarch64 (pacman)"    Linux  aarch64 "pacman" \
  "PKG_MGR=pacman .*LG_ARCH=arm64"

run_case "opensuse-x86_64 (zypper)" Linux  x86_64  "zypper" \
  "PKG_MGR=zypper"

run_case "macos-arm64 (brew)"       Darwin arm64   "brew" \
  "OS_NAME=Darwin ARCH=arm64 PKG_MGR=brew GNU_ARCH= MUSL_ARCH= LG_ARCH="

run_case "macos-x86_64 (brew)"      Darwin x86_64  "brew" \
  "OS_NAME=Darwin ARCH=x86_64 PKG_MGR=brew"

run_case "macos never needs a Linux pkg mgr even if one is on PATH" \
  Darwin arm64 "apt-get" "PKG_MGR=brew"

# Package-manager precedence: if multiple happen to be on PATH, apt wins
# (matches the if/elif order in the script).
run_case "apt takes precedence over dnf when both present" Linux x86_64 "apt-get dnf" \
  "PKG_MGR=apt"

# No known package manager on PATH -> detection correctly settles on "none".
# (This is the exact condition that makes step 1's real case statement hit
# its `*) exit 1` arm; the self-test hook intentionally returns before step 1
# runs, so we assert the detection input to that decision, not the exit.)
run_case "Linux with no known package manager detected as none" Linux x86_64 "" \
  "PKG_MGR=none"

echo
echo "== 3. Negative cases (OS/arch guard clauses — fire before self-test hook) =="
run_case "unsupported OS (FreeBSD)" FreeBSD x86_64 "" "" fail
run_case "unsupported Linux arch (riscv64)" Linux riscv64 "apt-get" "" fail

echo
echo "============================================================"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
