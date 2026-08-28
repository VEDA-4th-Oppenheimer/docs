# CV5 자동 캘리브레이션 알고리즘 통합과 성능 최적화

LiDAR 3D 측정과 CCTV 2D 영상의 외부 파라미터 후보를 추정하는 Core를 CV5 OpenSDK
환경에 통합한 방식과 최적화 범위를 정리한다. 공개 기준은 OpenSDK `a0832b6`,
`d94b862`(2026-08-24), 최적화 기준은 같은 날짜의 로컬 `calibration` 1.2 작업본이다.

`d94b862`는 광진(`lkj000619`)이 작성한 OpenSDK downstream 업데이트 커밋이다. 다만
여기에 반영된 targetless 파이프라인의 설계·구현 원천은 `auto_calib/develop`이며,
OpenSDK 앱의 최초 작성·Snapshot·CV5 운영 통합과는 구분한다. 이 문서는 낮은 버전의
Core 사본을 최신 Core 변경에 맞추기 위해 반영된 탐색·왜곡 보정·실행 설정과 CV5
통합 경계를 설명하며, 광진이 OpenSDK 앱 전체를 새로 개발했다는 의미로 사용하지
않는다.

| 항목 | 기준 |
|---|---|
| 입력 | organized LiDAR JSON과 CH1 CCTV JPEG |
| 결과 | 카메라-라이다 외부 파라미터 후보 `R`, `t`와 품질·거절 사유 |
| 대상 CPU | CV5 AArch64 / Cortex-A76 |
| 알고리즘 소스 | `Automatic_Calibration_Part`의 `develop` snapshot |
| 기본 탐색 | `--search-strategy staged` |
| Coarse 각도 간격 | yaw `5°`, down `5°`, optical roll `5°` |
| 하향각 범위 | `0~30°` |
| 광축 roll 범위 | `-15~15°` |
| Ceres solver thread | 로컬 1.2 기준 `2` |
| 자동 RT 적용 | 금지; 후보 결과만 보관 |

## 알고리즘과 OpenSDK 어댑터의 경계

```text
OpenSDK 어댑터
  -> LiDAR JSON 선택
  -> 4채널 Snapshot
  -> CH1 + JSON staging
  -> run_real_calibration 프로세스 실행

Calibration Core
  -> JSON / camera intrinsic 로드
  -> 원본 영상 왜곡 보정
  -> 2D / 3D 구조 특징 생성
  -> staged coarse-to-fine 탐색
  -> Ceres refinement 및 품질 gate
  -> candidate / rejection 결과 기록
```

알고리즘은 별도 프로세스로 실행한다. 앱은 Core 종료 코드, timeout, 로그와 결과 schema를
관리하되 알고리즘의 내부 판정을 덮어쓰지 않는다.

## 영상 왜곡 보정과 intrinsic

광각 카메라 원본 영상에는 radial/tangential distortion이 포함될 수 있으므로 CH1의
ChArUco 기반 intrinsic 프로파일을 입력한다.

```text
raw JPEG
  -> camera_intrinsic.json에서 K + distortion coefficients 로드
  -> cv::undistort
  -> rectified 영상에서 edge / 구조선 생성
```

| 설정 | 로컬 1.2 기준값 | 의미 |
|---|---|---|
| `--camera-channel` | `1` | CH1 intrinsic 및 결과 채널 |
| `--image-distortion-state` | `raw` | 입력이 왜곡된 원본임을 선언 |
| `--manual-intrinsic-json` | `../res/camera_intrinsic.json` | 실제 측정된 intrinsic JSON |
| `--ldc-enabled` | `false` | 영상이 이미 LDC 보정되었다고 가정하지 않음 |
| `--zoom-focus-locked` | `true` | 측정 당시와 동일한 렌즈 상태 전제 |

이미 보정된 영상에 `raw`를 적용하면 이중 보정이 발생할 수 있다. 카메라 채널, 해상도,
zoom/focus와 intrinsic 측정 조건이 다르면 해당 프로파일을 재사용하면 안 된다.

공개 `d94b862` 설정은 `--manual-intrinsic`, 로컬 1.2는
`--manual-intrinsic-json`을 사용한다. 실제 Core CLI의 지원 옵션을 먼저 확인해야 한다.

## 2D·3D 기하 특징과 품질 gate

| 특징 | 역할 |
|---|---|
| CCTV Sobel gradient / edge | 2D 영상 경계와 투영 LiDAR 특징의 일치 평가 |
| LiDAR surface normal / plane | 벽·바닥 등 3D 구조 평면 분할 |
| structural line | 3D 평면 경계 및 2D 영상 구조선 정합 |
| Manhattan direction | 수직·수평 구조 방향 제약 |
| spatial geometry NID | range·normal 특징과 영상 gradient의 공간 정합도 평가 |
| Z-buffer | 가까운 표면으로 가시 영역을 제한하고 가림을 처리 |
| finalist ambiguity gate | 서로 다른 방향 후보가 비슷하면 확정하지 않음 |

NID는 2×2 공간 분할을 포함하는 기하학 기반 평가에 사용된다. `signal_nmi_weight`가
0인 설정에서는 신호 세기 기반 NMI가 주 목적함수에 참여하지 않는다. 진단 출력이
존재하더라도 제품 승인 근거가 자동으로 생기는 것은 아니다.

## staged coarse-to-fine 탐색

전 방향의 세밀한 격자를 동일 비용으로 전수 평가하는 대신, 넓은 간격에서 유망한 방향을
찾은 다음 후보 주변만 좁혀 평가한다.

