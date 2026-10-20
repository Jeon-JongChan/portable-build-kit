#!/usr/bin/env bash
# C# (.NET) - 독립 실행 스크립트 (Linux). 이 파일 하나만 프로젝트에 복사하면 된다.
# 도구는 스크립트 옆 csharp/ 폴더에 설치된다.
#   bash csharp.sh [install|verify|update|reset --yes|env|run -- cmd] [옵션]
#   현재 셸에 환경 적용: source csharp.sh      (source 시에는 환경만 적용)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LANG_NAME=csharp
STATE="$ROOT/$LANG_NAME/_state"
pbk_path() { local p; for p in "$@"; do if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi; done; export PATH; }
activate() {
 # ponytail: invariant avoids hard ICU dependency on minimal Linux; drop when full globalization needed
 export DOTNET_ROOT="$ROOT/csharp/dotnet" DOTNET_CLI_HOME="$ROOT/csharp/home" NUGET_PACKAGES="$ROOT/csharp/nuget" DOTNET_MULTILEVEL_LOOKUP=0 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
 pbk_path "$ROOT/csharp/dotnet"
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
case "$(uname -s)" in Linux) ;; *) fail 'This .sh supports Linux. For Windows use csharp.ps1.';; esac
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
DOTNET_CHANNEL=10.0
dotnet_install() {
 mkdir -p "$ROOT/csharp/dotnet"
 fetch 'https://dot.net/v1/dotnet-install.sh' "$STATE/dotnet-install.sh"
 bash "$STATE/dotnet-install.sh" --channel "$DOTNET_CHANNEL" --install-dir "$ROOT/csharp/dotnet" --no-path
}
do_install() { [[ -x "$ROOT/csharp/dotnet/dotnet" ]] && { log 'dotnet already present'; return; }; dotnet_install; }
do_verify() { dotnet --version; }
do_update() { [[ -x "$ROOT/csharp/dotnet/dotnet" ]] || fail '.NET missing. Run install first.'; dotnet_install; }

ACTION=install; YES=0; RUN_ARGS=()
if (($#)) && [[ "$1" != -* ]]; then ACTION="$1"; shift; fi
while (($#)); do
 case "$1" in
  --yes) YES=1; shift;;
  --) shift; RUN_ARGS=("$@"); break;;
  --dotnet-channel) DOTNET_CHANNEL="${2:?}"; shift 2;;
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
