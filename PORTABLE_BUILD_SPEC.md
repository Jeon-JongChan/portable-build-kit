# Portable Build Kit - implementation specification

Revision: 2026-10-14. Maintained as a handoff document for another AI developer.

> Status: working prototype with Linux shell syntax and mocked integration tests. A complete online installation, Windows PowerShell 5.1 integration, native build/link, emulator boot, and a disconnected-device regression suite have **not** been completed. Never report success for an untested host/target.

## 1. Product objective

Install **only the toolchains required by a selected project** into `PROJECT/.build` from the official upstreams, with no global changes by default. Online `prime` resolves/caches declared project dependencies, while `offline-check` builds **the same locked project, architecture and toolchain configuration** without reaching the internet. All actions must support an interactive menu and a deterministic, noninteractive AI CLI. Windows uses `.ps1`/PowerShell; Linux uses `.sh` files executed with **Bash**, not POSIX sh.

## 2. Technology ownership and minimal installation

| Purpose | User-facing entry point | Portable directory | Default install |
|---|---|---|---|
| Android Kotlin / Compose | `.build/kotlin.ps1` / `.sh` | `kotlin/` | JDK, Android command-line tools, exactly selected Android platform and Build Tools |
| Windows C# | `csharp.ps1` / `.sh` | `csharp/` | .NET SDK and NuGet cache |
| Go backend | `go.ps1` / `.sh` | `go/` | Official Go SDK and module/build caches |
| Rust native libraries / CLI | `rust.ps1` / `.sh` | `rust/` | rustup `minimal` profile, Cargo and source/build caches |
| Python scripts | `python.ps1` / `.sh` | `python/` | `uv` plus managed CPython (actual `python` executable), isolated virtualenvs/cache |
| JavaScript build runtime | **`nodejs.ps1` / `.sh`** | `nodejs/` | Official Node.js LTS archive, bundled npm; **optional, on request** |
| Vue front end | **Node.js > `vue-init`** | `nodejs/projects/` | **No global Vue installation**. Scaffold in the requested project only |
| Tauri 2 / Vue + Rust | **Rust > Tauri submenu** | `rust/tauri/` (metadata) + Rust/Node.js shared caches | **No separate Tauri toolchain/entry-point**. Selected feature invokes Rust and Node.js installers |

**Do not produce** `vue.ps1`, `vue.sh`, `tauri.ps1`, `tauri.sh`, `.build/vue/` or `.build/tauri/`. Avoid installing optional Node.js in `install all` (minimal-size policy); install it only with explicit `nodejs install`, `vue-init` or `rust tauri-install`. Frontend packages such as Vue, Vite, TypeScript and `@tauri-apps/cli` belong to a project manifest and lockfile, not a globally installed CLI.

Node.js is the JavaScript runtime needed to execute Vue's development/build tools (such as Vite). **The Vue UI still runs in the browser/WebView, not as a Node.js process.** `npm`, delivered with Node.js, downloads/installs frontend dependencies. Tauri's native application core is written in Rust and invokes frontend build tooling when using a JS frontend.

## 3. Filesystem contract

```
PROJECT/
  .build/
    setup.ps1              # Shared command/menu manager
    setup.sh
    activate.ps1           # Generated session-only Windows environment
    env.sh                 # Generated session-only Linux environment
    go.ps1/.sh
    rust.ps1/.sh           # Rust menu INCLUDES Tauri
    kotlin.ps1/.sh         # Kotlin menu INCLUDES optional emulator
    csharp.ps1/.sh
    python.ps1/.sh
    nodejs.ps1/.sh         # Node menu INCLUDES on-demand Vue scaffold
    _state/                # Temporary downloads and global-restore metadata
    go/{sdk,path,cache}/
    rust/{rustup,cargo,targets,tauri}/
    kotlin/{jdk,android-sdk,gradle,project-caches,android-user}/
    csharp/{dotnet,nuget}/
    python/{bin,runtimes,envs,cache,pip-cache,tools}/
    nodejs/{node,npm-cache,npm-global,projects,corepack}/
      projects/<project-id>/
        node_modules/      # Actual project dependencies live here
        package-lock.sha256
        project.txt
  frontend/
    package.json
    package-lock.json
    node_modules -> ../.build/nodejs/projects/<project-id>/node_modules
  backend/
  android/
```

For Linux, `node_modules` is a relative symlink so moving a self-contained workspace can preserve it. On Windows, the project link is an NTFS directory junction and may need explicit regeneration after moving the workspace. Never silently delete unmanaged existing `node_modules` directories or links. Before removing `.build/nodejs`, remove only verified kit-managed links. Warn about external utilities such as `git clean` that may follow Windows junctions.

