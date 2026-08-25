# CV5 자동 캘리브레이션 애플리케이션

`calibration`은 LiDAR 측정 JSON과 4채널 CCTV Snapshot을 묶어 Calibration Core를
실행하는 OpenSDK 전용 CAP이다. 기준 코드는 OpenSDK `a0832b6`, `d94b862`
(2026-08-24) 및 같은 날짜의 로컬 `calibration` 1.2 작업본이다.

| 항목 | 값 |
|---|---|
| 앱 역할 | 세션 선택, 영상 취득, Core 실행과 후보 결과 관리 |
| 네트워크 수신 | 없음; `tcp_server` CAP이 담당 |
| 입력 루트 | `/tmp/calibration` |
| Snapshot 채널 | 사용자 CH1~CH4 / SDK `0~3` |
| 캘리브레이션 영상 | 사용자 CH1 / SDK `0` / `ch1.jpg` |
| 실행 파일 | `../bin/run_real_calibration` |
| 기본 Core timeout | `1800초` |
| 최대 대기 작업 | `4` |
| 웹 목록·상태 갱신 | `3초` |
| 결과 정책 | `candidate_only`; 외부 파라미터 자동 활성화 금지 |

## CAP 책임 경계

`calibration` 앱에는 TCP listener, mTLS handshake, 인증서 provisioning 코드가 없다.
JSON 수신은 별도 `tcp_server` CAP이 담당하고, 알고리즘은 `Automatic_Calibration_Part`
저장소에서 가져온 Core 실행 파일이 담당한다. 이 앱은 두 경계를 연결하는 카메라 측
어댑터다.

```mermaid
sequenceDiagram
    participant RPi as RPi camera module
    participant TCP as tcp_server CAP
    participant UI as calibration 웹 화면
    participant App as calibration SampleComponent
    participant Camera as CV5 Snapshot API
    participant Core as run_real_calibration

    RPi->>TCP: mTLS / LiDAR JSON
    TCP->>TCP: .part 검증 후 세션 JSON 게시
    UI->>App: GET /files
    UI->>App: POST /run / 선택한 file_name
    loop SDK channel 0~3
        App->>Camera: JPEG Snapshot
        Camera-->>App: ch1.jpg ~ ch4.jpg
    end
    App->>App: CH1 + JSON staging
    App->>Core: Core 실행 / 로그 및 timeout 관리
    Core-->>App: calibration_result.json
    App->>App: candidate_ready 또는 rejected
    UI->>App: GET /status
```

JSON 도착만으로 자동 실행하지 않는다. 운영자가 웹 목록에서 파일을 선택하고 시작을
눌러야 Snapshot과 Core 작업이 시작된다.

## 입력 파일과 세션 구조

```text
/tmp/calibration/calib-YYYYMMDD-HHMMSS/
├── calib-YYYYMMDD-HHMMSS_sweep-000001.json
├── ch1.jpg
├── ch2.jpg
├── ch3.jpg
├── ch4.jpg
├── staging/
│   ├── 000_image.jpg
│   └── 000_scan.json
├── output/
│   ├── core.log
│   ├── calibration_result.json
│   └── intermediate/
└── job_manifest.json
```

세션 파일명은 `calib-YYYYMMDD-HHMMSS`로 시작해야 한다. 앱은 `.part` 파일을
입력으로 사용하지 않으며 JSON에서 `interface_version`, `scan`, 비어 있지 않은
`measurements` 배열을 확인한다. 원본 JSON을 이동하거나 삭제하지 않는다.

서로 다른 CAP 사용자가 세션을 공유할 수 있도록 `/tmp/calibration`과 세션 디렉터리는
`01777` 권한을 사용한다. 장치 재부팅 시 `/tmp`의 JSON·Snapshot·결과는 사라진다.

## 4채널 Snapshot과 staging

Snapshot은 OpenPlatformManager의 `eAppSnapshotJpeg` 이벤트로 순차 요청한다.
처음에는 앱 전용 `../storage/captured`에 JPEG를 만든 뒤 공유 세션에 복사하고 임시
JPEG를 제거한다.

| 사용자 채널 | SDK 채널 | 세션 파일 | Core 사용 |
|---|---:|---|---|
| CH1 | `0` | `ch1.jpg` | 예 |
| CH2 | `1` | `ch2.jpg` | 아니오 |
| CH3 | `2` | `ch3.jpg` | 아니오 |
| CH4 | `3` | `ch4.jpg` | 아니오 |

```text
ch1.jpg            -> staging/000_image.jpg
original_scan.json -> staging/000_scan.json
```

네 채널을 캡처하지만 현재 Core에는 CH1과 LiDAR JSON 한 쌍만 전달한다. 4채널 전체의
독립 캘리브레이션 또는 다중 관측 학습은 현재 구현에 포함되지 않는다.

### job_manifest의 채널 표기 불일치

2026-08-24 작업본에서 실제 상수와 입력 선택은 CH1을 가리킨다.

```text
kCalibrationUiChannel  = 1
kCalibrationSdkChannel = 0
staging image           = ch1.jpg
```

그러나 `WriteJobManifest()`는 아래 값을 문자열로 고정 기록한다.

```json
{
  "calibration_channel": {"ui_channel": 3, "sdk_channel": 2}
}
```

