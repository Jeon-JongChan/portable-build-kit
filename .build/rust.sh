#!/usr/bin/env bash
# Rust - 독립 실행 스크립트 (Linux). 이 파일 하나만 프로젝트에 복사하면 된다.
# 도구는 스크립트 옆 rust/ 폴더에 설치된다.
#   bash rust.sh [install|verify|update|reset --yes|env|run -- cmd] [옵션]
#   현재 셸에 환경 적용: source rust.sh      (source 시에는 환경만 적용)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LANG_NAME=rust
STATE="$ROOT/$LANG_NAME/_state"
pbk_path() { local p; for p in "$@"; do if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi; done; export PATH; }
activate() {
 export RUSTUP_HOME="$ROOT/rust/rustup" CARGO_HOME="$ROOT/rust/cargo"
 pbk_path "$ROOT/rust/cargo/bin"
}

# source 로 불러오면 환경만 적용하고 호출자 셸 옵션(set -e 등)은 건드리지 않는다
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
 activate; unset -f activate pbk_path; unset ROOT LANG_NAME STATE
 return 0
fi
set -euo pipefail
log() { printf '[build-kit] %s\n' "$*"; }
fail() { echo "[build-kit] ERROR: $*" >&2; exit 1; }
requires() { command -v "$1" >/dev/null 2>&1 || fail "Host command missing: $1"; }
case "$(uname -s)" in Linux) ;; *) fail 'This .sh supports Linux. For Windows use rust.ps1.';; esac
case "$(uname -m)" in x86_64|amd64) host_arch=x64; go_arch=amd64; rust_arch=x86_64;; aarch64|arm64) host_arch=aarch64; go_arch=arm64; rust_arch=aarch64;; *) fail "Unsupported CPU $(uname -m)";; esac
fetch() { requires curl; mkdir -p "$(dirname "$2")"; curl --fail --location --retry 3 --connect-timeout 20 --output "$2" "$1"; }
sha_check() {
 local file="$1" expected="$2" actual
 requires sha256sum
 actual="$(sha256sum "$file" | awk '{print $1}')"
 [[ "${actual,,}" == "${expected,,}" ]] || fail "SHA256 mismatch: $file"
}
extract_one() {
 local archive="$1" into="$2" staging="$STATE/extract.$$"
 mkdir -p "$staging" "$into"
 # 명시적 || fail: update의 `if (install_x)` 안에서는 set -e가 꺼져 실패한 압축 해제가 성공으로 보고된다
 if [[ "$archive" == *.zip ]]; then requires unzip; unzip -q "$archive" -d "$staging" || fail "Cannot extract $archive"; else requires tar; tar -xf "$archive" -C "$staging" || fail "Cannot extract $archive"; fi
 local dirs=("$staging"/*)
 if [[ ${#dirs[@]} -eq 1 && -d ${dirs[0]} ]]; then cp -a "${dirs[0]}/." "$into/" || fail "Cannot copy into $into"; else cp -a "$staging/." "$into/" || fail "Cannot copy into $into"; fi
 rm -rf "$staging"
}
:
do_install() {
 [[ -x "$ROOT/rust/cargo/bin/cargo" ]] && { log 'rust already present'; return; }
 local uri="https://static.rust-lang.org/rustup/dist/${rust_arch}-unknown-linux-gnu/rustup-init" tmp="$STATE/rustup-init" expected
 fetch "$uri.sha256" "$tmp.sha256"; expected="$(awk '{print $1}' "$tmp.sha256")"
 [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || fail 'Rustup hash unavailable'
 fetch "$uri" "$tmp"; sha_check "$tmp" "$expected"; chmod +x "$tmp"
 activate; "$tmp" -y --no-modify-path --profile minimal --default-toolchain stable
 rm -f "$tmp" "$tmp.sha256"
 if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
  log 'WARNING: no system C linker (cc/gcc). rustc installs, but cargo build needs build-essential (or equivalent).'
 fi
}
do_verify() { rustc --version; }
do_update() {
 [[ -x "$ROOT/rust/cargo/bin/rustup" ]] || fail 'Rust missing. Run install first.'
 activate; rustup set profile minimal; rustup update stable
}

ACTION=install; YES=0; RUN_ARGS=()
if (($#)) && [[ "$1" != -* ]]; then ACTION="$1"; shift; fi
while (($#)); do
 case "$1" in
  --yes) YES=1; shift;;
  --) shift; RUN_ARGS=("$@"); break;;

  -h|--help) echo "Usage: bash $LANG_NAME.sh install|verify|update|reset --yes|env|run -- cmd"; exit 0;;
  *) fail "Unknown option: $1";;
 esac
done

case "$ACTION" in
 install) do_install;;
 verify) activate; do_verify;;
 update) do_update;;
 reset)
  ((YES)) || fail 'Reset deletes tools; pass --yes after reviewing.'
  rm -rf -- "$ROOT/$LANG_NAME"; log "Removed $LANG_NAME";;
 env) printf 'Run in current shell: source %q\n' "$ROOT/$LANG_NAME.sh";;
 run) activate; ((${#RUN_ARGS[@]})) || fail 'run requires -- command [args]'; "${RUN_ARGS[@]}";;

 *) fail "Unsupported action: $ACTION";;
esac
