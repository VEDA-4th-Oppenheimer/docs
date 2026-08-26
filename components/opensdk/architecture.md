# CV5 OpenSDK 카메라 애플리케이션 구조

Hanwha Vision CV5 기반 Edge AI CCTV에서 실행하는 A.D.T.S 카메라 애플리케이션의
런타임 구조와 앱별 책임을 정리한다. 공개 코드 기준은 OpenSDK `704fbd1`
(2026-08-19), `a0832b6` 및 `d94b862`(2026-08-24)다. 2026-08-24 로컬 작업본의
`tcp_server`·`calibration` 1.2 변경은 공개 커밋과 구분해 적는다.

| 항목 | 값 |
|---|---|
| 대상 장치 | Hanwha Vision CV5 기반 4채널 카메라 |
| 대상 구조 | AArch64, Cortex-A76 |
| 애플리케이션 언어 | C++17 |
| 실행 단위 | Open Platform CAP 애플리케이션 |
| 주요 SDK 서비스 | LifeCycleManager, AppDispatcher, OpenPlatformManager |
| 카메라 채널 | SDK `0~3`, 사용자 화면 `1~4` |
| 영상 입력 | OpenSDK JPEG Snapshot |
| 외부 측정 입력 | RPi 데몬의 mTLS LiDAR JSON 업로드 |

## 시스템 내 카메라 책임

STM32는 LiDAR·엔코더 측정과 스캔을 담당하고 RPi는 측정값을 organized JSON으로
정리한다. 카메라 단은 그 JSON을 수신하고 현재 영상을 취득하여 영상 처리나 외부
파라미터 추정에 사용한다.

```mermaid
flowchart LR
    STM32[STM32 / LiDAR / Pan-Tilt] -->|측정값| RPi[RPi 통합 데몬]
    RPi -->|mTLS TCP 2222 / JSON| TCP[tcp_server CAP]
    TCP -->|세션 JSON| Session[/tmp/calibration]
    Camera --> Preprocess[vision_preprocessing 작업본]
    Camera --> Calibration[calibration CAP]
    Session --> Calibration
    Calibration --> Core[run_real_calibration]
    Core --> Result[후보 외부 파라미터 / 진단 결과]
    Camera -.->|추가 검증 시 별도 실행| LSD[lsd_line_detection CAP]
    Camera -.->|추가 검증 시 별도 실행| SAM[sam_segmentation CAP]
```

MQTT 제어, Qt 관제, STM32 모터 구동 및 PCD 다운로드는 OpenSDK 앱의 직접 책임이
아니다. 수신 서버와 캘리브레이션 앱을 분리해 인증서·소켓 처리와 영상·알고리즘 처리를
서로 다른 CAP 경계에 둔다.

현재 자동 캘리브레이션의 실행 경로는 `RPi → tcp_server → /tmp/calibration →
calibration → run_real_calibration`이다. `lsd_line_detection`과 `sam_segmentation`은
이 경로에서 호출되지 않는다. LSD 선분 결과와 MobileSAM 마스크는 전처리·Core 입력·
목적함수·결과 판정에 사용하지 않는다. CV5에서 각 기능을 추가로 확인할 때만 별도
CAP으로 실행한다.

## 앱별 책임과 공개 상태

| 앱 | 주요 책임 | Git 기준 상태 |
|---|---|---|
| `tcp_server` | mTLS 연결, JSON 파일 수신·검증·저장, 서버 상태 표시 | `704fbd1`에 포함; 공개본 1.0과 로컬 1.2의 저장 경로가 다름 |
| `sam_segmentation` | 4채널 Snapshot, MobileSAM encoder·decoder 추론, 마스크 시각화 | `704fbd1`에 포함된 추가 검증용 독립 CAP; 현재 캘리브레이션 구조에는 미사용 |
| `lsd_line_detection` | `app/res`의 JPEG에 LSD를 적용하고 결과 이미지를 저장 | `704fbd1`에 포함된 추가 검증용 독립 CAP; 현재 캘리브레이션 구조에는 미사용, `LSD_REFINE_STD` 사용 |
| `calibration` | 세션 JSON 선택, 4채널 Snapshot, 채널 1 staging, Core 실행 | `a0832b6`에 포함; `d94b862`에 팀원의 알고리즘 갱신 포함 |
| `vision_preprocessing` | 4채널 Grayscale·Gaussian·CLAHE·Sharpening | 별도 로컬 작업본이며 공개 OpenSDK Git 트리에 없음 |

`d94b862`의 최신 targetless 알고리즘 갱신은 팀원 커밋이다. 카메라 앱 구성과 Core
이식·운영 통합을 담당한 이영민의 공개 커밋은 `704fbd1`, `a0832b6`이다.

## CAP 프로젝트의 공통 구조

```text
<app>/
├── config/app_manifest.json
├── docker-compose.yml
└── app/
    ├── CMakeLists.txt
    ├── toolchain.cmake
    ├── html/index.html
    ├── res/
    │   └── models/
    │       ├── AppDispatcher_manifest_instance_0.json
    │       └── AppDispatcher_default_attribute_0.json
    └── src/
        ├── PLifeCycleManagermanifest.json
        └── sample_component/
            ├── sample_component.cc
            ├── includes/sample_component.h
            └── manifests/
```

`config/app_manifest.json`은 앱 이름, 버전과 플랫폼 설정을 정의한다. `app/html`은
운영 화면, `app/res`는 모델·설정·dispatcher manifest, `app/src/sample_component`는
실제 이벤트 처리 로직이다. 빌드 과정은 CV5용 실행 파일과 공유 라이브러리를 모아
`opensdk_packager -s cv5`로 CAP을 생성한다.

