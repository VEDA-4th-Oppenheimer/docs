# Qt 관제 콘솔 빌드와 배포

SPATIAL·VMS(Qt 데스크톱 관제 UI)를 빌드하고, 등록해서 실제 킷에 붙이고, 배포본으로
패키징하는 절차를 정리한다.

| 항목 | 값 |
|---|---|
| 문서 ID | `ADTS-QTC-80` |
| 담당 | 송영빈 |
| 기준 코드 | QT `e777e73` (2026-08-21) |
| 실행 파일명 | `spatial_vms` / 배포명 `SPATIAL-VMS` |
| 빌드 | `CMakeLists.txt` (Qt6 Widgets + Paho MQTT C++ + FFmpeg) |
| 패키징 | `scripts/package_macos.sh` · `scripts/package_windows.ps1` |
| 등록 마법사 | `src/EnrollDialog` |

---

## 이 앱이 무엇인가

Hanwha Vision **PNM-C16083RVQ** 멀티센서 카메라 + **TOFSense-F2 P** 1D LiDAR pan-tilt
스캐너로 사람 표적 없이(targetless) camera-LiDAR 외부 파라미터(extrinsic)를 자동
산출하는 킷의 Qt 데스크톱 관제 UI.

- **UI**: Qt6 Widgets, 다크 관제실 테마 (`src/Theme.h`)
- **CCTV 영상**: RTSP 직접 연결(영상 자체는 MQTT 경유 아님). `src/RtspDecoder`가
  FFmpeg(libavformat/avcodec/swscale)로 채널별 RTSP 스트림을 백그라운드 스레드에서
  디코딩해 `CameraTile`에 공급한다.
  **카메라 정보는 등록할 때 사용자가 입력한다.** 카메라는 RPi 와 물리적으로
  떨어져 있고 데몬은 카메라를 건드리지 않으므로, 서버를 경유할 이유가 없다.
  등록 후에는 `모드 → 카메라 설정…` 에서 바꾸면 **재시작 없이 즉시 적용**된다.
  RTSP 는 이 앱이 카메라에 직접 연결하므로 RPi 를 경유하지 않는다.
  연결이 안 되면 **3번(3초·6초 간격)만 시도하고 멈춘다** — 카메라 없는 자리에서
  무한 재시도로 로그를 채우지 않게. 다시 붙이려면 `모드 → CCTV 재연결`(또는
  `카메라 설정…` 에서 확인).
- **MQTT**: Eclipse Paho MQTT C++ (`src/MqttBridge`) — 스캔 제어/상태 전용
  (`adts/...` 토픽). 브로커는 **RPi 에 상주**(Mosquitto)하며 Qt·카메라 단·통합
  데몬이 모두 이 브로커의 클라이언트다. **포트 8883 + mTLS**. 인증서가 없으면
  평문 `tcp://` 로 degraded 접속하지만, 브로커가 TLS 전용이라 실제로는 실패한다 —
  로컬에 평문 브로커를 따로 띄운 경우에만 의미가 있다.
- **데모 모드**: 실제 브로커/킷이 없어도 상단 메뉴 `모드 → Demo Mode` 토글로 계약서의
  실제 세션 흐름(`cmd/scan` → `state=SCANNING` → `event/progress` 2Hz → `state=EXPORT`
  + `state/scan` → `state=IDLE`)과 IMU 드리프트를 재생한다 (기본값 꺼짐, `src/DemoBridge`).
  등록되지 않은 상태로 앱을 띄우면 자동으로 이 모드로 들어간다.
  RTSP는 이 토글과 무관하게 카메라 설정이 있으면 항상 동작한다.

## 이 문서가 따르는 것

- **MQTT 인터페이스 계약** (데몬=이현우 / 브로커·인증서=이현우·송영빈) — 이 앱의 MQTT 부분은
  전적으로 이 계약을 따른다. 토픽·페이로드·QoS·retain 을 바꾸려면 계약을 먼저 고쳐야 한다.
- **카메라 단 캘리브 결과(NCC / edge_rmse / extrinsic) 스키마** — **이 MQTT 계약과는
  별개**이며 발행 토픽이 아직 정해지지 않았다. 그래서 이 Qt 앱은 캘리브 품질과 RT 를 아직
  표시하지 않는다.

## 의존성 설치 (macOS / Homebrew)

```bash
brew install qt paho-mqtt-c paho-mqtt-cpp ffmpeg pkg-config
# 실제 브로커 연동 테스트용 (선택)
brew install mosquitto
```

---

# 사용법

