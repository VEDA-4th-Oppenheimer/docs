# Automatic Calibration Core 구현과 커밋 이력

## 문서 기준

이 문서는 `auto_calib/develop/automatic_calibration`의 Calibration Core를 코드와 Git 커밋 기준으로 설명한다. 기준 branch는 `develop`, Core 기준선은 `f684cd6`(2026-08-24)이며, 이후 T1/T2 analyzer는 별도 실험으로 분리한다.

Core의 목적은 정적 자연 장면의 카메라 영상과 organized pan-tilt LiDAR scan을 비교해 `T_camera_lidar` 후보를 만들고, 품질이 부족하면 기존 prior를 유지하는 것이다.

## 커밋 이력

| 커밋 | 날짜 | 주요 변경 | Core 관점 |
|---|---|---|---|
| `c3461f7` | 2026-07-30 | 초기 Core workspace와 synthetic/문서 기반 | 알고리즘 실험 기준점 |
| `2c98554` | 2026-08-13 | workspace 재구성, Ubuntu native flow, real runner, Manual Calibration·Top View·schema·tests | 실제 입력을 받을 독립 실행 구조 구성 |
| `88758b6` | 2026-08-13 | CH1 sample data와 반복 진단 경로 | 실데이터 재현 기준 추가 |
| `f92626e` | 2026-08-20 | fixed Manual K+D, staged search, lifecycle, RT perturbation, Core 테스트 | 연구 경로와 제품 후보 경계 분리 |
| `f684cd6` | 2026-08-24 | 구조선·Manhattan·hold-out·Jenkins·Manual·fail-safe 검증 확대 | Core 실험 기준선 동결 |

`eaa4787`은 저장소 최초 README 기준을 만든 커밋으로, Core 구현 이력에는 포함하지 않고 개인 작업 이력에서 초기 문서 기준으로만 기록한다.

`c001d04`는 OpenSDK handoff 문서이며 Core 자체 구현이 아니다. `058ab97`, `b0d9cb0`, `53bfcba`, `2986691`, `79aeb0d`, `afd277a`는 analyzer 실험으로 별도 기록한다.

## 입력과 좌표계

```text
p_camera = R_camera_lidar * p_lidar + t_camera_lidar
```

| 항목 | 계약 |
|---|---|
| 영상 | BGR image와 동일 optical 상태의 camera profile |
| LiDAR | organized pan/tilt scan, meter/radian 계약 |
| 카메라 좌표 | OpenCV optical: `+x right`, `+y down`, `+z forward` |
| 추정 대상 | 제품 경로는 `R,t`; `K+D`는 Manual ChArUco profile로 고정 |
| prior | mechanical/camera-center prior는 제약·진단용으로 별도 기록 |

raw/rectified 상태, zoom/focus, LDC와 Manual profile이 일치하지 않으면 제품 승인 경로가 아니다. K+RT 공동 추정과 제조사 FOV K는 연구·진단 flag로만 둔다. 평면 제약을 이용한 K+RT 공동 추정 자체는 후속 연구 주제이지만, 현재 제품 경로는 K+D를 고정한다.[^P8]

## 처리 흐름

```text
RGB + camera profile
  -> grayscale / gradient / Canny distance
organized LiDAR scan
  -> range change / robust normal / plane segmentation
  -> plane intersection·boundary·persistent occlusion segments
  -> coarse score map
  -> separated contiguous basins
  -> 5° local -> 1° local
  -> up to 3 distinct Ceres R,t finalists
  -> training/core/quality gate
  -> common hold-out
  -> candidate 또는 fail-safe rejection
```

### 특징 추출

- Sobel gradient magnitude는 영상 구조 특징, Canny distance transform은 edge 위치 잔차에 사용한다.
- raw image는 Manual distortion coefficients로 한 번만 undistort한다.
- LiDAR range 변화와 robust surface-normal 변화는 별도 채널로 계산한다.
- 승인 평면의 교차선, 평면–미분류 geometry 경계선, 여러 관측에서 반복된 폐색선을 구분한다. 자연 edge의 추출 방식과 장면 내 edge 분포가 관측성에 영향을 준다는 선행 연구를 참고하되, 논문 구현·수치를 그대로 사용하지 않는다.[^P4][^P7]
- 단일 scan의 range discontinuity는 폐색 진단선이며 자동 승인 구조선으로 바로 사용하지 않는다.