즉 상태 API와 실제 staging은 CH1이지만 manifest 메타데이터는 CH3으로 잘못 표기된다.
결과 추적이나 검증 도구가 manifest만 읽으면 다른 카메라 채널로 오인할 수 있으므로
릴리스 전에 해당 값을 실제 상수와 일치시켜야 한다.

## 웹 API

| 요청 | 역할 |
|---|---|
| `GET /files` | 호환되는 세션 JSON 목록과 처리·대기 상태 조회 |
| `GET /status` | Core 실행 가능 여부, 채널 진행률, 세션, 오류와 경과 시간 조회 |
| `POST /run` | 선택한 JSON 파일에 대해 Snapshot과 작업 큐 등록 |

```json
{
  "file_name": "calib-20260824-120000_sweep-000001.json"
}
```

완료되었거나 `rejected` 상태인 세션은 다시 실행하지 않는다. 대기 또는 처리 중인
파일은 목록에서 별도 상태로 표시한다. 웹 화면은 3초마다 목록과 상태를 갱신한다.

### 상태 흐름

```text
waiting_for_selection
  -> capturing_channels
  -> calibration_queued
  -> preparing_calibration
  -> calibration_running
  -> candidate_ready | rejected

오류 분기:
  staging_failed | core_not_available | calibration_failed
  | result_validation_failed | manifest_failed
```

Core 자동 실행이 꺼져 있거나 실행 파일이 없으면 `ready_for_calibration` 상태로 남기고
원인을 기록한다. Core 종료 코드 `0`은 `candidate_ready`, `3`은 `rejected`로
처리하며 다른 코드는 실행 실패다.

## Core 실행 설정

로컬 1.2 작업본의 핵심 설정은 다음과 같다.

```json
{
  "auto_run_core": true,
  "executable": "../bin/run_real_calibration",
  "timeout_seconds": 1800,
  "arguments": [
    "--input-dir", "{staging_dir}",
    "--output", "{output_dir}",
    "--camera-channel", "1",
    "--image-distortion-state", "raw",
    "--manual-intrinsic-json", "../res/camera_intrinsic.json",
    "--search-strategy", "staged",
    "--camera-center-x-m", "0.05928",
    "--camera-center-y-m", "-0.08105",
    "--camera-center-z-m", "0",
    "--yaw-step-deg", "5",
    "--down-min-deg", "0",
    "--down-max-deg", "30",
    "--down-step-deg", "5",
    "--optical-roll-min-deg", "-15",
    "--optical-roll-max-deg", "15",
    "--optical-roll-step-deg", "5"
  ]
}
```

`{staging_dir}`, `{output_dir}`는 실행 직전에 실제 세션 경로로 치환한다. 공개 Git
`d94b862`의 설정은 `--manual-intrinsic`을 사용하지만 로컬 1.2는
`--manual-intrinsic-json`으로 수정했다. 실제 Core가 지원하는 옵션과 설정 JSON을 같은
버전으로 배포해야 한다.

기본 timeout은 1800초다. 과거 별도 실험에서 더 긴 timeout을 사용한 기록이 있더라도
현재 공개 코드와 로컬 1.2 설정의 기본값을 7200초라고 적으면 안 된다.

## 결과 검증과 자동 활성화 금지

Core 실행이 끝나면 `output/calibration_result.json`에 다음 값이 존재하는지 검사한다.

```json
{
  "status": "candidate_ready",
  "internal_gate_status": "example",
  "candidate_rt_status": "example",
  "product_approved_rt_status": "example",
  "reason_code": "example",
  "activation_allowed": false
}
```

문자열 값은 형식 설명용이며 실제 상태는 Core가 판정한다. `activation_allowed`가
`true`이면 앱이 결과를 거부한다. manifest도 `candidate_only: true`,
`activation_allowed: false`를 기록한다.

단일 CH1 영상과 단일 JSON의 결과는 후보 또는 진단 자료다. 여러 장면, hold-out,
ground truth와 승인 절차 없이 자동으로 카메라의 운영 외부 파라미터를 바꾸지 않는다.

## 시간 계측과 결과 보존

로컬 1.2는 웹의 시작 요청을 받은 시점부터 아래 작업의 전체 시간을 측정한다.

```text
request_elapsed_ms
  = 4채널 Snapshot
  + 작업 큐 대기
  + staging
  + Core 실행
  + 결과 검증 및 상태 기록
```

경과 시간은 `/status`, `job_manifest.json`, 앱 로그에 남긴다. Core 내부의
`runtime_ms`와 전체 요청 시간은 범위가 다르므로 같은 성능 지표로 비교하면 안 된다.

## 통합 전 확인 사항

1. `tcp_server`가 실제로 `/tmp/calibration/<session>`에 JSON을 게시하는지 확인한다.
   공개 `tcp_server` 1.0은 `storage/uploads`를 사용하므로 바로 연결되지 않는다.
2. CH1/SDK0 실제 이미지와 manifest의 CH3/SDK2 불일치를 수정·검증한다.
3. Core 옵션 이름과 `camera_intrinsic.json`을 동일한 소스 버전으로 맞춘다.
4. 정상 완료뿐 아니라 `.part`, 잘못된 JSON, Snapshot 실패, timeout, Core 종료 코드
   `3`, 재부팅 후 파일 소실을 시험한다.
5. `candidate_ready`를 제품 승인 또는 자동 적용과 혼동하지 않는다.
