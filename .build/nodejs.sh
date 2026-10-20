#!/usr/bin/env bash
# Node.js - 독립 실행 스크립트 (Linux). 이 파일 하나만 프로젝트에 복사하면 된다.
# 도구는 스크립트 옆 nodejs/ 폴더에 설치된다.
#   bash nodejs.sh [install|verify|update|reset --yes|env|run -- cmd|vue-init] [옵션]
#   현재 셸에 환경 적용: source nodejs.sh      (source 시에는 환경만 적용)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LANG_NAME=nodejs
STATE="$ROOT/$LANG_NAME/_state"
pbk_path() { local p; for p in "$@"; do if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi; done; export PATH; }
activate() {
 export npm_config_cache="$ROOT/nodejs/npm-cache" npm_config_prefix="$ROOT/nodejs/npm-global" npm_config_userconfig="$ROOT/nodejs/npmrc" COREPACK_HOME="$ROOT/nodejs/corepack" npm_config_update_notifier=false
 pbk_path "$ROOT/nodejs/node/bin"
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
case "$(uname -s)" in Linux) ;; *) fail 'This .sh supports Linux. For Windows use nodejs.ps1.';; esac
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
NODE_MAJOR=24 PROJECT="$PWD"
install_nodejs() {
 [[ -x "$ROOT/nodejs/node/bin/node" ]] && { log 'node already present'; return; }
 local sums filename expected tmp
 sums="$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt")"
 filename="$(printf '%s\n' "$sums" | awk -v m="$NODE_MAJOR" -v a="$([[ "$host_arch" == x64 ]] && echo x64 || echo arm64)" '$2 ~ ("^node-v" m "[.]" ) && $2 ~ ("-linux-" a "[.]tar[.]gz$") {print $2;exit}')"
 [[ -n "$filename" ]] || fail "No Node LTS archive for Linux $host_arch"
 expected="$(printf '%s\n' "$sums" | awk -v f="$filename" '$2==f {print $1;exit}')"
 tmp="$STATE/$filename"; fetch "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/$filename" "$tmp"; sha_check "$tmp" "$expected"
 mkdir -p "$ROOT/nodejs/node"; extract_one "$tmp" "$ROOT/nodejs/node"; rm -f "$tmp"
}
do_install() { install_nodejs; }
do_verify() { "$ROOT/nodejs/node/bin/node" --version; "$ROOT/nodejs/node/bin/npm" --version; }
do_update() {
 local old="$STATE/update-backup-nodejs" latest latest_version
 [[ -x "$ROOT/nodejs/node/bin/node" ]] || fail 'Node.js missing. Run install first.'
 latest="$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt" | grep -oE 'node-v[0-9]+\.[0-9]+\.[0-9]+-linux-' | head -n 1 || true)"
 latest_version="${latest#node-}"; latest_version="${latest_version%-linux-}"
 [[ "$latest_version" == v* ]] || fail 'Cannot resolve latest Node.js version'
 if [[ "$("$ROOT/nodejs/node/bin/node" --version)" == "$latest_version" ]]; then log "Node.js already at $latest_version"; return; fi
 [[ ! -e "$old" ]] || fail "Incomplete previous update exists: $old"
 mkdir -p "$STATE"; mv "$ROOT/nodejs/node" "$old"
 if (install_nodejs); then rm -rf -- "$old"; else
  rm -rf -- "$ROOT/nodejs/node"; mv "$old" "$ROOT/nodejs/node"; fail 'Node.js upgrade failed; previous toolchain restored'
 fi
}
# 빈 폴더(--project, 기본: 현재 폴더)에 Vue(TypeScript) 프로젝트 생성
vue_init() {
 install_nodejs; activate
 [[ -d "$PROJECT" ]] || fail "Project directory not found: $PROJECT"
 [[ -z "$(find "$PROJECT" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "Vue scaffold target must be empty: $PROJECT"
 # create-vue --typescript 플래그가 대화형 기능 선택을 생략시킨다
 (cd "$PROJECT" && npm create vue@latest -- --typescript .)
}

ACTION=install; YES=0; RUN_ARGS=()
if (($#)) && [[ "$1" != -* ]]; then ACTION="$1"; shift; fi
while (($#)); do
 case "$1" in
  --yes) YES=1; shift;;
  --) shift; RUN_ARGS=("$@"); break;;
  --node-major) NODE_MAJOR="${2:?}"; shift 2;;
  --project) PROJECT="${2:?}"; shift 2;;
  -h|--help) echo "Usage: bash $LANG_NAME.sh install|verify|update|reset --yes|env|run -- cmd|vue-init"; exit 0;;
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
 vue-init) vue_init;;
 *) fail "Unsupported action: $ACTION";;
esac