### 목적함수와 gate

| 구성 | 역할 | 현재 정책 |
|---|---|---|
| range/normal geometry NID | LiDAR 기하와 영상 gradient의 공간 분포 비교 | 사용, 2×2 spatial cell. MI/NMI/NID 계열 문헌을 설계 참고로 사용[^P1][^P2][^P3] |
| edge alignment | 투영 LiDAR edge와 Canny distance 잔차 | 사용 |
| structural line | 2D LSD와 3D 선분의 방향·끝점·겹침·normal 일치 | gate/보조 목적. natural-edge·correspondence 계열과 비교 |
| Manhattan | 영상 소실 방향과 LiDAR 중력·벽축 비교 | prior/gate로 별도 기록 |
| signal-strength NMI | intensity 기반 진단 | 기본 가중치 `0`; surface-intensity MI는 반복성 conformance 전 제품 근거로 사용하지 않음[^P1][^P2] |

카메라는 360° LiDAR의 일부만 보므로 edge relative support를 단독 hard reject로 사용하지 않는다. NID·절대 support·공간 분포·구조 gate를 함께 판단한다.

## staged 탐색과 후보 선택

1. coarse yaw/down/optical-roll score map을 만든다.
2. 인접 8개 후보를 보정해 연속 고득점 영역을 찾는다.
3. 서로 다른 yaw 방향의 최대 3개 contiguous basin을 선택한다.
4. basin별 5° local search와 1° local search를 수행한다.
5. 최종 seed별 Ceres `R,t` refinement를 독립 실행한다. 2D–3D correspondence/RANSAC 후 direct NID refinement를 사용하는 선행 연구와 목적은 유사하지만, 현재 구현은 grid·basin 초기화를 사용하고 자동 correspondence/RANSAC은 미구현이다.[^P3]
6. training scene validation → Core gate → absolute support → objective/TESL/confidence 순으로 비교한다.
7. 선택 후에만 공통 hold-out을 평가한다.

최종 후보가 실패하면 차순위 `PASS`를 강제로 승격하지 않는다. 실패 후보는 debug JSON/시각화에만 남기고 기존 active RT 또는 mechanical prior를 유지한다.

## 상태 수명주기

| 상태 | 의미 | 활성화 |
|---|---|---:|
| `INTERNAL_GATE_PASS` | 현재 입력의 Core gate 통과 | 불가 |
| `CANDIDATE_RT` | training/제한 hold-out에서 후보 확인 | 불가 |
| `PRODUCT_APPROVED_RT` | 독립 기준·반복성·fail-safe 통과 | 별도 승인 후 가능 |
| `DIAGNOSTIC_ONLY` / `FAIL` | 원인 분석용 | 불가 |

`state`, `reason_code`, `candidate_available`, `internal_gate_pass`, `activation_allowed`를 분리해 기록한다. 현재 기준선은 후보가 있어도 `NOT_PRODUCT_APPROVED_RT`, `activation_allowed=false`다.

## 주요 API와 코드 맵

| API/파일 | 역할 |
|---|---|
| `calibrateExtrinsic` | 단일 장면 진단·추정 |
| `calibrateExtrinsicMultiScene` | 다중 장면 공통 `R,t`와 finalist 선택 |
| `segmentLidarPlanes` | robust normal·평면 분할 |
| `extractLidarStructuralSegments` | 평면 교차·경계·폐색 구조선 생성 |
| `evaluateSignalNmiPose` | signal-strength NMI 진단 |
| `automatic_calibration/src/calibration_core.cpp` | 특징·score·search·gate·refinement |
| `automatic_calibration/include/auto_calib/calibration_core.hpp` | config·metrics·result·공개 API |
| `automatic_calibration/apps/run_real_calibration.cpp` | pairing·K+D·실행 옵션·결과 저장 |
| `automatic_calibration/tests/` | 좌표계·합성·Core·stress·real 회귀 |

## 데이터 생성·실행·검증 지원