The physical install/cache directories stay in `.build` for Go, Rust, Kotlin/Gradle, .NET, Python and Node. Source files, ordinary compiled output and explicitly generated app artifacts may remain in the application project; distinguish **toolchains/dependencies** from **application build artifacts**. For Rust and Gradle, route compiled target and project-specific caches to `.build` too.

## 4. Facade 패턴 및 네 가지 사용자 동작 (필수)

### 4.1 기본 Facade 계약

`setup.ps1` / `setup.sh`는 **Facade**이며 각 언어 전용 `go.*`, `rust.*`, `kotlin.*`, `csharp.*`, `nodejs.*`, `python.*`는 언어를 지정해 Facade만 호출하는 **얇은 Adapter**다. 각 언어별 사용자 메뉴나 환경 설정 로직을 복제하지 않는다. 내부 서비스는 SDK 설치, 환경변수 격리, 최신화, 삭제 및 복원, 의존성 캐싱, 선택 기능을 책임진다.

사용자에게 표시하는 **최상위 메뉴는 정확히 네 개**(종료 제외)여야 한다.

```text
1. 설치 (Install)
2. 환경설정 (Configure)
3. 최신화 (Update)
4. 초기화 (Reset)
0. 종료
```

- **설치 (install):** 언어별 최소 툴체인만 격리 설치한다. 기본적으로 Android Emulator/NDK, Tauri, Vue scaffold, 시스템 전역 패키지 설치는 수행하지 않는다.
- **환경설정 (configure):** 세션 환경 활성화 안내, 명시적인 전역 환경변수 추가/원복, 상태 검증, 의존성 준비(`prime`), 오프라인 테스트, 설치 현황 조회를 하위 메뉴/`--mode`로 제공한다. **언어 선택형 추가 기능**은 이 메뉴 안의 또 다른 하위 메뉴에서만 표시한다.
- **최신화 (update):** 해당 툴체인을 설정한 버전 계열에서 갱신하되 새 프로젝트 의존성 및 잠금파일을 자동 업그레이드하지 않는다. Go는 최신 안정판(또는 지정 버전), Rust는 stable, .NET은 지정 채널 최신 패치, Node.js는 지정 major의 최신 패치, Python은 요청한 minor 내 업데이트를 원칙으로 한다. **Android**는 용량 절약을 위해 사용자가 지정한 플랫폼 및 Build Tools를 정확히 보장하고 전체 SDK 일괄 업데이트는 금지한다. JDK와 Command-line Tools 최신 버전 갱신은 별도 검증 후 구현한다.
- **초기화 (reset):** 기본 `all`은 먼저 이전 전역 설정을 원복하고 지정된 언어의 관리 도구/캐시만 삭제한다. `env`는 전역 설정만 복원하고, `tools`는 관리 도구만 지운다. 삭제 대상은 `.build/<language>` 하위 관리 파일과 툴이 소유한 프로젝트 링크로 제한한다. **비대화형 SDK 삭제에는 `--yes`/`-Yes`가 필수**, 인터랙티브에서는 `RESET` 확인 필수. 전역 설정 충돌 시 원복/삭제를 중단한다.

### 4.2 하위 메뉴 및 CLI

| Facade 하위 기능 | Linux | Windows |
|---|---|---|
| 기본 설치 | `bash .build/go.sh install` | `.\.build\go.ps1 -Action install` |
| 검증 | `bash .build/go.sh configure --mode verify` | `.\.build\go.ps1 -Action configure -Mode verify` |
| 세션 환경 | `source .build/env.sh` | `. .\.build\activate.ps1` |
| 전역 적용/복구 | `configure --mode global-on` / `global-off` | `-Action configure -Mode global-on` / `global-off` |
| 의존성 설치 및 고정 | `configure --mode prime --project DIR` | `-Action configure -Mode prime -Project DIR` |
| 오프라인 검증 | `configure --mode offline-check --project DIR` | `-Action configure -Mode offline-check -Project DIR` |
| 최신화 | `bash .build/rust.sh update` | `.\.build\rust.ps1 -Action update` |
| 도구+설정 전체 초기화 | `reset --scope all --yes` | `-Action reset -Scope all -Yes` |
| 전역 설정만 원복 | `reset --scope env` | `-Action reset -Scope env` |
| Android 에뮬레이터 추가 설치 | `bash .build/kotlin.sh configure --feature emulator --operation install --accept-android-licenses` | `.\.build\kotlin.ps1 -Action configure -Feature emulator -Operation install -AcceptAndroidLicenses` |
| Android AVD 조회/실행/삭제 | `--feature emulator --operation list/start/remove` | `-Feature emulator -Operation list/start/remove` |
| Tauri 2 선택 기능 | `bash .build/rust.sh configure --feature tauri --operation install/verify/prime/offline-check/remove` | `-Action configure -Feature tauri -Operation ...` |
| Vue 필요시 생성 | `bash .build/nodejs.sh configure --feature vue --operation init --project DIR` | `.\.build\nodejs.ps1 -Action configure -Feature vue -Operation init -Project DIR` |