접속에 필요한 것(인증서·브로커 주소·카메라 URL)은 전부 비밀정보라 저장소에도
배포본에도 들어 있지 않다. 그래서 **처음 쓰는 사람**과 **개발하는 사람**의 설정
방법이 다르다.

## A. 배포본을 받아 쓰는 경우 (일반 사용자)

앱을 실행하면 **등록 화면**이 뜬다. 여기서 한 번만 입력하면 이후에는 묻지 않는다.

| 입력란 | 값 |
|---|---|
| 발급 서버 주소 | RPi IP (예: `172.20.32.110`) |
| 포트 | `8443` (기본값) |
| 토큰 | 관리자에게 받은 1회용 문자열 |
| 기기 이름 | 자동으로 호스트명이 채워진다 — 브로커 로그에서 누구 것인지 구분용 |
| **카메라 IP** | CCTV 주소 (예: `172.20.33.8`) |
| **카메라 계정 / 비밀번호** | 카메라 로그인 정보 |

토큰은 **인증서(스캐너 제어)** 를 받기 위한 것이고, 카메라 입력란은 **CCTV 영상**을
위한 것이다. 둘은 서로 무관하다 — RTSP 는 이 앱이 카메라에 직접 연결하고 RPi 를
거치지 않는다. 그래서 카메라 정보는 서버가 아니라 여기서 받는다.

카메라 IP 를 비우면 발급 서버가 설정을 갖고 있을 때 그것을 폴백으로 쓴다. 서버에도
없으면 등록은 성공하되 영상이 나오지 않으며, 완료 창이 그 사실을 알려준다.

받은 파일은 아래에 저장된다. 앱을 지우거나 다시 설치해도 남는다.

| OS | 위치 |
|---|---|
| macOS | `~/Library/Application Support/VEDA4th/SPATIAL-VMS/` |
| Windows | `C:\Users\<사용자>\AppData\Roaming\VEDA4th\SPATIAL-VMS\` |
| Linux | `~/.local/share/VEDA4th/SPATIAL-VMS/` |

**토큰이 없거나 나중에 하려면** `나중에`를 누른다. Demo Mode 로 떠서 화면 구성은
볼 수 있고, 실제 장비에는 붙지 않는다.

**카메라 변경**: 상단 메뉴 `모드 → 카메라 설정…`. IP·계정·비밀번호를 고치면
**재시작 없이 즉시** 스트림이 갈아끼워진다. 비밀번호를 비우면 기존 값을 유지한다.
카메라는 인증서와 무관하므로 재등록할 필요가 없다.

4채널은 같은 카메라(Hanwha PNM 시리즈)의 **센서 0~3 번**이 CH1~CH4 에 대응한다.
URL 은 `rtsp://<계정>:<비번>@<IP>:554/<0~3>/profile2/media.smp` 형태로 앱이 만든다
(`src/CameraConfig.h`).

**로그아웃**: 상단 메뉴 `모드 → 로그아웃`. 이 기기에 저장된 인증서와 설정을 지우고
앱을 닫는다. 다시 쓰려면 새 토큰을 발급받아야 한다. (이미 발급된 인증서 자체의
무효화(CRL)는 아직 없다 — 기기 분실 대응이 필요하면 브로커에 CRL 을 걸어야 한다)

### 발급 서버 쪽 전제

서버 신원은 실행파일에 박아둔 `resources/ca.crt` 로만 검증한다(시스템 CA 는 쓰지
않는다). 발급 시점에는 아직 클라이언트 인증서가 없어 검증 근거가 이것뿐이다.
`ca.crt` 는 **공개** 인증서라 배포본에 들어가도 안전한데, **CA 를 재발급하면 이 파일도
같이 갱신**해야 한다 — 안 하면 기존 배포본은 새 서버를 영영 신뢰하지 못한다.

요청·응답 형식과 서버가 지켜야 할 조건(`v3_client` 확장, 전통 RSA 키 포맷, 발급 후 ACL
등록 의무, 오류 코드)은 `interfaces/` 의 **Qt ↔ RPi 등록·발급 계약** 문서가 정본이다.
여기서는 클라이언트가 그 계약대로 구현돼 있다는 것만 밝혀둔다.

## B. 저장소에서 직접 빌드하는 경우 (개발자)

```bash
cmake -S . -B build
cmake --build build
./build/spatial_vms.app/Contents/MacOS/spatial_vms   # macOS
```

Windows 는 의존성 설치 방법이 달라 아래 **배포용 패키징 → Windows** 절의 vcpkg 절차를
따른다.

