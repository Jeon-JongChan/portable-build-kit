#!/usr/bin/env bash
# Install (go+python) → global-on (~/.bashrc) → login shell runs tools → global-off.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
kit="$scratch/.build"
mark='# >>> portable-build-kit managed >>>'
global_on=0
cleanup() {
  if [[ "$global_on" -eq 1 ]]; then
    echo '[global] SAFETY global-off...'
    bash "$kit/setup.sh" configure --mode global-off >/dev/null 2>&1 || true
  fi
  # belt: strip managed block if orphaned
  if [[ -f "$HOME/.bashrc" ]] && grep -Fq "$mark" "$HOME/.bashrc"; then
    if [[ -f "$kit/_state/global-bash-enabled" ]] || grep -Fq "$scratch" "$HOME/.bashrc"; then
      bash "$kit/setup.sh" configure --mode global-off >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
cp -a "$root/.build" "$scratch/"

echo '[global] install go + python + csharp...'
bash "$kit/go.sh" install
bash "$kit/python.sh" install
bash "$kit/csharp.sh" install
# rust install ok without cc; skip cargo build in probe

echo '[global] global-on...'
bash "$kit/setup.sh" configure --mode global-on
global_on=1
[[ -f "$kit/_state/global-bash-enabled" ]] || { echo 'marker missing'; exit 1; }
grep -Fq "$mark" "$HOME/.bashrc" || { echo 'bashrc block missing'; exit 1; }

echo '[global] login shell probe...'
# bashrc is for interactive login shells
out="$(bash -lic 'go version; python --version; uv --version; dotnet --version; echo GOROOT=$GOROOT; echo DOTNET_ROOT=$DOTNET_ROOT; echo PROBE_PASS' 2>&1)" || {
  echo "$out"; echo 'login probe failed'; exit 1
}
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q 'PROBE_PASS' || { echo 'no PROBE_PASS'; exit 1; }
printf '%s\n' "$out" | grep -q "$scratch" || { echo 'GOROOT not kit-isolated'; exit 1; }
printf '%s\n' "$out" | grep -q 'DOTNET_ROOT=.*'"$scratch" || { echo 'DOTNET_ROOT not kit-isolated'; exit 1; }

echo '[global] global-off...'
bash "$kit/setup.sh" configure --mode global-off
global_on=0
[[ ! -f "$kit/_state/global-bash-enabled" ]] || { echo 'marker remains'; exit 1; }
if grep -Fq "$mark" "$HOME/.bashrc" 2>/dev/null; then
  echo 'bashrc managed block remains'; exit 1
fi

out2="$(bash -lic 'echo GOROOT=${GOROOT:-}; echo RESTORE_PASS' 2>&1)" || true
printf '%s\n' "$out2"
printf '%s\n' "$out2" | grep -q 'RESTORE_PASS' || { echo 'restore probe failed'; exit 1; }
if printf '%s\n' "$out2" | grep -q "$scratch"; then
  echo 'scratch path still in login env after global-off'; exit 1
fi

echo 'INDEP Linux global-on/off+run: PASS'