과거 저수준 명령(`prime`, `emulator-install` 등)은 **호환성용 내부 호출 경로**로 유지할 수 있지만 새로운 문서와 AI 워크플로는 네 가지 Facade 액션만 사용해야 한다. 개별 스크립트 실행과 공통 `setup` 실행의 동작은 일치해야 한다. `install all`의 기본 집합은 Go·Rust·Kotlin·C#·Python이고, Node.js는 필요할 때만 별도 설치한다. 모든 파라미터는 메뉴 없이도 동작해야 한다.

### 4.3 업데이트 경계 및 복원 정책

1. 업데이트는 온라인 작업으로 취급한다. 버전 계열을 바꾸면 기존 오프라인 스냅샷을 재검증하거나 `prime`한다.
2. Go/Node.js 교체는 기존 바이너리의 백업을 임시 보관한 후 설치가 성공할 때만 폐기한다. 다른 도구의 디렉터리를 삭제하지 않는다. 인터럽트/전원 중단 시 재개·롤백은 추가 보강이 필요하다.
3. `uv`가 비관리형 포터블 설치(`UV_UNMANAGED_INSTALL`)일 때는 `uv self update` 대신 포터블 전용 설치 절차로 갱신한다.
4. `sdkmanager --update` 같은 무차별 업데이트는 **절대 실행하지 않는다**. 선택한 Android 패키지/에뮬레이터 이미지에 한정한다.
5. Rust Tauri와 Node.js Vue의 선택 기능은 공유 도구를 임의로 제거해서는 안 된다.
6. 전역 설정 복원은 반드시 추적 기록과 충돌 검사에 근거해야 한다. 프로젝트의 수동 설치/원본 코드는 삭제 대상이 아니다.

## 5. Project dependency isolation: REQUIRED

| Ecosystem | Installation location / environment | Offline condition |
|---|---|---|
| Go | `GOPATH`, `GOMODCACHE`, `GOCACHE` under `.build/go` | `go.sum`, downloaded modules; `GOPROXY=off` |
| Rust | `RUSTUP_HOME`, `CARGO_HOME` under `.build/rust`; `CARGO_TARGET_DIR=.build/rust/targets/<id>` | `Cargo.lock`, fetched sources/target components; `cargo build --offline` |
| Kotlin/Android | `JAVA_HOME`, `ANDROID_HOME`, `GRADLE_USER_HOME`; Gradle `--project-cache-dir` under `.build/kotlin` | Project Wrapper JAR/distribution, plugin and Maven artifacts available; `--offline` |
| C# | `DOTNET_ROOT`, `DOTNET_CLI_HOME`, `NUGET_PACKAGES` under `.build/csharp` | All NuGet packages/assets restored; `dotnet build --no-restore` |
| Python | Managed interpreter/uv, `UV_CACHE_DIR`, `UV_PROJECT_ENVIRONMENT` under `.build/python` | `uv.lock` preferred; wheel/sdist dependencies cached; `uv sync --offline` |
| Node.js / Vue / Tauri frontend | Node + npm cache in `.build/nodejs`; project `node_modules` physically in `.build/nodejs/projects/<id>` with a project-local link | `package-lock.json` hash matches cached snapshot; `npm run build` with network disabled |

**Important:** `node_modules` must NOT physically live in a system-level directory or be globally installed. For JS, online `prime` runs `npm ci` in the project, transfers its `node_modules` to the isolated store, and creates a managed link/junction; offline-check verifies `package-lock` fingerprint and uses the stored copy. Windows NTFS junction behavior and unusual npm postinstall scripts require actual integration tests. Third-party postinstall scripts may still create their own caches outside `.build`; investigate and block such side effects rather than claiming unconditional isolation.

Only explicit online `prime` can fetch new dependency versions. Where lockfiles are absent, create and commit them online first. Capturing *every* possible dependency of a future, unknown project is not possible: the offline promise applies only to the prepared project, platform/architecture, exact tasks/features and pinned versions.

## 6. Android Kotlin minimal SDK + optional emulator