개발 트리에서는 등록 마법사를 거치지 않고 **프로젝트 안의 설정 파일**을 그대로 쓴다.
example 을 복사해 실제 값을 채운다 (둘 다 gitignore 대상 — 절대 커밋하지 말 것).

```bash
cp config/cameras.example.json config/cameras.json
cp config/mqtt.example.json    config/mqtt.json
```

인증서 3개(`ca.crt` / `qt-console.crt` / `qt-console-trad.key`)는 `mqtt.json` 의
`cert_dir` 이 가리키는 폴더(기본 `certs/`)에 둔다. RPi 의 `/etc/adts/certs/` 에서
받아오면 된다. 개인키(`.key`)는 어떤 경우에도 커밋하지 않는다.

PNM-C16083RVQ(4MP × 4ch 멀티센서) RTSP URL 형식:

```
rtsp://USER:PASSWORD@CAMERA_IP:554/<0~3>/profile2/media.smp
```

센서(채널) 번호 0~3이 CH1~CH4에 대응한다. `profile2`는 서브스트림, `profile1`은 고해상도
메인스트림. MVP 범위는 대표 1채널(CH1)이지만 하드웨어가 4채널 모두 지원해 4개 다 붙였다.

### 설정 파일 탐색 순서

`src/ConfigPath.h` 의 `resolveConfigPath()` 가 이 순서로 찾는다.

1. **현재 작업 디렉터리** 기준 상대경로 — 터미널에서 프로젝트 루트에서 실행할 때
2. **실행파일 위치에서 위로 최대 6단계** — 개발 트리의 `.app` 을 Finder/IDE 로 실행할 때
3. **사용자 데이터 디렉터리** — 배포본

개발 트리를 먼저 보는 이유: 개발 중에는 프로젝트 파일을 고쳐서 바로 확인할 수 있어야
하고, 배포본에는 개발 트리가 없어 자연히 3번으로 떨어지기 때문이다. 반대로 하면
개발자가 등록을 한 번 한 뒤로 프로젝트 파일 수정이 조용히 무시돼 헷갈린다.

> ⚠️ `cert_dir` 이 `"certs"` 같은 상대경로일 때, 예전에는 프로세스 CWD 기준으로
> 찾아서 Finder 로 실행하면(CWD=`/`) 인증서를 못 찾고 평문으로 degraded 접속해
> **설정은 맞는데 안 붙는** 상태가 됐다. 지금은 `cert_dir` 도 위 순서로 해석한다.

## 동시 접속 (Client ID)

MQTT 는 Client ID 가 유일해야 하고, 같은 ID 로 두 번째가 붙으면 브로커가 첫 번째를
끊는다. 그래서 Client ID 를 `qt-console-<호스트명>-<난수>` 로 만든다 — 여러 명이
동시에 콘솔을 켜도 서로 끊기지 않는다.

권한은 Client ID 가 아니라 **인증서 CN** 으로 판정되므로(`use_identity_as_username
true`) ACL 과 인증서는 그대로 쓸 수 있다. 계약서 §1 의 "고정 `qt-console`" 문구는
다중 콘솔에서 성립하지 않아 확장했다.

---

## 배포용 패키징 (Qt/FFmpeg/Paho 미설치 고객 PC용)

`qt_add_executable`은 macOS에서 `.app` 번들을(APPLE), Windows에서는 콘솔창 없는
GUI `.exe`를(WIN32) 만든다 (`CMakeLists.txt` 참고). 다만 기본 빌드 결과물은 여전히
빌드 머신의 Homebrew 라이브러리를 동적으로 링크하고 있어 그 자체로는 배포할 수
없다 — 아래 절차로 의존성을 번들링해야 한다.

번들에 들어가는 의존성은 **Qt6 Widgets/Network/OpenGLWidgets + Paho(C·C++) +
OpenSSL + FFmpeg(avformat/avcodec/avutil/swscale)** 이다. `OpenGLWidgets` 는 3D 스캔
뷰(`src/ScanView3D`)를 붙이면서 늘어난 것이라, 그 이전에 만들어 둔 배포본 절차와
비교할 때 Qt 쪽 산출물이 더 많다(`QtOpenGL`/`QtOpenGLWidgets`, 그리고 Qt 6.11 부터는
플러그인 의존으로 `QtQml`/`QtQuick` 계열까지 딸려온다).

### 앱 아이콘