Core 알고리즘 외에 입력을 만들고 같은 조건으로 재실행하기 위한 도구도 함께 구현했다.

| 경로 | 기여 내용 |
|---|---|
| `automatic_calibration/src/synthetic_lidar.cpp` | Stanford 2D-3D-S RGB·z-depth를 organized pan/tilt LiDAR scan으로 변환하고 ground-truth transform과 생산자 metadata를 기록 |
| `automatic_calibration/apps/generate_synthetic_scan.cpp` | synthetic PCD·JSON·YAML 생성 |
| `automatic_calibration/apps/run_synthetic_calibration.cpp`, `run_multi_synthetic_calibration.cpp` | 단일·다중 synthetic scene에서 Core와 좌표계 계약 검증 |
| `automatic_calibration/apps/run_real_calibration.cpp` | 중첩 Jenkins package 탐색, channel 선택, 같은 parent directory pairing, deterministic sort, train/hold-out 분리, fixed-pose 검증과 debug 산출물 저장 |
| `automatic_calibration/apps/render_calibration_visualization.cpp` | initial·estimated pose overlay와 colorized point cloud 비교 |
| `automatic_calibration/tests/challenger_*`, `calibration_core_tests.cpp` | 반복 구조, ambiguity, coverage, hold-out, fail-safe 조건의 stress·회귀 검증 |

대표 결과는 `calibration_result.json`, `training_scene_validation.csv`, `holdout_scene_validation.csv`, `fixed_pose_validation_result.json`으로 남기며, 실행 기준 commit과 입력 package를 함께 기록한다.

## 실험·검증 로그

### 공통 실행 조건

| 항목 | 기준 |
|---|---|
| Core 기준선 | `f684cd6` / 2026-08-24 |
| 실행 이미지 | `auto-calib-dev:ubuntu-latest` 또는 동일 Docker 개발 환경 |
| 빌드 | CMake + Ninja, Release 계열, `/workspace-build` |
| 카메라 | PNM-C16083RVQ, CH1 우선, `2592×1520`, raw image |
| intrinsic | `charuco-pass-clean18-20260814` Manual ChArUco `K+D` 고정 |
| LDC | `unknown` 또는 비활성. 자동 실행에서 임의 LDC를 추가하지 않음 |
| camera center prior | LiDAR frame 기준 `(0.05928, -0.08105, 0) m` |
| search | staged coarse → separated basin → `5°` local → `1°` local → Ceres |
| product state | 모든 실행에서 `NOT_PRODUCT_APPROVED_RT`, `activation_allowed=false` |

### 결함 개선 및 회귀 로그

| ID | 발견된 문제 | 구현·검증 결과 |
|---|---|---|
| F1/F9 | 평면 후보가 책상·장애물을 지면으로 오인할 수 있음 | 점수 `≥200`, 면적 `≥1.0 m²`, 높이 `0.8~5.0 m`, pitch `5~60°`, normal tilt `≤85°` 조건을 적용 |
| F2/F3/F8 | 3D normal을 단순 x/y 성분으로 비교하면 비등방성 K에서 방향이 틀어짐 | `K^-T(R·Δn)` 공변 투영으로 수정하고 `fx≠fy`, 주점 오프셋 조건을 100,000회 Monte Carlo로 검증 |
| F4 | 다중 장면에서 TESL과 asymmetric structural weight가 0으로 남음 | 장면별 explained structural length를 전체 장면에 누적하고 `tesl_ratio`를 visible length로 정규화 |
| F5 | 희소 edge subset이 낮은 평균 오차로 false basin을 만들 수 있음 | scene별 visible edge/NID point 절대 하한과 `minimum_explained_structural_ratio=0.10` 적용 |
| F6 | `-123°` false basin과 `165°` 후보의 confidence 차이가 `0.0172`에 불과해 1위가 잘못 승격됨 | finalist confidence margin `<0.02`, 또는 support `<0.6×`이면 `FINALIST_AMBIGUOUS`로 fail-safe 처리 |
| F7 | NID 개선율을 `0%`로 완화해 기하 개선 없는 후보가 통과함 | `minimum_nid_improvement_ratio=0.01` 복원, `10^-7` micro-epsilon 비교 적용 |
| E2E | 테스트가 종료 코드 0만 확인해 오정합 후보를 놓침 | result JSON의 status/reason/product fields까지 확인하도록 real-result 검증 경로 보강 |