- Install **command-line tools + one selected `platforms;android-N` + one matching `build-tools;VERSION` + JDK**; no Android Studio installation.
- `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `GRADLE_USER_HOME`, `JAVA_HOME`, `ANDROID_AVD_HOME`, `ANDROID_EMULATOR_HOME`, `ANDROID_USER_HOME` must reference `.build/kotlin`.
- Optional `--with-adb` installs `platform-tools` only when debugging/device installation is needed.
- Optional `--with-ndk` installs exactly one NDK version only for JNI/Rust/Tauri Android projects and adds Rust Android target if applicable.
- Emulator remains an optional Kotlin submenu. `emulator-install` downloads `emulator`, `platform-tools`, and **one** selected system image, and creates the named AVD in `.build/kotlin/android-user/avd`. `emulator-list`, `emulator-start`, `emulator-remove`, `--purge-emulator-packages` must work independently.
- Do not silently accept Android licenses. An explicit acceptance flag is required **after the user has read and accepted** the licenses.
- Emulator launch requires host virtualization/GPU/kernel drivers; having portable Android SDK binaries is not sufficient by itself.

## 7. Tauri-specific host prerequisites and scope

- Tauri 2 is a Rust **optional feature**. Do not install Tauri CLI globally; use locked project `@tauri-apps/cli` with npm, and Cargo dependencies from the project's `src-tauri/Cargo.lock`.
- Windows native app builds require compatible MSVC C++ linker + Windows SDK and WebView2. Detect/validate, never fake a completed portable toolchain.
- Linux native app builds require WebKitGTK 4.1 development files, OpenSSL libraries and additional platform packages. They may be system/ABI coupled; the portable manager must **report blockers** and later can implement an explicit isolated sysroot/container solution with real tests.
- Android builds require selected NDK, Android platform/build tools, Java and Rust Android target; mobile packaging/build tools must be tested. No Apple target installation or support is in scope.
- Merely running `cargo build` tests the native crate, **not** a successful packaged Tauri application. Add a separate tested bundle action (including local frontend compilation, platform native prerequisites) before claiming complete offline Tauri packaging.

Official reference: https://tauri.app/start/prerequisites/ .

## 8. Safety / supply-chain / global changes

- Use only official HTTPS distributions; verify SHA-256/signatures where available, keep resolved toolchain versions in a future project lock manifest.
- Dynamic upstream installer scripts (e.g., uv and dotnet) currently need stronger script hash verification and a version-pinned source in a hardened release.
- `global-on` is opt-in only; record old user values, include only installed tool paths, never edit system-wide configuration without separate authorization.
- `global-off` must revert exact tracked changes and report conflicts rather than deleting third-party changes.
- On Windows, avoid touching unrelated directory junctions and symlinks. Prefer safe remove of the junction only, never recursive traversal of its target.
- Install/remove do not require administrative privilege where supported; otherwise fail with a clear prerequisite explanation.

## 9. Acceptance tests for the next AI

1. 공통 및 각 언어 `.ps1`/`.sh` 진입점의 **최상위 메뉴는 4개만** 표시한다. Kotlin 에뮬레이터, Rust Tauri 2, Node.js Vue는 환경설정 하위 메뉴에서만 표시한다.
2. Online-install each selected compiler and verify its executable runs **from `.build`**; no PATH or user-folder pollution by default.
3. With a new locked Vue project, run `nodejs prime` and confirm `node_modules` files live in `.build/nodejs/projects/<id>`; source project contains only a kit-managed link.
4. Disable network, verify `nodejs offline-check`, `rust cargo build --offline`, Go, Kotlin/Gradle, Python/uv and .NET locked project builds. For Tauri verify real **bundle** separately.
5. Exercise Kotlin minimal Android SDK installation and emulator/AVD optional install, headless start, and removal on supported host.
6. Exercise `configure --mode global-on/global-off` and `reset --scope all --yes`; verify previous settings are restored, unmanaged `node_modules` remain untouched, and reset without `--yes` refuses deletion.
7. Test actual Windows PowerShell 5.1 and Linux x86_64. Test relocation of copied workspace; regenerate junctions on Windows when needed.
8. Check SHA validation, failure exit codes, interrupted download recovery, package version pins, disk usage before/after, and removal of temporary state.
9. Add tests for `node_modules` links with native optional dependencies, Vue/Vite, Tauri CLI and postinstall scripts. Linux mock tests alone are **not** sufficient for full acceptance.

## 10. Current validation status

- Linux Bash syntax and simulated Android emulator/AVD lifecycle: tested.
- Linux simulated Node.js project dependency installation, link, offline reuse, removal, Rust Tauri submenu: tested.
- Live network downloads, Windows PowerShell, actual Vue/NuGet/Cargo/Gradle compile, cross-target offline packaging: **not yet verified**.

This document is normative for subsequent work. When scripts and docs conflict, fix and test the scripts instead of silently downgrading these requirements.

### Facade 리팩터링 검증 현황

- 기존 Linux Bash 에뮬레이터/Node/Tauri 모의 테스트와 기본 메뉴/Facade 비대화형 호출 검증 수행.
- PowerShell은 실제 Windows 호스트에서 실행 검증하지 못했으므로 별도 수동/CI 검증 필요.
- 최신화의 실 다운로드 및 롤백/빌드 타깃 보장, 오프라인 재빌드는 실환경 검증 전에는 완료로 선언하지 말 것.