`resources/AppIcon.icns`(macOS)/`resources/AppIcon.ico`(Windows) — CCTV 불릿
카메라 실루엣 + REC 표시등, 관제실 다크 테마(`Theme.h`) 색상과 맞춰 그렸다.
`CMakeLists.txt`가 플랫폼별로 자동으로 번들에 넣는다(macOS는
`MACOSX_BUNDLE_ICON_FILE`+리소스 복사, Windows는 `resources/app.rc` 통해 `.exe`에
아이콘 리소스로 컴파일). 디자인을 바꾸려면 `scripts/gen_app_icon.cpp` 참고
(사용법은 파일 상단 주석).

### macOS (검증 완료 — 2026-08-14 재확인)

```bash
cmake -S . -B build && cmake --build build
./scripts/package_macos.sh
```

`scripts/package_macos.sh`가 하는 일:
1. `macdeployqt`로 Qt 프레임워크 + 링크된 Homebrew dylib(FFmpeg/Paho/OpenSSL 등)을
   `spatial_vms.app/Contents/Frameworks`로 복사하고 install name을
   `@executable_path/../Frameworks/...`로 재기록.
2. 이 앱이 실제로 쓰지 않는 플러그인(`libqpdf`/`libqsvgicon`/
   `libqtvirtualkeyboardplugin` — QtPdf/QtSvg/QtVirtualKeyboard 프레임워크를
   요구하지만 이 앱은 해당 프레임워크를 링크하지 않음) 제거.
3. 번들 전체를 스캔해 남은 Homebrew(`/opt/homebrew`)/`/usr/local` 절대경로 참조가
   있으면 `install_name_tool`로 재기록.
4. `codesign --deep --sign -`로 ad-hoc 재서명 (배포 시 실제 서명이 필요하면
   `-s '<Developer ID>'`로 교체).
5. `hdiutil`로 `build/SPATIAL-VMS.dmg` 생성.

**중간에 뜨는 ERROR 두 종류는 정상이다** (스크립트가 뒤에서 정리한다):

- `Cannot resolve rpath "@rpath/QtPdf.framework/..."` (QtSvg/QtVirtualKeyboard 도
  같이) — 2번에서 지우는 그 플러그인들이다.
- `codesign verification error: ... invalid signature ... In subcomponent:
  Frameworks/libbrotlicommon.1.dylib` — `macdeployqt` 가 dylib 의 install name 을
  고치면서 서명이 깨진 것이다. 3번에서 id 를 다시 쓰고 4번에서 번들 전체를
  재서명하므로 최종 산출물은 `codesign --verify --deep --strict` 를 통과한다.
  (`install_name_tool: warning: changes ... will invalidate the code signature`
  경고도 같은 이유다.)

마지막 재확인(2026-08-14, Homebrew Qt 6.11.1 / FFmpeg 8.1.2 / OpenSSL 3.6.3) 결과:

- 번들 안 Mach-O 전체에서 `/opt/homebrew`·`/usr/local` 잔여 참조 **0건**.
- `spatial_vms.app` 115MB, `SPATIAL-VMS.dmg` 52MB.
- 번들에 `.key`/`.crt`/`.pem`·`mqtt.json`·`cameras.json` 이 하나도 안 들어간다
  (Windows 쪽과 달리 macOS 스크립트에는 자동 검사가 없다 — `config/`·`certs/` 를
  번들 리소스로 넣는 CMake 규칙 자체가 없어서 구조적으로 섞이지 않는다).
- `cd /tmp && env -i .../Contents/MacOS/spatial_vms` — 환경변수를 전부 지우고
  프로젝트와 무관한 디렉터리에서 실행해도 정상 기동.

Homebrew가 전혀 없는 macOS에서도 이 `.dmg`를 열어 `.app`을 `Applications`로
드래그하면 바로 쓸 수 있다.

> ⚠️ **개발 머신에서의 `env -i` 실행은 "설정 없는 새 PC" 검증이 아니다.**
> `HOME` 을 지워도 Qt 는 `getpwuid` 로 사용자 데이터 디렉터리를 찾아내므로,
> 이미 등록을 해 본 개발 머신에서는 `~/Library/Application Support/VEDA4th/
> SPATIAL-VMS/{config,certs}` 를 그대로 읽는다(위 실행에서도 실제 카메라로 RTSP 를
> 걸었다). 등록 마법사부터의 신규 사용자 흐름을 보려면 그 폴더를 잠시 다른 이름으로
> 옮겨두고 실행할 것.
>
> 같은 이유로 **빈 `certs/` 폴더를 배포본 옆에 두면 안 된다.** `resolveConfigPath`
> 는 실행파일 주변을 사용자 데이터 디렉터리보다 먼저 보기 때문에, 빈 `certs/` 가
> 발급받아 둔 인증서를 가려 MQTT 가 조용히 평문으로 degrade 된다.

