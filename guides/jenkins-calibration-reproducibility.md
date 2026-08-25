# Jenkins Calibration 데이터 수집과 재현성 운영

## 목적

Jenkins 자동화의 역할을 세 단계로 분리한다.

```text
collection       = CCTV snapshot + LiDAR scan 수집
dataset packaging = image + PCD + JSON + manifest 보관
calibration test = 같은 dataset으로 Core 실행·검증
product approval  = 독립 기준·반복성·fail-safe를 별도 확인
```

Jenkins job의 `PASS`나 dataset 생성 성공은 `PRODUCT_APPROVED_RT`와 같은 의미가 아니다.

문서 기준은 `auto_calib/develop`의 `f684cd6`(2026-08-24)과 `automatic_calibration/docs/JENKINS_*.md`다. 현재 운영 중인 데이터 수집 Job과 별도 후속 Calibration Test 계획을 구분한다.

## 파이프라인

```text
현재 Freestyle 수집 경로
cctv_capture -> 3d_scan -> dataset_pack -> dataset archive

별도 후속 계획
dataset archive -> calibration_dataset_test -> result JSON/CSV/archive
```

| 단계 | 상태 | 입력 | 산출물 | 실패 분류 |
|---|---|---|---|---|
| `cctv_capture` | 현재 Freestyle Job | CCTV credentials와 channel 목록 | CH1~CH4 JPEG | camera/network/credential failure |
| `3d_scan` | 현재 Freestyle Job | scanner API와 scan timeout | PCD, pan-tilt JSON, scan event | device/link/home/scan failure |
| `dataset_pack` | 현재 Freestyle Job | capture·scan 결과 | archive, `manifest.json` | packaging/provenance failure |
| `calibration_dataset_test` | 별도 후속 Job 계획 | archive 또는 unpacked dataset | `calibration_result.json`, scene CSV, logs | Core gate/test failure |

수집 시작점인 `cctv_capture`는 정기 실행 스케줄을 가질 수 있고, 현재 Freestyle 구성 문서에는 세 Job의 성공·실패 Slack 알림도 기록되어 있다. 스케줄과 알림 성공은 데이터 내용이나 Calibration 정확도 검증을 대신하지 않는다.

## Dataset 계약

각 package directory가 image–scan pairing의 authoritative boundary다. 파일명 시각만으로 서로 다른 package를 조합하지 않는다.

| 규칙 | 내용 |
|---|---|
| image 선택 | `--camera-channel 1`이면 `_CH1` image만 사용 |
| scan 선택 | `*_pan_tilt_lidar.json`만 사용, `manifest.json`은 scan으로 취급하지 않음 |
| pairing | 같은 package 부모 디렉터리 안에서 image와 scan 연결 |
| ordering | scan filename 기준 deterministic sort |
| manifest | counts, session, build tag, checksum과 수집 메타데이터 보관 |
| hold-out | 마지막 pair를 `--holdout-count`로 optimization에서 제외 |

권장 package 구조:

```text
calib_dataset_build<N>_<timestamp>/
├── YYYYMMDD_HHMMSS_CH1.jpg
├── YYYYMMDD_HHMMSS_CH2.jpg
├── YYYYMMDD_HHMMSS_CH3.jpg
├── YYYYMMDD_HHMMSS_CH4.jpg
├── *_pan_tilt_lidar.json
├── *.pcd
└── manifest.json
```

## Capture·scan 자동화

현재 `data_storage`의 `3d_scan` Freestyle Job은 PCD와 `*_pan_tilt_lidar.json`을 회수한다. 저장소의 별도 통합 helper인 `jenkins-capture-and-scan.sh`는 다음을 수행한다.

1. Jenkins Credentials에서 CCTV password를 읽고 channel별 snapshot을 수집한다.
2. LiDAR HTTP service와 상태를 확인한다.
3. scan command의 `req_id`를 저장하고 event stream을 polling한다.
4. timeout·error event·`ok=false`를 감지하면 incomplete result를 성공으로 보관하지 않는다.
5. 정상 완료 후 PCD를 다운로드한다. 이 helper는 `*_pan_tilt_lidar.json`을 별도로 다운로드하지 않는다.
6. 요청 응답은 `scan-request.json`, 완료 event는 `scan-result-event.json`, event stream은 `lidar-events.ndjson`로 저장한다.
7. camera files, LiDAR PCD, Jenkins build tag를 `manifest.json`에 기록한다.

