# Portable Build Kit (Facade-based prototype)

언어별 **하나의 단순한 사용자 메뉴**와 비대화형 AI 호출을 지원하는 포터블 빌드 도구 관리 초안입니다.
전체 설계·제약·후속 개발 요구는 [`PORTABLE_BUILD_SPEC.md`](PORTABLE_BUILD_SPEC.md)에 있습니다.

## 기본 메뉴는 정확히 네 개

```text
1. 설치       (Install)
2. 환경설정   (Configure)
3. 최신화     (Update)
4. 초기화     (Reset)
0. 종료
```

`환경설정` 하위 메뉴에서 상태 검증, 세션 PATH 활성화, 전역 설정 등록/복원, 프로젝트 의존성 사전 다운로드(`prime`), 오프라인 빌드 검증(`offline-check`)을 처리합니다.
같은 위치의 선택 기능으로 **Kotlin → Android 에뮬레이터**, **Rust → Tauri 2**, **Node.js → 필요할 때 Vue 초기화**를 제공합니다. 기본 설치에서 에뮬레이터/AVD/NDK/Tauri/Vue는 제외합니다.

## 파일 구조 / Facade 책임

- `.build/setup.sh`, `.build/setup.ps1` : 4개 공개 액션과 기능별 내부 서비스 호출을 조율하는 **Facade**
- `.build/go.{sh,ps1}` 등 : 언어만 선택해 Facade에 전달하는 얇은 Adapter (개별 사용자 진입점)
- `.build/{go,rust,kotlin,csharp,python,nodejs}/` : 해당 SDK, 패키지, 환경 설정 및 캐시의 격리 공간
- `.build/rust/` : Tauri 공유 Rust 도구 및 필요할 때만 활성화되는 Tauri 기능
- `.build/nodejs/` : Node.js·npm 및 선택적으로 설치한 Vue 프로젝트 의존성

## Linux 사용 예

```bash
bash .build/rust.sh                                      # 4개 기본 메뉴
bash .build/kotlin.sh                                    # 같은 기본 메뉴 / 에뮬레이터는 환경설정 내부
bash .build/go.sh install                                 # AI: 설치
bash .build/go.sh configure --mode verify                 # AI: 검증
bash .build/go.sh configure --mode prime --project ./api   # AI: 사전 의존성 준비
bash .build/go.sh configure --mode offline-check --project ./api
bash .build/go.sh update                                  # Go 최신 안정 패치/릴리스
bash .build/kotlin.sh configure --feature emulator --operation install --accept-android-licenses
bash .build/rust.sh configure --feature tauri --operation install
bash .build/nodejs.sh configure --feature vue --operation init --project ./frontend
bash .build/go.sh reset --scope all --yes                  # 격리 SDK 삭제 + 추적된 전역 설정 복원
source .build/env.sh                                      # 현재 셸에서만 환경변수 활성화
```

## Windows PowerShell 사용 예

```powershell
.\.build\csharp.ps1
.\.build\csharp.ps1 -Action install
.\.build\csharp.ps1 -Action configure -Mode verify
.\.build\csharp.ps1 -Action update
.\.build\kotlin.ps1 -Action configure -Feature emulator -Operation install -AcceptAndroidLicenses
.\.build\rust.ps1 -Action configure -Feature tauri -Operation install
.\.build\csharp.ps1 -Action reset -Scope all -Yes
. .\.build\activate.ps1
```

`reset`이 도구를 삭제할 때는 터미널 상호작용의 `RESET` 확인이나 명시적인 `--yes`/`-Yes`가 필요합니다. 환경변수만 원복할 때는 `reset --scope env`를 사용합니다.

## 업데이트 및 오프라인 조건

- **최신화는 도구 체인 업데이트**입니다. 프로젝트의 `Cargo.lock`, `package-lock.json`, `uv.lock`, `go.mod` 등의 버전을 **자동 변경하지 않습니다.** Kotlin SDK는 요청한 API/Build Tools만 보장합니다. 무차별적인 `sdkmanager --update`는 실행하지 않습니다.
- 오프라인 빌드는 **동일 OS/CPU/프로젝트/잠금파일/빌드 타깃을 온라인 상태에서 먼저 `prime`한 경우에만** 가능성을 검증합니다. 새 의존성은 오프라인에서 받을 수 없습니다.
- Tauri Windows MSVC·SDK/WebView2 및 Linux WebKitGTK·시스템 라이브러리는 호스트 의존성이 남아 있습니다. 도구만 설치했다고 모든 Tauri 타깃의 패키징이 완성되는 것은 아닙니다.
- 현재는 **초안**입니다. Linux 모의 테스트만 수행되었고 실제 Windows PowerShell 설치, 다운로드, 실기기 에뮬레이터 구동 및 완전한 네트워크 차단 빌드는 검증되지 않았습니다.