### Windows (검증 완료 — 2026-08-14)

vcpkg + Visual Studio 2022(MSVC, x64) 조합으로 **빌드·실행**(2026-08-05)에 이어
**패키징과 타 PC 실행까지 확인**했다(2026-08-14). 아래 절차 그대로 하면 된다.

**1) vcpkg 설치 (1회)**

```powershell
git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
```

`vcpkg : '...' 용어가 cmdlet ... 으로 인식되지 않습니다` 는 vcpkg 가 PATH 에 없다는
뜻이다. `C:\vcpkg\vcpkg.exe` 처럼 전체 경로로 부르거나 PATH 에 `C:\vcpkg` 를 넣는다.

**2) 의존성 설치**

```powershell
C:\vcpkg\vcpkg.exe install qtbase[widgets,opengl] ffmpeg[avcodec,avformat,swscale] openssl paho-mqttcpp --triplet x64-windows
```

- `opengl` 은 3D 스캔 뷰가 쓰는 `Qt6::OpenGLWidgets` 때문에 필요하다. vcpkg `qtbase`
  의 기본 feature 라 예전처럼 `qtbase[widgets]` 로 깔아도 결과는 같지만, 이 앱이
  OpenGL 을 링크한다는 걸 드러내려고 명시했다.
- Qt 도 **vcpkg 의 `qtbase`** 를 그대로 썼다 — 그래서 configure 에 `CMAKE_PREFIX_PATH`
  가 필요 없다. 대신 qtbase 는 소스 빌드라 처음 한 번은 시간이 오래 걸린다. 공식 Qt
  설치 관리자로 받은 Qt 를 쓰려면 configure 에
  `-DCMAKE_PREFIX_PATH=C:\Qt\<버전>\msvc2022_64` 를 붙인다.
- `pkg_check_modules(FFMPEG ...)` 는 Windows 에서도 그대로 통한다 — vcpkg 가 pkgconf 와
  `.pc` 파일을 같이 깔아주기 때문에 pkg-config 를 따로 설치할 필요가 없다.

**3) 빌드 · 실행**

```powershell
cmake -S . -B build -A x64 `
  -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake `
  -DVCPKG_TARGET_TRIPLET=x64-windows
cmake --build build --config Release
.\build\Release\spatial_vms.exe
```

> Windows 에서는 `CMakeLists.txt` 가 `PAHO_MQTTPP_IMPORTS` 를 정의한다. paho-mqttpp3 를
> **DLL 로 링크**할 때 헤더 심볼이 `__declspec(dllimport)` 로 선언되지 않으면
> unresolved external symbol 로 링크가 깨진다. 반대로 static 트리플릿
> (`x64-windows-static`)으로 바꾸면 이 정의를 빼야 한다.

**4) 패키징**

```powershell
.\scripts\package_windows.ps1 -ExtraDllDirs "C:\vcpkg\installed\x64-windows\bin"
```

> ⚠️ **vcpkg 로 빌드했다면 `-ExtraDllDirs` 를 반드시 붙인다.** 스크립트는 DLL 을
> `-ExtraDllDirs` → 실행파일 폴더 → `PATH` 순으로 찾는데, vcpkg 의
> `installed\x64-windows\bin` 은 PATH 에 등록되지 않아 인자 없이 돌리면 Paho/FFmpeg/
> OpenSSL DLL 을 못 찾는다. 이때 스크립트는 **중단하지 않고 경고만 남긴 채 zip 을
> 만들기 때문에**, 그 zip 은 다른 PC 에서 실행 직후 DLL 오류로 죽는다. 실제 검증에서도
> 이 인자가 필요했다. 마지막 경고 목록이 비어 있는지 꼭 확인할 것.

`scripts/package_windows.ps1`이 하는 일:

1. `windeployqt --release --compiler-runtime` 으로 Qt DLL·플러그인·MSVC 런타임 수집
   (`Qt6OpenGL*.dll` 도 여기서 따라온다 — 별도로 챙길 필요 없다).
2. `windeployqt` 가 모르는 **Paho / FFmpeg / OpenSSL** DLL 을 와일드카드로 찾아 복사
   (`avcodec-62.dll` 처럼 버전이 파일명에 붙고, 그 번호는 vcpkg 가 받아온 FFmpeg
   버전마다 달라지기 때문). 못 찾으면 목록을 경고로 알린다.
3. **비밀정보 혼입 검사** — 스테이징에 `.key`/`.crt`/`.pem` 이나 `mqtt.json`/
   `cameras.json` 이 들어 있으면 중단한다. 배포본에 인증서를 담으면 받은 사람
   전원이 장비 명령 권한(`adts/cmd/#` 쓰기)과 카메라 admin 비밀번호를 갖게 된다.
