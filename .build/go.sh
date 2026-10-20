#!/usr/bin/env bash
# Go - 독립 실행 스크립트 (Linux). 이 파일 하나만 프로젝트에 복사하면 된다.
# 도구는 스크립트 옆 go/ 폴더에 설치된다.
#   bash go.sh [install|verify|update|reset --yes|env|run -- cmd] [옵션]
#   현재 셸에 환경 적용: source go.sh      (source 시에는 환경만 적용)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LANG_NAME=go
STATE="$ROOT/$LANG_NAME/_state"
pbk_path() { local p; for p in "$@"; do if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi; done; export PATH; }
activate() {
 export GOROOT="$ROOT/go/sdk" GOPATH="$ROOT/go/path" GOMODCACHE="$ROOT/go/path/pkg/mod" GOCACHE="$ROOT/go/cache" GOENV="$ROOT/go/goenv" GOTOOLCHAIN=local
 pbk_path "$ROOT/go/sdk/bin"
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
case "$(uname -s)" in Linux) ;; *) fail 'This .sh supports Linux. For Windows use go.ps1.';; esac
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
GO_VERSION=1.27.2 GO_VERSION_EXPLICIT=0
install_go() {
 [[ -x "$ROOT/go/sdk/bin/go" ]] && { log 'go already present'; return; }
 requires awk
 # ponytail: split locals — bash set -u treats `$name` as unbound in the same `local` line
 local name="go${GO_VERSION}.linux-${go_arch}.tar.gz" meta checksum tmp
 tmp="$STATE/$name"
 # include=all: 기본 목록은 최신 패치만 담아 고정 버전이 새 패치 출시 즉시 사라짐
 meta="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all')"
 # here-string: 파이프로 넘기면 awk 조기 exit 시 대용량 JSON의 printf가 SIGPIPE → pipefail로 중단
 checksum="$(awk -F'"' -v n="$name" 'index($0,"\"filename\"") {hit=(index($0,n)>0)} hit && index($0,"\"sha256\"") {print $4;exit}' <<<"$meta")"
 [[ "${#checksum}" -eq 64 ]] || fail "Cannot validate Go checksum for $name (version may be unavailable)"
 fetch "https://go.dev/dl/$name" "$tmp"; sha_check "$tmp" "$checksum"
 mkdir -p "$ROOT/go/sdk"; extract_one "$tmp" "$ROOT/go/sdk"; rm -f "$tmp"
 log 'Installed Go.'
}
latest_go_version() {
 local version
 version="$(curl -fsSL 'https://go.dev/dl/?mode=json' | grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"go[0-9]+\.[0-9]+(\.[0-9]+)?"' | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
 [[ -n "$version" ]] || fail 'Unable to resolve latest stable Go version'
 printf '%s' "${version#go}"
}
do_install() { install_go; }
do_verify() { go version; }
do_update() {
 local old="$STATE/update-backup-go"
 [[ -x "$ROOT/go/sdk/bin/go" ]] || fail 'Go missing. Run install first.'
 ((GO_VERSION_EXPLICIT)) || GO_VERSION="$(latest_go_version)"
 if [[ "$("$ROOT/go/sdk/bin/go" version)" == *"go${GO_VERSION} "* ]]; then log "Go already at $GO_VERSION"; return; fi
 [[ ! -e "$old" ]] || fail "Incomplete previous update exists: $old"
 mkdir -p "$STATE"; mv "$ROOT/go/sdk" "$old"
 if (install_go); then rm -rf -- "$old"; else
  rm -rf -- "$ROOT/go/sdk"; mv "$old" "$ROOT/go/sdk"; fail 'Go upgrade failed; previous toolchain restored'
 fi
}

ACTION=install; YES=0; RUN_ARGS=()
if (($#)) && [[ "$1" != -* ]]; then ACTION="$1"; shift; fi
while (($#)); do
 case "$1" in
  --yes) YES=1; shift;;
  --) shift; RUN_ARGS=("$@"); break;;
  --go-version) GO_VERSION="${2:?}"; GO_VERSION_EXPLICIT=1; shift 2;;
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
