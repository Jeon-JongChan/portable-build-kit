#!/usr/bin/env bash
set -euo pipefail
f="$(mktemp -d)"
trap 'rm -rf "$f"' EXIT
kit_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cp -a "$kit_root/.build" "$f/"
root="$f/.build"; sdk="$root/kotlin/android-sdk"
mkdir -p "$root/kotlin/jdk/bin" "$sdk/cmdline-tools/latest/bin" "$sdk/emulator"
cat > "$root/kotlin/jdk/bin/java" <<'EOF'
#!/bin/sh
printf 'mock java %s\n' "$*"
EOF
cat > "$sdk/cmdline-tools/latest/bin/sdkmanager" <<'EOF'
#!/bin/bash
case "$*" in *--licenses*) echo 'licenses accepted';; *) echo "mock sdkmanager: $*";; esac
EOF
cat > "$sdk/cmdline-tools/latest/bin/avdmanager" <<'EOF'
#!/bin/bash
case "$*" in
 *'create avd'*)
  name='';while (($#)); do if [[ "$1" == '-n' ]]; then name="$2";shift 2;else shift;fi;done
  mkdir -p "$ANDROID_AVD_HOME"; printf 'avd.ini\n' > "$ANDROID_AVD_HOME/$name.ini";echo "created $name";;
 *'delete avd'*)
  name='';while (($#)); do if [[ "$1" == '-n' ]]; then name="$2";shift 2;else shift;fi;done
  rm -f "$ANDROID_AVD_HOME/$name.ini"; echo "deleted $name";;
 *'list avd'*)
  ls "$ANDROID_AVD_HOME"/*.ini 2>/dev/null || true;;
 *) echo "mock avdmanager $*";;
esac
EOF
cat > "$sdk/emulator/emulator" <<'EOF'
#!/bin/sh
printf 'mock emulator %s\n' "$*"
EOF
chmod +x "$root/kotlin/jdk/bin/java" "$sdk/cmdline-tools/latest/bin/sdkmanager" "$sdk/cmdline-tools/latest/bin/avdmanager" "$sdk/emulator/emulator"
# mock image install / AVD / remove w/o Internet
bash "$root/kotlin.sh" configure --feature emulator --operation install --avd-name smoke_test --android-api 36 --accept-android-licenses
[[ -f "$root/kotlin/android-user/avd/smoke_test.ini" ]]
bash "$root/kotlin.sh" configure --feature emulator --operation list
bash "$root/kotlin.sh" configure --feature emulator --operation remove --avd-name smoke_test --purge-emulator-packages
[[ ! -f "$root/kotlin/android-user/avd/smoke_test.ini" ]]
# Verify portable Python activation paths
bash "$root/python.sh" configure --mode env
bash -c 'source "$1/env.sh"; [[ "$UV_PYTHON_BIN_DIR" == "$1/python/bin" ]]; [[ "$ANDROID_AVD_HOME" == "$1/kotlin/android-user/avd" ]]' _ "$root"
echo 'Smoke tests passed'