4. `build\SPATIAL-VMS-windows.zip` 생성.

압축을 풀어 `spatial_vms.exe` 를 실행하면 등록 화면이 뜬다. 설치 프로그램
(Inno Setup 등)은 아직 없다 — zip 배포로도 동작하므로 우선순위를 낮췄다.

**검증 결과 (2026-08-14)**: `-ExtraDllDirs` 로 vcpkg `bin` 을 지정해 zip 을 만들고,
Qt/FFmpeg/Paho 가 설치되지 않은 다른 PC 에서 압축을 풀어 실행하는 것까지 확인했다.
아직 안 해 본 것은 **그 PC 에서 등록 마법사로 실제 발급까지 받아보는 것** — 발급
서비스(`/enroll`)가 아직 안 떠 있어서다(아래 TODO 2-1).

## 스캔 포인트클라우드 (Top-View)

스캔이 끝나면 `adts/state/scan` 이 `.pcd` **경로**만 준다(계약 §9). Qt 는 그 경로에서
파일명만 떼어 두 갈래로 찾는다 — `src/ScanFetcher`.

1. **로컬 `scans/`** 에 이미 있으면 그대로 읽는다(`resolveConfigPath` 순서를 따른다).
   개발 중 `scp` 로 받아둔 파일이 여기 해당한다. `scans/` 는 gitignore 대상이다.
2. 없으면 **`GET https://<host>:8443/scan/<파일명>`** 으로 받아온다.

2번을 위해 발급 서비스에 읽기 전용 경로를 추가했다(RPi 저장소 `broker/enroll_service.c`).
인증서를 발급하는 서비스에 파일 경로를 여는 것이라 세 겹으로 막았다:

- **검증된 클라이언트 인증서 필수.** `/enroll` 은 인증서를 받기 *전에* 부르는
  것이라 인증서를 요구할 수 없다. 그래서 `SSL_VERIFY_PEER` 만 켜고
  `FAIL_IF_NO_PEER_CERT` 는 켜지 않는다 — 핸드셰이크는 누구나 되지만 `/scan` 은
  핸들러에서 `SSL_get_verify_result` 를 직접 확인해 거부한다.
- **파일명만.** `/` 나 `%` 가 하나라도 있으면 400. 디렉터리는 `ADTS_SCAN_DIR`
  로 고정이라 경로 탈출이 성립하지 않는다.
  `%` 를 디코드하지 않고 거부하는 이유는 스캔 파일명에 인코딩이 필요 없고,
  디코더를 두는 것 자체가 우회 표면이 되기 때문이다.
- **`.pcd` 확장자만.**

### TLS 호스트명 (`server_name`)

8443 접속은 `mqtt.json` 의 `host`(보통 DHCP 로 받은 IP)로 하는데, RPi 서버 인증서
SAN 에는 발급 당시의 IP 와 `raspberrypi`/`localhost` 만 들어 있다. 주소가 바뀌면
`QSslSocket` 의 호스트명 검증에 걸려 `The host name did not match any of the valid
hosts for this certificate` 로 핸드셰이크가 깨진다 — **브로커는 붙는데 스캔만 안 오는**
모습이 된다(paho 는 `ssl_options.verify` 가 기본 꺼짐이라 8883 은 안 걸린다).

그래서 `mqtt.json` 의 `server_name`(기본 `raspberrypi`)으로 검증할 호스트명만
인증서상의 이름에 맞춘다. 사설 CA 체인 검증과 mTLS 는 그대로다. 서버 인증서를 현재
주소로 재발급했다면 `""` 로 두면 `host` 검증으로 돌아간다.

### 서버 쪽 전제 (RPi)

목록이 계속 `로컬 N건 · 서버 목록 실패` 로만 뜬다면 대개 Qt 가 아니라 RPi 쪽이다.
문구에 붙는 사유로 어디서 막혔는지 갈린다.

| 사유 | 뜻 | 조치 |
|---|---|---|
| `SSL handshake failed: The host name did not match…` | 인증서 SAN 불일치 | 위 `server_name` |
| `HTTP 404` + `없는 경로입니다` | 발급 서비스에 `/scans` 라우트가 없다 — 옛 바이너리 | RPi `develop` 로 `adts_enroll` 재빌드·재배포 |
| `HTTP 404` + `스캔 디렉터리가 없습니다` | `ADTS_SCAN_DIR` 을 서비스가 못 읽는다 | 아래 |