### CTest 9-suite 역사 로그

2026-08-21 R4 종합 기록은 9개 suite를 실행해 `9/9 PASS`, `0 FAIL`, 총 `78.08 s`를 기록했다. 이 결과는 이후 코드가 추가되기 전의 역사적 R4 로그이며, 최신 B0 11-case 실행 결과와 합산하지 않는다.

| suite | 결과 | 실행 시간 | 검증 내용 |
|---|---:|---:|---|
| `automatic_synthetic_lidar_tests` | PASS | `0.10 s` | 6-DoF transform round-trip, `K^-1` ray consistency |
| `automatic_calibration_core_tests` | PASS | `5.47 s` | plane segmentation, plane intersection, NMI, M1/M2/M3 core |
| `challenger_m1_2_stress_tests` | PASS | `43.52 s` | TESL monotonicity, absolute support 16-case truth table, 1,000회 재현성 |
| `challenger_m2_1_ambiguity_tests` | PASS | `<0.01 s` | confidence `<0.02`, support `<0.6×`, `15°` circular wrap |
| `challenger_m2_2_stress_tests` | PASS | `28.34 s` | normal gate `45°`, 1:1 greedy collision, 108 random poses |
| `challenger_m3_stress_tests` | PASS | `0.13 s` | NID 1%, `K^-T`, 100,000회 intrinsic fuzzing |
| `manual_marker_tests` | PASS | `0.20 s` | ChArUco pattern, camera/board·LiDAR/board transform composition |
| `top_view_tests` | PASS | `0.02 s` | Top-View projection and metadata serialization |
| `top_view_gui_smoke` | PASS | `0.29 s` | offscreen GUI argument parsing and smoke run |
| **합계** | **9/9 PASS** | **78.08 s** | **0 FAIL** |

### 실데이터 상태·reason 로그

| 데이터 실행 | 상태 | 선택 방향 | 핵심 metric | 해석 |
|---|---|---|---|---|
| 2026-08-18 Challenger | `CANDIDATE_RT / PASS` | yaw `166.24°`, down `20.82°`, roll `3.51°` | visible edge `861`, NID point `2,714`, mean edge `23.50 px`, confidence `0.7916`, bracket error `0.009 mm` | 물리 참값 후보와 일치하는 내부 결과 |
| 2026-08-19 remediation | `FAIL / COARSE_OVERLAP_INSUFFICIENT` | 후보 승격 없음 | 희소 후보의 절대 support 부족 | 참값 basin을 유지하고 fail-closed |
| 2026-08-19 legacy | `PASS`였던 false positive | yaw `-118.84°`, down `-3.69°`, roll `-20.69°` | mean edge `8.42 px`이나 bracket error `93.837 mm` | subset shrinkage를 보여주는 역사적 실패 사례 |
| Jenkins scene0 CH1 결합 | `CANDIDATE_RT / PASS` | yaw `168.09°`, down `28.31°`, roll `6.68°` | visible edge `1,674`, NID point `1,797`, mean edge `18.51 px`, confidence `0.5850`, bracket error `0.004 mm` | 다중 장면 후보. 제품 승인은 아님 |

브래킷 불변식은 `t = -R·C_lidar`로 검사했다. legacy false basin은 낮은 edge 오차에도 불구하고 `93.837 mm`를 위반했고, 2026-08-18 및 Jenkins 결합 후보는 각각 `0.009 mm`, `0.004 mm`였다.

### Jenkins build별 실행 로그