## LifeCycleManager와 컴포넌트 생성

SDK가 제공하는 LifeCycleManager는 애플리케이션 manifest에 등록된 컴포넌트를 생성하고
종료한다. CMake는 SDK의 `life_cycle_manager`를 앱 실행 이름으로 배치하고 각
`SampleComponent`는 다음 진입점을 제공한다.

```cpp
extern "C" {
SampleComponent* create_component(void* mem_manager);
void destroy_component(SampleComponent* component);
}
```

초기화에서 저장 디렉터리를 준비하고 AppDispatcher에 API를 등록한다. `tcp_server`는
이 시점에 mTLS 서버를 별도 스레드로 시작하며, `calibration`은 작업 큐와 Core 실행
가능 여부를 준비한다.

```text
CAP 시작
  -> LifeCycleManager가 SampleComponent 생성
  -> Initialize()
       -> 저장소·설정 준비
       -> AppDispatcher URI 등록
       -> 앱별 서버 / worker 초기화
  -> ProcessAEvent()로 HTTP·플랫폼 이벤트 처리
  -> CAP 종료 시 worker와 소켓 해제
```

## AppDispatcher와 웹 API

앱은 `IAppDispatcher::OpenAPIRegistrar`로 경로와 HTTP 메서드를 등록하고,
`eHttpRequest` 이벤트에서 `PATH_INFO` 및 요청 본문을 해석한다.

| 앱 | API 또는 동작 | 설명 |
|---|---|---|
| `vision_preprocessing` | `POST /captureprocess` | 4채널 Snapshot과 전처리 실행 |
| `vision_preprocessing` | `GET /input0~3`, `GET /result0~3` | 채널별 원본·처리 결과 반환 |
| `sam_segmentation` | `GET /status`, `GET /input0~3`, `GET /result0~3` | 추가 검증용 독립 CAP의 진행률과 채널별 이미지 조회 |
| `tcp_server` | 상태 조회 화면 | 연결 수, 업로드 수, 마지막 파일과 오류 표시 |
| `calibration` | `GET /files`, `GET /status`, `POST /run` | 세션 목록, 작업 상태 및 선택 실행 |

AppDispatcher manifest 인스턴스가 빠지거나 GroupName이 앱 이름과 맞지 않으면
dispatcher 수신자가 생성되지 않는다. 이 경우 앱 웹 화면 문제로 보이더라도 실제 원인은
CAP 패키지의 컴포넌트 구성 누락일 수 있다.

## 4채널 Snapshot과 채널 번호

Snapshot은 `IPOpenPlatformManager::eAppSnapshotJpeg` 이벤트로 요청한다. SDK에는
0부터 시작하는 채널 번호를 전달하고, UI에는 1부터 시작하는 채널 번호를 표시한다.

| 사용자 채널 | SDK 채널 | 캘리브레이션 세션 파일 |
|---|---:|---|
| CH1 | 0 | `ch1.jpg` |
| CH2 | 1 | `ch2.jpg` |
| CH3 | 2 | `ch3.jpg` |
| CH4 | 3 | `ch4.jpg` |

```json
{
  "jpeg_path": "../storage/captured/example-ch1.jpg",
  "channel": "0",
  "app_name": "calibration"
}
```

OpenSDK의 Snapshot 호출은 컴포넌트 이벤트 스레드에서 수행한다. 현재 통합 경로의
Calibration Core는 `calibration` 앱의 worker에서 처리한다. 추가 검증용
`sam_segmentation`을 별도로 실행할 때만 MobileSAM 추론이 해당 앱의 worker에서
처리된다. 두 worker와 결과 데이터는 연결되지 않는다.

## 앱 간 공유 저장소와 버전 차이

로컬 통합 작업본 1.2의 `tcp_server`와 `calibration`은 다음 세션 경로를 공유한다.

```text
/tmp/calibration/calib-YYYYMMDD-HHMMSS/
├── calib-YYYYMMDD-HHMMSS_sweep-000001.json
├── ch1.jpg
├── ch2.jpg
├── ch3.jpg
├── ch4.jpg
├── staging/
├── output/
└── job_manifest.json
```

두 CAP의 실행 사용자가 다를 수 있으므로 공유 루트와 세션 디렉터리는 `01777`로
만든다. `/tmp`의 파일은 카메라 재부팅 후 유지되지 않는다.

공개 OpenSDK `d94b862`의 `tcp_server` 1.0은 아직 JSON을 `../storage/uploads`에
저장한다. 따라서 공개 저장소의 앱 두 개를 그대로 빌드하면 `calibration`이 기대하는
`/tmp/calibration` 경로와 일치하지 않는다. 통합 검증 전에 로컬 1.2 변경을 OpenSDK
저장소에 반영하거나 같은 공유 경로를 구현해야 한다.

## 구현과 검증의 구분

- MobileSAM은 CV5 CAP 구동 및 ONNX load/forward 기록이 있지만 추가 검증용이며,
  현재 자동 캘리브레이션 구조에는 사용하지 않는다.
- `lsd_line_detection`과 VPT-31/VPT-92 기준 구현은 추가 검증용이며 현재 자동
  캘리브레이션 구조에는 사용하지 않는다. 두 구현은 서로 다른 코드이므로 동일 기능으로
  간주하지 않는다.
- RPi→카메라 실제 mTLS 전송, 4채널 매핑, 재부팅과 장시간 반복 검증은 별도
  통합시험으로 확인해야 한다.
- Calibration 결과는 후보 또는 진단 결과이며 자동으로 제품 외부 파라미터를 적용하지
  않는다.