마지막 건이 헷갈린다. 유닛(`broker/adts-enroll.service`)에 `ProtectHome=true` 가
걸려 있어 **`/home` 아래는 경로가 맞아도 못 읽는다.** 데몬은 `/var/lib/adts/scans`
를 1순위로 쓰지만 그 디렉터리가 없으면 작업 디렉터리의 `./scans`(= 홈 아래)로 조용히
폴백하므로, 이 상태가 되면 파일은 쌓이는데 서비스는 하나도 못 본다. `/var/lib/adts/scans`
를 `pi` 소유로 만들어 두면 양쪽이 같은 곳을 본다.

수동으로도 열 수 있다 — 상단 메뉴 `모드 → 스캔 파일 열기… (.pcd)`.

점 색은 **높이**로 칠한다(낮음=짙은 청색, 높음=밝은 난색). 상태색(Ok/Warn/Danger)과
섞이지 않게 일부러 다른 계열을 쓴다 — "초록 점 = 정상"으로 읽히면 안 된다.
스캔이 방보다 넓게 찍히면 뷰가 자동으로 넓어진다(스케일 바에 `VIEW` 로 표시).

지원 형식은 데몬이 쓰는 **ASCII PCD**(`FIELDS x y z` / `DATA ascii`)뿐이다.
binary/binary_compressed 는 데몬이 만들지 않으므로 거부한다.

> PCD 원본 프레임은 `+x 오른쪽 / +y 아래 / +z 전방`, 원점은 센서다. Top-View 는
> `+x 오른쪽 / +y 북`이라 평면 투영은 `(x, z)` 를 그대로 얹으면 되고, 높이는
> 화면 관례(위가 +)에 맞춰 부호만 뒤집어 색상에 쓴다.

## 화면 구성

4개 탭: `메인 대시보드`(기본) / `CALIBRATION` / `DEVICES / MQTT` / `EVENT LOG`.
TopBar 버튼(HOME/SCAN/STOP/DISARM)의 활성화는 계약서 §5 상태-버튼 매핑을 따른다 —
DISARM 만 상태와 무관하게 항상 활성(비상정지). DISARM 상태에서는 HOME 버튼이
REARM 으로 바뀌어 `cmd/rearm` 을 발행한다.

스캔이 끝나면 데몬이 되감기 유예(15초) 뒤 스스로 DISARM 으로 내려가므로, 다음
스캔 전에 REARM 을 한 번 눌러야 한다.

## MQTT 토픽

> ⚠️ 계약서는 토픽에 `kit1` 세그먼트를 넣지만, **RPi 데몬 실구현에는 없다**
> (`daemon/modules/mqtt/mqtt_module.c`). 이 앱은 실구현 쪽에 맞췄다 — 아래가 실제로
> 오가는 토픽이다. 계약서가 재확정되면 `src/MqttBridge.cpp` 상단 상수와 함께 고칠 것.

| 토픽 | 방향 | QoS | Retained | 내용 |
|---|---|---|---|---|
| `adts/cmd/scan` | 발행 | 1 | **금지** | 스캔 시작 — `{req_id, pan_ddeg:[a,b], tilt_ddeg:[a,b], step_ddeg, sensor_height_mm}` |
| `adts/cmd/stop` | 발행 | 1 | 금지 | 스캔 중단 — `{req_id}` |
| `adts/cmd/home` | 발행 | 1 | 금지 | 스캔 없이 홈만 수행 — `{req_id}`. IDLE 에서만 받는다 |
| `adts/cmd/disarm` | 발행 | 1 | 금지 | 안전정지 — `{req_id}` |
| `adts/cmd/rearm` | 발행 | 1 | 금지 | DISARM 해제 — `{req_id}`. 계약 외 확장 |
| `adts/state/daemon` | 구독 | 1 | 예 | FSM/링크/IMU. LWT 로 데몬 사망 시 `state:"OFFLINE"` 자동 수신 |
| `adts/state/scan` | 구독 | 1 | 예 | 스캔 결과 — 파일 경로만(점 데이터 없음) |
| `adts/event/progress` | 구독 | 0 | 아니오 | 진행률 ~2Hz, 유실 가정(완료 판정은 state 로) |
| `adts/event/error` | 구독 | 1 | 아니오 | 오류 코드/메시지 |

접속이 안 될 때 브로커에서 직접 들여다보면 어느 구간이 끊겼는지 빨리 갈린다:

```bash
mosquitto_sub -h <RPi IP> -p 8883 \
  --cafile certs/ca.crt --cert certs/qt-console.crt --key certs/qt-console-trad.key \
  -t 'adts/#' -v -i debug-$$      # -i: 앱과 Client ID 가 겹치지 않게
```

