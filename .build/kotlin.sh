#!/usr/bin/env bash
# Kotlin / Android (JDK + Android SDK) - 독립 실행 스크립트 (Linux). 이 파일 하나만 프로젝트에 복사하면 된다.
# 도구는 스크립트 옆 kotlin/ 폴더에 설치된다.
#   bash kotlin.sh [install|verify|update|reset --yes|env|run -- cmd|emulator-install|emulator-list|emulator-start|emulator-remove] [옵션]
#   현재 셸에 환경 적용: source kotlin.sh      (source 시에는 환경만 적용)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LANG_NAME=kotlin
STATE="$ROOT/$LANG_NAME/_state"
pbk_path() { local p; for p in "$@"; do if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi; done; export PATH; }
activate() {
 export JAVA_HOME="$ROOT/kotlin/jdk" ANDROID_HOME="$ROOT/kotlin/android-sdk" ANDROID_SDK_ROOT="$ROOT/kotlin/android-sdk" GRADLE_USER_HOME="$ROOT/kotlin/gradle" ANDROID_USER_HOME="$ROOT/kotlin/android-user" ANDROID_PREFS_ROOT="$ROOT/kotlin/android-user" ANDROID_EMULATOR_HOME="$ROOT/kotlin/android-user" ANDROID_AVD_HOME="$ROOT/kotlin/android-user/avd"
 pbk_path "$ROOT/kotlin/jdk/bin" "$ROOT/kotlin/android-sdk/cmdline-tools/latest/bin" "$ROOT/kotlin/android-sdk/platform-tools" "$ROOT/kotlin/android-sdk/emulator"
 local d
 if [[ -d "$ROOT/kotlin/android-sdk/ndk" ]]; then
  for d in "$ROOT/kotlin/android-sdk/ndk"/*; do
   if [[ -d "$d" ]]; then export NDK_HOME="$d" ANDROID_NDK_HOME="$d"; break; fi
  done
 fi
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
case "$(uname -s)" in Linux) ;; *) fail 'This .sh supports Linux. For Windows use kotlin.ps1.';; esac
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
ANDROID_API=36 BUILD_TOOLS=36.0.0 JDK_MAJOR=21 NDK_VERSION=27.2.12479018 WITH_NDK=0 WITH_ADB=0 ACCEPT_LICENSES=0
EMULATOR_ABI=x86_64 EMULATOR_FLAVOR=google_apis AVD_NAME=pbk_android EMULATOR_HEADLESS=0 PURGE_EMULATOR_PACKAGES=0
install_kotlin() {
 [[ "$host_arch" == x64 ]] || fail 'Android CLI tools Linux archive currently requires x64 host in this script'
 local jdk="$ROOT/kotlin/jdk" sdk="$ROOT/kotlin/android-sdk" tmp api checksum
 if [[ ! -x "$jdk/bin/java" ]]; then
  api="https://api.adoptium.net/v3/assets/latest/${JDK_MAJOR}/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse"
  checksum="$(curl -fsSL "$api" | grep -oE '"checksum"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{64}"' | head -n 1 | grep -oE '[0-9a-fA-F]{64}' || true)"
  [[ ${#checksum} -eq 64 ]] || fail 'Cannot obtain verified Temurin JDK checksum'
  tmp="$STATE/temurin.tar.gz"
  fetch "https://api.adoptium.net/v3/binary/latest/${JDK_MAJOR}/ga/linux/x64/jdk/hotspot/normal/eclipse" "$tmp"
  sha_check "$tmp" "$checksum"; mkdir -p "$jdk"; extract_one "$tmp" "$jdk"; rm -f "$tmp"
 fi
 if [[ ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
  tmp="$STATE/android-cli.zip"
  fetch 'https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip' "$tmp"
  sha_check "$tmp" '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583'
  mkdir -p "$sdk/cmdline-tools/latest"
  extract_one "$tmp" "$sdk/cmdline-tools/latest"; rm -f "$tmp"
  # 압축 안에 cmdline-tools/ 가 한 겹 더 있으면 한 단계 올린다
  if [[ -d "$sdk/cmdline-tools/latest/cmdline-tools" ]]; then
   mv "$sdk/cmdline-tools/latest/cmdline-tools/"* "$sdk/cmdline-tools/latest/"
   rmdir "$sdk/cmdline-tools/latest/cmdline-tools"
  fi
 fi
 activate
 local mgr="$sdk/cmdline-tools/latest/bin/sdkmanager"
 if ((ACCEPT_LICENSES)); then
  local answers="$STATE/android-licenses.txt"
  for _ in $(seq 1 80); do printf 'y\n'; done > "$answers"
  "$mgr" --sdk_root="$sdk" --licenses < "$answers"; rm -f "$answers"
 else
  log 'Android licenses NOT auto-accepted. If SDK download is blocked, rerun with --accept-android-licenses after reviewing licenses.'
 fi
 local packages=("platforms;android-${ANDROID_API}" "build-tools;${BUILD_TOOLS}")
 if ((WITH_ADB)); then packages+=("platform-tools"); fi
 if ((WITH_NDK)); then packages+=("ndk;${NDK_VERSION}"); fi
 "$mgr" --sdk_root="$sdk" --install "${packages[@]}"
 log "Android SDK installed: API ${ANDROID_API}, Build Tools ${BUILD_TOOLS}; no emulator/system images."
}
do_install() { install_kotlin; }
do_verify() { java -version; sdkmanager --sdk_root="$ANDROID_HOME" --list_installed; }
do_update() {
 [[ -x "$ROOT/kotlin/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]] || fail 'Android SDK missing. Run install first.'
 # sdkmanager --update 는 원치 않는 플랫폼/버전을 추가할 수 있어 쓰지 않는다
 install_kotlin
 log 'Ensured exact requested API/build-tools/NDK selection. JDK & CLI tool upgrades require separate tested version pins.'
}
# 선택 기능: Android 에뮬레이터 (기본 설치에는 포함되지 않음)
android_image_package() { printf 'system-images;android-%s;%s;%s' "$ANDROID_API" "$EMULATOR_FLAVOR" "$EMULATOR_ABI"; }
android_emulator_ready() {
 [[ -x "$ROOT/kotlin/android-sdk/cmdline-tools/latest/bin/avdmanager" ]] || fail 'Android tools absent: install Kotlin first'
 activate
 mkdir -p "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME"
}
emulator_install() {
 [[ "$host_arch" == x64 ]] || fail 'This implementation only installs the Android emulator on Linux x86_64'
 install_kotlin
 android_emulator_ready
 local sdk="$ROOT/kotlin/android-sdk" package
 package="$(android_image_package)"
 "$sdk/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$sdk" --install emulator platform-tools "$package"
 [[ -x "$sdk/emulator/emulator" ]] || fail 'Android emulator executable missing after SDK installation'
 if [[ -f "$ANDROID_AVD_HOME/$AVD_NAME.ini" ]]; then log "AVD already exists: $AVD_NAME"; return; fi
 printf 'no\n' | "$sdk/cmdline-tools/latest/bin/avdmanager" create avd -n "$AVD_NAME" -k "$package" --force
 [[ -f "$ANDROID_AVD_HOME/$AVD_NAME.ini" ]] || fail 'AVD was not created under the portable Android AVD directory'
 log "Installed emulator + single system image ($package); AVD=$AVD_NAME"
}
emulator_list() {
 android_emulator_ready
 "$ROOT/kotlin/android-sdk/cmdline-tools/latest/bin/avdmanager" list avd
 if [[ -x "$ROOT/kotlin/android-sdk/emulator/emulator" ]]; then "$ROOT/kotlin/android-sdk/emulator/emulator" -list-avds; fi
}
emulator_start() {
 android_emulator_ready
 [[ -f "$ANDROID_AVD_HOME/$AVD_NAME.ini" ]] || fail "AVD not installed: $AVD_NAME. Run emulator-install first"
 local exe="$ROOT/kotlin/android-sdk/emulator/emulator" log_file="$ANDROID_EMULATOR_HOME/${AVD_NAME}-emulator.log"
 [[ -x "$exe" ]] || fail 'Emulator package missing'
 local flags=(-avd "$AVD_NAME" -no-snapshot)
 if ((EMULATOR_HEADLESS)); then flags+=(-no-window -no-audio); fi
 nohup "$exe" "${flags[@]}" > "$log_file" 2>&1 < /dev/null &
 log "Emulator launched (pid=$!, log=$log_file). Hardware virtualization and host graphics are required for acceleration."
}
emulator_remove() {
 android_emulator_ready
 local avd="$ROOT/kotlin/android-sdk/cmdline-tools/latest/bin/avdmanager" sdk="$ROOT/kotlin/android-sdk" package
 if [[ -f "$ANDROID_AVD_HOME/$AVD_NAME.ini" ]]; then "$avd" delete avd -n "$AVD_NAME"; log "AVD removed: $AVD_NAME"
 else log "AVD absent: $AVD_NAME"; fi
 if ((PURGE_EMULATOR_PACKAGES)); then
  # 다른 AVD가 공유 중인 패키지는 삭제하지 않는다
  if find "$ANDROID_AVD_HOME" -maxdepth 1 -name '*.ini' -print -quit | grep -q .; then
   fail 'Other AVDs exist; only selected AVD deleted. Refusing to uninstall shared system image/emulator.'
  fi
  package="$(android_image_package)"
  "$sdk/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$sdk" --uninstall "$package" emulator
  log 'Emulator package and selected system image removed (ADB retained).'
 fi
}

ACTION=install; YES=0; RUN_ARGS=()
if (($#)) && [[ "$1" != -* ]]; then ACTION="$1"; shift; fi
while (($#)); do
 case "$1" in
  --yes) YES=1; shift;;
  --) shift; RUN_ARGS=("$@"); break;;
  --android-api) ANDROID_API="${2:?}"; shift 2;;
  --build-tools) BUILD_TOOLS="${2:?}"; shift 2;;
  --ndk-version) NDK_VERSION="${2:?}"; shift 2;;
  --with-ndk) WITH_NDK=1; shift;;
  --with-adb) WITH_ADB=1; shift;;
  --jdk-major) JDK_MAJOR="${2:?}"; shift 2;;
  --accept-android-licenses) ACCEPT_LICENSES=1; shift;;
  --emulator-abi) EMULATOR_ABI="${2:?}"; shift 2;;
  --emulator-flavor) EMULATOR_FLAVOR="${2:?}"; shift 2;;
  --avd-name) AVD_NAME="${2:?}"; shift 2;;
  --headless) EMULATOR_HEADLESS=1; shift;;
  --purge-emulator-packages) PURGE_EMULATOR_PACKAGES=1; shift;;
  -h|--help) echo "Usage: bash $LANG_NAME.sh install|verify|update|reset --yes|env|run -- cmd|emulator-install|emulator-list|emulator-start|emulator-remove"; exit 0;;
  *) fail "Unknown option: $1";;
 esac
done
# 옵션 검증 (AVD 이름/경로 안전성)
[[ "$ANDROID_API" =~ ^[0-9]+$ && "$BUILD_TOOLS" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$NDK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid Android package version'
[[ "$EMULATOR_ABI" == x86_64 || "$EMULATOR_ABI" == arm64-v8a ]] || fail 'Invalid emulator ABI'
[[ "$EMULATOR_FLAVOR" == default || "$EMULATOR_FLAVOR" == google_apis ]] || fail 'Invalid emulator flavor'
[[ "$AVD_NAME" =~ ^[A-Za-z][A-Za-z0-9_.-]{0,63}$ ]] || fail 'Invalid AVD name (ASCII letters/digits/._-)\'
case "$ACTION" in
 install) do_install;;
 verify) activate; do_verify;;
 update) do_update;;
 reset)
  ((YES)) || fail 'Reset deletes tools; pass --yes after reviewing.'
  rm -rf -- "$ROOT/$LANG_NAME"; log "Removed $LANG_NAME";;
 env) printf 'Run in current shell: source %q\n' "$ROOT/$LANG_NAME.sh";;
 run) activate; ((${#RUN_ARGS[@]})) || fail 'run requires -- command [args]'; "${RUN_ARGS[@]}";;
 emulator-install) emulator_install;;
 emulator-list) emulator_list;;
 emulator-start) emulator_start;;
 emulator-remove) emulator_remove;;
 *) fail "Unsupported action: $ACTION";;
esac