| Case | training | hold-out | 종료/상태 | 핵심 결과 |
|---|---|---|---|---|
| Case A baseline | build5·8·9 | build10 | exit `3`, `FAIL / FINALIST_AMBIGUOUS` | train `3/3`, hold-out scene `1/1`, objective `0.7524322`, margin `1.8209%` < 요구 `2%` |
| Case B stress | build17·18·19 | build20·21 | exit `0`, `CANDIDATE_RT / PASS` | train `3/3`, hold-out `2/2`, objective `0.7637627`, margin `6.4912%` |
| Case C primary | build22·23 | build24 | exit `0`, `CANDIDATE_RT / PASS` | train `2/2`, hold-out `1/1`, objective `0.8006294`, margin `2.9436%` |
| Case C RT → Case A | Case C RT 고정 | build5~10 | exit `0`, `INTERNAL_GATE_PASS` | 4/4 scene 내부 gate, 재추정 없음 |
| Case C RT → Case B | Case C RT 고정 | build17~21 | exit `0`, `INTERNAL_GATE_PASS` | 5/5 scene 내부 gate, 재추정 없음 |

Case A의 실패는 입력·빌드 오류가 아니라 finalist 간 margin 부족을 정상적으로 거절한 결과다. Case B와 Case C의 PASS도 내부 목적함수·hold-out gate 통과를 뜻할 뿐, 독립 `T_lidar_marker_board`가 없는 상태에서 제품 RT 정답을 뜻하지 않는다.

### 최신 Analyzer 기준선과의 구분

2026-08-25 B0 실행은 전체 11 cases 중 9 PASS, 2 FAIL을 기록했으며, 두 FAIL은 데이터 경로가 컨테이너에 mount되지 않은 환경 문제였다. Case C 자체는 `CANDIDATE_RT/PASS`, hold-out objective `0.8006294005`였다. 이 집계는 2026-08-21의 9-suite `100% PASS`와 실행 범위가 다르므로 누적 PASS율로 합치지 않는다.

## 검증 해석과 범위

커밋·dataset에 따라 테스트 집계가 5 suites, 8 suites, 9 suites, 최신 B0 11 cases로 달라진다. 이를 하나의 누적 PASS율로 합치지 않고 실행 기준별로 기록한다.

OpenSDK MobileSAM/LSD/TCP server 및 앱 통합은 Core 범위가 아니다. OpenSDK 앱에 포함된 낮은 버전 calibration Core를 최신 `auto_calib/develop` 변경에 맞춰 업데이트한 작업은 별도 연계 기여로 기록한다. Qt 공간 정합과 RTSP 분석은 Core 결과를 소비·진단하는 별도 작업이다.

## 논문 근거 각주

각주는 문헌이 제안한 방법과 현재 Core의 설계 비교를 설명하기 위한 것이다. 아래 각주는 우리 실험의 PASS/FAIL 수치나 제품 승인 상태를 증명하지 않는다.

[^P1]: G. Pandey et al., “Automatic Targetless Extrinsic Calibration of a 3D Lidar and Camera by Maximizing Mutual Information,” *AAAI*, 2012. [AAAI 원문 및 DOI](https://ojs.aaai.org/index.php/AAAI/article/view/8379)
[^P2]: Z. Taylor and J. Nieto, “Automatic Calibration of Lidar and Camera Images using Normalized Mutual Information,” *IEEE ICRA*, 2013. [저자 제공 원문 PDF](https://www-personal.acfr.usyd.edu.au/jnieto/Publications_files/TaylorICRA2013.pdf)
[^P3]: K. Koide et al., “General, Single-shot, Target-less, and Automatic LiDAR-Camera Extrinsic Calibration Toolbox,” *IEEE ICRA*, 2023. [arXiv 원문](https://arxiv.org/abs/2302.05094)
[^P4]: L. Tamas and Z. Kato, “Targetless Calibration of a Lidar - Perspective Camera Pair,” *ICCV Workshops*, 2013. [CVF Open Access](https://openaccess.thecvf.com/content_iccv_workshops_2013/W21/html/Tamas_Targetless_Calibration_of_2013_ICCV_paper.html)
[^P7]: C. Yuan et al., “Pixel-level Extrinsic Self Calibration of High Resolution LiDAR and Camera in Targetless Environments,” arXiv:2103.01627, 2021. [arXiv 원문](https://arxiv.org/abs/2103.01627)
[^P8]: L. Li et al., “Joint Intrinsic and Extrinsic LiDAR-Camera Calibration in Targetless Environments Using Plane-Constrained Bundle Adjustment,” arXiv:2308.12629, 2023. [arXiv 원문](https://arxiv.org/abs/2308.12629)