`adts/state/daemon` 이 `"online":false` 면 브로커는 살아 있고 **RPi 데몬이 죽은** 것이다.

req_id 는 Qt 가 명령마다 생성(`MqttBridge::newReqId`)하고, 자신이 보낸 req_id 가
아닌 응답은 무시한다(`acceptsReqId`, 계약 §4).

## 구조

```
src/
├── main.cpp / MainWindow      # 5탭 셸, 시그널 배선, Demo/Live 전환, 카메라 설정, 로그아웃
├── CameraConfig.h             # PNM 시리즈 RTSP URL 조립(센서 0~3 → CH1~4)
├── ConfigPath.h               # 설정 파일 탐색(개발 트리 → 사용자 데이터 디렉터리)
├── EnrollDialog               # 최초 실행 등록 마법사 (1회용 토큰 → 인증서·설정 발급)
├── Theme.h / Models.h         # 디자인 토큰, 계약 스키마 데이터 모델
│                                 (DaemonState/ScanResult/ScanProgress/KitError)
├── DataBridge / MqttBridge / DemoBridge   # 계약 공용 시그널 인터페이스 + 구현체
├── RtspDecoder / RtspSource                # 채널별 RTSP 디코딩(FFmpeg) + config 로더
├── TopBar / TiltBanner / StatusBar        # 상단(HOME/SCAN/STOP/DISARM)/경고/하단 바
├── CameraTile / TopViewWidget / TopViewPanel  # 대시보드 좌(CCTV)/우(Top-View) 패널
└── CalibrationTab / DevicesTab / EventLogTab / SettingsTab   # 나머지 4개 탭

config/
├── cameras.example.json / cameras.json   # RTSP — 후자는 gitignore
└── mqtt.example.json / mqtt.json         # MQTT 브로커/인증서 경로 — 후자는 gitignore

certs/            # 개발용 인증서 — 통째로 gitignore
resources/
├── ca.crt / resources.qrc     # 사설 CA 공개 인증서 (발급 서버 검증용, 실행파일에 내장)
└── AppIcon.icns / AppIcon.ico / app.rc

scripts/
├── package_macos.sh           # .app 번들링 + .dmg (2026-08-14 재확인)
└── package_windows.ps1        # DLL 수집 + zip (2026-08-14 검증, vcpkg 는 -ExtraDllDirs 필요)
```

## 남은 TODO

1. ~~영상 디코딩~~ — RTSP+FFmpeg로 완료 (`src/RtspDecoder`).
2. ~~MQTT 프로토콜 구현~~ — 완료. RPi 데몬·브로커와 실제 연동 확인함(mTLS 8883,
   `state/daemon` 하트비트·IMU 수신). 토픽은 계약서가 아닌 데몬 실구현 기준.
2-1. **발급 서버(`/enroll`) 미구현** — 클라이언트는 위 계약대로 준비돼 있다.
   RPi 쪽 서비스가 뜨면 실제 발급까지 연결해 확인해야 한다. (담당: 송영빈)
2-2. ~~Windows 패키징~~ — 완료(2026-08-14). `package_windows.ps1` 로 zip 을 만들어
   의존성 없는 다른 PC 에서 실행까지 확인했다. vcpkg 빌드에서는 `-ExtraDllDirs` 가
   필요하다(위 4단계 경고 참고). 남은 건 그 PC 에서 등록 마법사로 실제 발급을 받아보는
   것으로, 2-1 이 풀려야 가능하다.
4. 카메라 단 캘리브 결과(NCC/edge_rmse/extrinsic) 표시 — 발행 토픽이 아직 없다
   (이영민 협의, 참고문서 3번 §9). 토픽이 정해지면 CALIBRATION 탭에 QUALITY
   패널을 추가한다.
5. ~~`state/scan`이 경로만 준다~~ — 전달 방식을 정하고 구현했다. 발급 서비스
   (8443)에 읽기 전용 `GET /scan/<파일명>` 을 달고, Qt 는 `state/scan` 을 받는
   즉시 그 파일을 가져와 Top-View 에 점군을 깐다 (`src/ScanFetcher`,
   `src/ScanCloud`). 계약 §9 를 이 방식으로 확정하면 문서도 고쳐야 한다.
   **아직 남은 것**: 실장비 왕복 검증(데몬·발급 서비스 재기동 후 1회), 그리고
   에지 추출 — 지금은 점을 그대로 찍을 뿐 벽/기둥 선분을 뽑지는 않는다.