```text
전역 coarse 점수 계산
  -> Gaussian 인접 가중치로 basin 후보 생성
  -> 서로 다른 yaw 방향의 후보 최대 3개 선택
  -> 5° 지역 탐색
  -> 1° 지역 탐색
  -> Ceres 6-DoF refinement
  -> finalist ambiguity / 품질 gate
```

코드 기준으로 basin 후보는 최대 3개이며 서로 다른 yaw 방향 사이의 최소 분리값은
`30°`다. 가까운 후보만 반복 선택하는 것을 막아 대칭 구조에서 발생할 수 있는 방향
모호성을 줄인다.

기존 프로젝트 README에는 전수 탐색 약 `32,760`회/`47분`, staged 결과
`0.5~2초`라는 설명이 있다. 해당 수치는 같은 CV5 장치·입력·빌드 조건에서 반복
측정한 증적이 확인되지 않았으므로 목표 또는 참고치로만 취급한다. 장치 성능이
검증되었다고 표현하지 않는다.

## CV5 Release와 Cortex-A76

로컬 1.2의 Docker Compose는 Release 구성을 명시하고 Core 및 실행 파일에 CV5용 CPU
옵션을 적용한다.

```cmake
if(SOC STREQUAL "cv5")
  list(APPEND CALIBRATION_ARCH_COMPILE_OPTIONS
       $<$<CONFIG:Release>:-mcpu=cortex-a76>)
endif()
```

```bash
cmake -S app -B app/build \
  -DSOC=cv5 \
  -DCMAKE_BUILD_TYPE=Release
```

AArch64에서 Cortex-A76 대상으로 컴파일하면 해당 CPU의 Advanced SIMD/NEON 기반
최적화 경로를 사용할 수 있다. OpenCV 의존성 빌드에도 `CPU_BASELINE=NEON`을
지정한다.

```text
OpenCV CPU features: ... NEON ...
```

실행 로그에서 실제 CPU feature를 확인해야 하며 단순히 빌드 옵션이 존재한다는 사실만으로
특정 배속 향상을 주장하지 않는다.

## Ceres와 반복 계산 절감

로컬 `calibration` 1.2 변경은 다음 항목을 포함한다.

| 최적화 | 확인된 코드 또는 설정 |
|---|---|
| Ceres 병렬도 | solver의 `options.num_threads = 2` |
| CPU 대상 | Release에서 `-mcpu=cortex-a76` |
| OpenCV baseline | `CPU_BASELINE=NEON` |
| 비활성 신호 NMI | `signal_nmi_weight <= 0`이면 관련 준비·평가 경로 생략 |
| visibility 재사용 | 같은 pose의 Z-buffer를 여러 평가 항목에서 재사용 |
| 불필요한 refinement 준비 제거 | coarse/local 단계에서 필요한 항목만 준비 |
| 전체 요청 시간 측정 | `/status`, `job_manifest.json`, 앱 로그의 `request_elapsed_ms` |

Ceres thread 수는 CPU 코어 수만큼 늘리는 것이 항상 최선은 아니다. 카메라 영상 처리,
OpenSDK 런타임, 열 제한과 메모리 사용을 함께 고려해 실제 CV5에서 비교 측정해야 한다.

## 카메라-LiDAR 오프셋과 입력 계약

로컬 설정에서 CH1 광학 중심의 물리적 오프셋은 다음 값이다.

| 축 | 값 |
|---|---:|
| `camera-center-x-m` | `0.05928 m` |
| `camera-center-y-m` | `-0.08105 m` |
| `camera-center-z-m` | `0 m` |
| `legacy-range-offset-m` | `0.084 m` |

이 값은 2026-08-24 작업본 설정을 옮긴 것이며 다른 장치나 다른 카메라 채널에 그대로
적용할 수 없다. LiDAR 원점, encoder 각도, 스캔 방향과 카메라 좌표계가 일치하는지
실측 데이터로 검증해야 한다.

## 성능 계측 방법

서로 다른 시간 지표를 구분한다.

```text
Core runtime_ms
  = Calibration Core 내부 처리 시간

request_elapsed_ms
  = Snapshot + queue + staging + Core + 결과 검증
```

성능 비교는 다음 조건을 함께 기록한다.

1. 동일한 LiDAR JSON, 이미지 해상도와 camera intrinsic.
2. 동일한 staged/legacy 옵션, angular range와 품질 gate.
3. CAP 버전, Git commit, Release 여부와 CPU 옵션.
4. Core `runtime_ms`, 전체 `request_elapsed_ms`, 반복 횟수.
5. CPU 사용률, 최대 메모리, 장치 온도 및 thermal throttling.
6. 결과 `R`, `t`, ambiguity와 rejection 사유의 일치 여부.

속도만 빨라지고 결과의 재현성이나 품질 gate가 달라지면 동일한 개선으로 볼 수 없다.

## 미해결 검증 항목

- 단일 CH1·단일 observation 결과는 diagnostic/candidate 수준이다.
- 최소 여러 장면, hold-out, 반복 측정과 ground truth가 없으면 제품 승인 결과로 사용할
  수 없다.
- 공개 Git 버전과 로컬 1.2의 CPU 옵션, CLI 인자, 공유 저장소가 아직 같지 않다.
- `job_manifest.json`의 CH3 표기와 실제 CH1 입력이 다르다.
- `/tmp` 휘발성, 4채널 mapping, Core timeout 및 장시간 반복 실행은 장치 통합시험이
  필요하다.