Credential, IP, token은 소스·문서·artifact log에 평문으로 남기지 않는다. 이 문서의 예시는 실제 접속 정보가 아닌 역할과 placeholder만 사용한다.

## Calibration 재현 조건

동일한 Core 결과를 비교할 때 다음을 고정한다.

| 범주 | 고정값 |
|---|---|
| source | Core commit, container/image, compiler/build type |
| camera | channel, resolution, zoom/focus, LDC/raw/rectified 상태 |
| intrinsic | 동일 Manual ChArUco K+D profile |
| geometry | camera center prior, LiDAR coordinate contract, range offset |
| search | staged/legacy, yaw/down/roll range와 step, hold-out count |
| data | package/build 번호, train/hold-out 역할, file hash |
| output | state, reason code, runtime, scene CSV, projection artifacts |

2026-08-21 scene0 기록에서는 3 training + 1 limited hold-out을 사용했다. build9/build10 CH1 image가 동일하여 마지막 pair는 완전 독립 camera–LiDAR hold-out이 아니므로 `limited hold-out`으로만 기록한다.

2026-08-24 계획에서는 build22·23을 training, build24를 development hold-out으로 분리했다. build24를 기준으로 threshold나 알고리즘을 튜닝하면 hold-out이 회귀 fixture로 오염되므로, 실행 후에만 판정하고 수정 근거로 재사용하지 않는다.

## 실험·검증 실행 로그

### 입력 무결성 로그

2026-08-24 build5~24 전체 활용 실행에서는 12개 CH1 package를 역할별로 분리했다.

| 항목 | 기록 |
|---|---|
| package 수 | `12` |
| package 구성 | CH1~CH4 image, JSON, PCD, manifest |
| package당 JSON measurement | `40,400` cells |
| valid JSON sample | `40,038~40,190` |
| checksum 오류 | `0` |
| angle out-of-range | `0` |
| PCD 사용 | automatic 계산은 JSON, PCD는 좌표·시각화 교차검사 |
| 공통 K+D | `charuco-pass-clean18-20260814` Manual profile |
| camera center prior | `(0.05928, -0.08105, 0) m` |
| product activation | `false` |

### ChArUco audit 로그

두 board가 같은 marker ID를 사용하므로 board별 ROI를 적용했다. corner threshold를 낮춰 expected fail을 PASS로 바꾸지 않았다.

| 대상 | ROI | 결과 |
|---|---|---|
| build5/8/9/10 chair | `850,1200,700,320` | 전체 PASS |
| build17 chair | `1650,1200,650,320` | PASS |
| build18 chair | `1500,1000,900,500` | `FAIL`, 5 corners < minimum 6 |
| build19~24 chair | `1200,1200,800,320` | 전체 PASS |
| build5~24 monitor | `2090,700,500,650` | build17만 `FAIL`, 나머지 PASS |
| 전체 | - | `22 PASS + 2 EXPECTED FAIL` |

camera-side pose는 automatic targetless 점수에 주입하지 않고 preflight/reference 진단으로만 사용했다.

### Case 실행 로그

| Case | 입력 분할 | exit | 상태 | 결과 |
|---|---|---:|---|---|
| A baseline | build5·8·9 train / build10 hold-out | `3` | `FAIL / FINALIST_AMBIGUOUS` | train `3/3`, hold-out scene `1/1`, objective `0.7524322`, margin `1.8209%` < `2%` |
| B stress | build17·18·19 train / build20·21 hold-out | `0` | `CANDIDATE_RT / PASS` | train `3/3`, hold-out `2/2`, objective `0.7637627`, margin `6.4912%` |
| C primary | build22·23 train / build24 hold-out | `0` | `CANDIDATE_RT / PASS` | train `2/2`, hold-out `1/1`, objective `0.8006294`, margin `2.9436%` |
| C RT fixed → A | Case C RT를 build5~10에 재추정 없이 적용 | `0` | `INTERNAL_GATE_PASS` | 4/4 scene |
| C RT fixed → B | Case C RT를 build17~21에 재추정 없이 적용 | `0` | `INTERNAL_GATE_PASS` | 5/5 scene |

Case C의 선택 후보는 현재 primary candidate로 보존하지만 `NOT_PRODUCT_APPROVED_RT`, `activation_allowed=false`다. Case A의 exit `3`은 입력/빌드 장애가 아니라 ambiguity를 거절한 정상 fail-closed 결과다. Case B는 stress 조건이며 제품 RT의 정확도 증거로 사용하지 않는다.

### 2026-08-21 scene0 반복성 로그

초기 scene0 3-training + 1-limited-hold-out 실행에서는 결합 결과가 다음과 같았다.

```text
status       = CANDIDATE_RT
reason       = PASS
selected yaw = -190° (circular 170°)
down / roll  = 29° / -1°
confidence   = 0.585022
mean edge    = 18.506 px
geometry NID = 0.931760
visible edge = 1,674
training     = 3/3 PASS
hold-out     = 1/1 PASS, mean edge 21.804 px
```

세 단독 실행은 모두 `INTERNAL_GATE_PASS`였지만 방향 반복성이 깨졌다.

| 비교 | rotation geodesic | translation 차이 |
|---|---:|---:|
| pair0 ↔ pair1 | `64.548°` | `65.055 mm` |
| pair0 ↔ pair2 | `68.564°` | `65.001 mm` |
| pair1 ↔ pair2 | `8.190°` | `8.429 mm` |

pair0의 `-128°` 후보와 다른 PASS 후보의 confidence 차이가 약 `0.00622`에 불과했으며, 당시 finalist 선택이 이를 `FINALIST_AMBIGUOUS`로 거절하지 못한 것이 단일 장면 false positive의 원인이었다. 이 로그는 다중 장면·finalist ambiguity gate가 필요한 근거다.

### 운영 실패와 테스트 실패 분리 로그

| 로그/상태 | 분류 | 처리 |
|---|---|---|
| CCTV password missing | collection failure | Jenkins Credentials 바인딩 실패로 중단 |
| LiDAR timeout/error event/`ok=false` | collection failure | 성공 archive로 저장하지 않음 |
| PCD empty | collection failure | archive 생성 실패 |
| JSON/PCD/image count mismatch | packaging failure | manifest mismatch로 분리 |
| B0 CTest 2건 data path 미mount | test environment failure | 알고리즘 PASS/FAIL에 합산하지 않음 |
| `FINALIST_AMBIGUOUS` | calibration test failure | 후보를 active RT로 승격하지 않음 |
| `COARSE_OVERLAP_INSUFFICIENT` | calibration gate rejection | 후보 없음 상태로 보존 |

## 결과 판정

```text
collection failure -> 데이터 수집 문제, Core 정확도와 분리
test failure       -> 동일 입력에서 Core gate/reproducibility 문제
CANDIDATE_RT       -> 후보 결과, active RT로 사용 금지
PRODUCT_APPROVED_RT -> 독립 기준·반복성·fail-safe까지 별도 통과해야 가능
```

현재 scene0/B0 결과는 후보·진단 상태를 유지하며 `activation_allowed=false`다. 내부 hold-out PASS는 독립 설치 ground truth나 장기간 반복성을 대체하지 않는다.

## Artifact와 로그 보존

최소 보존 세트:

```text
manifest.json
scan-request.json
scan-result-event.json
calibration_result.json
training_scene_validation.csv
holdout_scene_validation.csv
console.log
```

score map, debug image, PLY/PCD는 원본 작업 공간 또는 artifact archive에 보관하고, docs에는 상태·핵심 metric·재현 경로만 기록한다. 수집 실패와 테스트 실패의 로그를 하나의 성공 archive로 합치지 않는다.

## 운영 체크리스트

1. Jenkins build tag와 source commit을 저장했는가.
2. package별 image·PCD·JSON·manifest count가 일치하는가.
3. channel filter와 parent pairing을 적용했는가.
4. train/hold-out package가 사전에 고정됐는가.
5. K+D·distortion state·camera center prior가 동일한가.
6. `state`, `reason_code`, `activation_allowed`를 확인했는가.
7. generated 결과와 console log를 보존했는가.
8. job PASS를 제품 RT 승인으로 잘못 해석하지 않았는가.
