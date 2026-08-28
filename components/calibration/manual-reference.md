# Manual Calibration 출력물과 기준 자료

## 목적

Manual Calibration은 자동 Calibration의 후보를 독립적으로 진단하고, 카메라 intrinsic·왜곡 보정 입력을 고정하기 위한 기준 경로다. 여기서 생성된 `T_camera_lidar`는 LiDAR display-plane과 보드 geometry를 조합한 예비 추정값이며 제품 conformance ground truth가 아니다. 자연 평면을 이용한 targetless calibration 연구는 공통 planar region을 외부·내부 보정에 사용할 수 있음을 보여주지만[^P4], 이 문서의 태블릿 display-plane 절차는 해당 논문을 재현한 것이 아니다.

기록 기준일은 2026-08-25다. 출력물의 파일 위치와 생성 조건을 함께 남겨 인쇄·촬영·재실행 시 같은 board profile을 사용할 수 있게 한다.

구현 기준은 `auto_calib/develop`의 `2c98554`(2026-08-13)와 `f684cd6`(2026-08-24)이며, 아래 PDF·config는 해당 도구로 생성해 작업 공간에 보존한 Git 미추적 출력물이다.

## 출력물 목록

| 파일 | 상태 | 용도 |
|---|---|---|
| `develop/output/pdf/charuco_a4_7x5_dict5x5_100_280x200mm.pdf` | Git 미추적 출력물 | A4 landscape ChArUco board 인쇄용 PDF |
| `develop/output/pdf/charuco_a4_board_config.json` | Git 미추적 출력물 | board dictionary, 격자·마커 크기, 최소 코너 수 정의 |
| `develop/output/pdf/charuco_a4_print_spec.json` | Git 미추적 출력물 | A4 크기, 여백, 배율, 인쇄 후 실측 기준 |
| `develop/automatic_calibration/docs/CH1_ARUCO_VALIDATION_20260818.md` | Git 문서 | CH1 ChArUco 검증 이력 |
| `develop/automatic_calibration/docs/MANUAL_REFERENCE_PRIOR_WORKFLOW.md` | Git 문서 | Manual 결과를 prior/reference/hold-out으로 분리하는 규칙 |
| `develop/manual_calibration/docs/SESSION_CONST_ENV_CALIBRATION_RECORD.md` | Git 문서 | camera–marker와 LiDAR display-plane 예비 기준 기록 |

## 구현 도구

| 경로 | 역할 |
|---|---|
| `develop/manual_calibration/apps/generate_charuco_board.cpp` | board config를 읽어 ChArUco board와 출력 metadata 생성 |
| `develop/manual_calibration/apps/calibrate_camera_markers.cpp` | 다중 촬영 이미지에서 camera intrinsic과 distortion 계산 |
| `develop/manual_calibration/apps/estimate_marker_pose.cpp` | 고정 K+D로 camera–marker pose와 reprojection metric 계산 |
| `develop/manual_calibration/apps/compare_marker_to_automatic.cpp` | Manual reference와 Automatic 후보의 차이를 독립 비교 |
| `develop/manual_calibration/tests/manual_marker_tests.cpp` | board schema, pose, transform 비교 경로의 회귀 테스트 |

도구 구현과 출력물을 구분한다. C++ 실행기·schema·테스트는 Git 커밋 근거이고, `output/pdf/`의 PDF·JSON은 실제 인쇄 조건을 보존한 local output이다.

## Board 기준값

`charuco_a4_board_config.json` schema `1.0` 기준:

| 항목 | 값 |
|---|---:|
| dictionary | `DICT_5X5_100` |
| squares | `7 × 5` |
| square length | `0.027 m` / `27 mm` |
| marker length | `0.020 m` / `20 mm` |
| minimum ChArUco corners | `6` |
| legacy pattern | `false` |

`charuco_a4_print_spec.json` 기준:

| 항목 | 값 |
|---|---:|
| page | A4 landscape, `297 × 210 mm` |
| nominal PDF board size | `280 × 200 mm` |
| active board size | `189 × 135 mm` |
| page margin | left/right `8.5 mm`, top/bottom `5 mm` |
| print scale | `67.5%` |
| fit to page | `false` |

인쇄 후에는 PDF의 자동 맞춤을 끄고, 전체 board `189 × 135 mm`, marker `20 mm`, 한 칸 `27 mm`를 실측한다. 실측값이 다르면 해당 출력물을 같은 calibration profile로 사용하지 않는다.

## 수행 흐름

```text
board_config.json + print_spec.json
  -> PDF 출력 및 실제 치수 측정
  -> 고정 zoom/focus에서 ChArUco 이미지 수집
  -> camera intrinsic + distortion 계산
  -> raw image undistort
  -> camera–marker pose 계산
  -> 필요 시 LiDAR display-plane과 board geometry를 조합
  -> Automatic 후보와 별도 비교
```

카메라 intrinsic은 동일한 해상도·zoom·focus profile에 한해 재사용한다. Automatic 경로에서는 고정된 `K + distortion`을 입력하고 raw 영상에 왜곡 보정을 적용한 뒤 RT 후보를 평가한다.

## 문헌과 Manual 구현의 구분

| 구분 | 문헌에서의 의미 | 현재 Manual 경로 |
|---|---|---|
| 공통 평면 | 두 센서에서 같은 planar region을 관측해 calibration 제약으로 사용 | 태블릿 display-plane ROI와 board geometry를 조합하는 현장 진단 |
| intrinsic | 일부 targetless 방법은 plane 제약과 함께 intrinsic을 추정 | ChArUco 촬영으로 `K+D`를 먼저 계산하고 Automatic에 고정 |
| extrinsic | 공통 plane과 시각·거리 관측으로 센서 간 RT 계산 | `T_camera_marker_board`는 camera-side PASS, `T_camera_lidar`는 `T_lidar_marker_board` 독립 측정이 없으면 예비값 |
| 증거 수준 | 논문 데이터셋과 실험 protocol에 한정된 결과 | 현재 세션의 RMSE·plane residual·camera center 차이를 별도 기록 |

Plane-constrained joint intrinsic/extrinsic 연구도 존재하지만[^P8], 제품 경로에서 K와 RT를 동시에 최적화하면 profile·LDC·관측성 변화가 섞일 수 있으므로 현재는 K+D 고정 정책을 유지한다.

## 검증 결과 기록

현재 작업 기록에 남은 대표 기준은 다음과 같다.

| 항목 | 결과 | 해석 |
|---|---:|---|
| clean ChArUco intrinsic profile | 18장 PASS image, RMS `0.647 px` | 고정 camera profile의 입력 기준 |
| camera–marker pose | 24 ChArUco corners, RMSE `0.335255 px` | marker pose 검출은 PASS |
| LiDAR display-plane 후보 | 213 points, mean absolute residual `0.009081525 m` | 태블릿 평면 후보 진단 |
| Automatic repeat sample | 10세트 `FAIL / NID_IMPROVEMENT_INSUFFICIENT` | Manual 입력을 사용해도 자동 RT 승인 아님 |
| Manual-derived `T_camera_lidar` | `ESTIMATED_GEOMETRY_CORRECTED` | display geometry를 포함한 예비값 |

## 실험·검증 로그

### 2026-08-14 session-const-env 로그

| 항목 | 기록 |
|---|---|
| 장비 | PNM-C16083RVQ, TOFSense-F2P, Samsung Galaxy Tab S7 |
| 카메라 | `2592×1520`, 고정 zoom/focus, LDC 미적용 |
| LiDAR | schema `1.2`, `101×400`, `range_offset_m=0.084`, `+x right/+y down/+z forward` |
| ChArUco board | `7×5`, square `23.951 mm`인 tablet profile |
| intrinsic 입력 | clean PASS image 18장 |
| camera intrinsic RMS | `0.647 px` |
| marker pose | marker `17`, corners `24`, RMSE `0.335255 px`, max `0.573315 px`, `PASS` |
| display plane | ROI row `16~33`, column `216~228`, range `0.7~1.1 m`, 선택 `213 points` |
| plane residual | mean absolute `0.009081525 m`, max absolute `0.074652560 m` |
| RT 상태 | `ESTIMATED_GEOMETRY_CORRECTED`, 제품 reference 아님 |

이 세션에서 사용한 K와 distortion은 다음과 같다.

```text
K =
[[2033.901952,    0.000000, 1337.029701],
 [   0.000000, 2037.779638,  745.370056],
 [   0.000000,    0.000000,    1.000000]]

D = [-0.565317439, 0.344593856, -0.003914537,
      0.000818275, -0.108094125]
```

camera–marker pose:

```text
R_camera_marker_board =
[[-0.059942918, -0.996896946, -0.051022791],
 [ 0.881443672, -0.028873465, -0.471405745],
 [ 0.468469743, -0.073231153,  0.880439264]]

t_camera_marker_board = [0.163765177, -0.034758982, 0.962049769] m
```

display plane과 board geometry를 조합한 결과:

```text
R_lidar_marker_board =
[[-0.086063593,  0.994666943, -0.056839513],
 [ 0.996028662,  0.084595143, -0.027759086],
 [-0.022802699, -0.059002830, -0.997997346]]

t_lidar_marker_board = [-0.326785359, 0.233832926, -0.758170253] m

R_camera_lidar =
[[-0.983521425, -0.142621159,  0.111107212],
 [-0.077785218,  0.888586398,  0.452066005],
 [-0.163202535,  0.435974103, -0.885037578]]

t_camera_lidar = [-0.040047519, 0.074784187, 0.135763305] m
quaternion_xyzw = [-0.056854541, 0.969167865, 0.229072831, 0.070759091]
```

계산된 camera center를 LiDAR frame으로 역변환하면 `[-0.011413573, -0.131353120, 0.090797807] m`이다. 기존 장착 중심 측정값과 약 `125 mm` 차이가 남고 LiDAR plane max residual도 `74.65 mm`이므로 최종 정답으로 사용할 수 없다.

### 2026-08-18 A4 단일 probe 로그

| 항목 | 결과 |
|---|---|
| board 실측 | `DICT_5X5_100`, `7×5`, square `27 mm`, marker `20 mm`, active board `189×135 mm` |
| camera-side detection | marker `16/17`, corner `22`, RMSE `1.2826 px`, max `2.6274 px`, `PASS` |
| automatic 입력 | 단일 image pair, 고정환경 진단용 scan |
| search | yaw coarse `5°`, down `0~30°`, roll `-15~15°`, Manual K+D fixed |
| automatic 후보 | yaw `160°`, down `20°`, roll `0°`, NID improvement 약 `3.07%` |
| 최종 상태 | `FAIL / SINGLE_OBSERVATION_DIAGNOSTIC_ONLY` |

이 FAIL은 board 인식 실패가 아니라 pair가 하나여서 hold-out·반복성 조건을 충족하지 못한 fail-closed 결과다. `NID_IMPROVEMENT_INSUFFICIENT` gate와 `REJECTED CANDIDATE` debug overlay도 함께 보존했다.

### 2026-08-18 CH1 3-pair 반복 로그

| scene | image–scan 시각 차이 | marker/corner | RMSE | 결과 |
|---:|---:|---:|---:|---|
| 0 | `3 s` | `17/17`, `24/24` | `1.243 px` | PASS |
| 1 | `25 s` | `17/17`, `24/24` | `1.277 px` | PASS |
| 2 | `7 s` | `17/17`, `24/24` | `1.325 px` | PASS |

자동 실행 결과:

```text
status                 = PASS
candidate gate         = PASS
training               = 3/3 PASS
coarse yaw             = 170°
refined down           = 19.9989°
optical roll           = 0°
objective improvement  = 15.53%
NID improvement        = 1.08%
mean edge distance     = 19.92 px
projected ratio        = 0.7794
structural matches     = 71
Manhattan vertical err = 5.37°
```

이 실행은 세 장면 내부에서 일관된 후보를 얻은 로그지만, 독립적인 LiDAR–board 기준값이 없으므로 `PRODUCT_APPROVED_RT`가 아니다. Manual RT perturbation 24개 중 signal-strength NMI 진단도 PASS였으나, 이는 reference truth가 아니라 입력 profile·민감도 확인이다.

### 2026-08-19 다중 채널 profile 로그

`auto_data/aruco_marker` 관측 수는 CH1 `78`, CH3 `64`, CH4 `41`이었다. CH1은 유효 18장으로 `charuco-pass-clean18-20260814` K/D를 생성했고, CH3·CH4는 서로 다른 optical channel이므로 CH1 profile을 재사용하지 않는다.

카메라 이동만 있었고 resolution·zoom/focus·ROI/crop·LDC·flip/mirror/rotation이 같다면 K/D를 재사용하고 새 `R,t`만 추정한다. 이 조건 중 하나라도 바뀌면 새 intrinsic profile로 분리한다. 단일 image `20260819-200910-CH1.jpg`는 새 K/D 학습이 아니라 기존 profile을 적용한 RT/hold-out 진단으로 분류했다.

### 2026-08-24 Jenkins build22~24 camera-side audit 로그

두 ChArUco board가 같은 marker ID를 사용하므로 전체 frame을 한 번에 처리하지 않고 ROI를 분리했다.

| board | ROI `x,y,w,h` | build22 | build23 | build24 | 최대 반복성 |
|---|---|---|---|---|---|
| 모니터 앞 primary | `2090,700,500,650` | 16 marker/22 corner, RMSE `0.405639 px` | 15/19, `0.430960 px` | 17/24, `0.396608 px` | rotation `1.094355°`, translation `10.795 mm` |
| 파란 의자 secondary | `1200,1200,800,320` | 16/22, `0.639540 px` | 16/22, `0.598605 px` | 16/22, `0.553488 px` | rotation `0.922760°`, translation `4.229 mm` |

ROI crop에서는 principal point를 `cx_roi=cx_full-roi_x`, `cy_roi=cy_full-roi_y`로 보정하고 `fx`, `fy`, distortion은 유지했다. 세 build의 camera-side pose가 반복된다는 사실은 확인했지만, LiDAR JSON/PCD에는 marker ID와 board origin이 없으므로 전체 `T_camera_lidar` reference는 `RT_REFERENCE_INCOMPLETE`로 유지했다.

### 재현 명령과 출력 계약

```text
calibrate_camera_markers
  --board board_config.json
  --images-dir <intrinsic_images>
  --output-dir <intrinsic_output>

estimate_marker_pose
  --board board_config.json
  --camera camera_intrinsic.json
  --image <image>
  --roi <x,y,w,h>
  --output-dir <pose_output>

compare_marker_to_automatic
  --manual-pose <marker_pose_result.json>
  --board-in-lidar <T_lidar_marker_board.json>
  --automatic-result <calibration_result.json>
```

각 실행에는 marker pose JSON, overlay PNG, report MD, 사용한 board/K+D profile, ROI와 reprojection metric을 같이 저장한다. `T_lidar_marker_board`가 독립 측정되지 않은 경우에는 `T_camera_lidar`를 생성하더라도 상태를 `ESTIMATED_GEOMETRY_CORRECTED`로 남긴다.

## 사용 경계

- Manual ChArUco 결과는 intrinsic·왜곡 보정 및 독립 진단 기준으로 사용한다.
- LiDAR 평면에는 marker ID와 board origin이 없으므로 display geometry를 조합한 RT는 예비값이다.
- board 인쇄 배율, 태블릿 표시 배율, camera zoom/focus, LiDAR 좌표계가 바뀌면 기존 profile을 재사용하지 않는다.
- Automatic의 `CANDIDATE_RT/PASS`와 Manual의 camera–marker `PASS`를 서로의 제품 승인 근거로 합산하지 않는다.
- 최종 conformance 기준에는 독립적인 board-to-LiDAR 측량, CAD 지그 또는 별도 ground truth가 필요하다.

## 논문 근거 각주

[^P4]: L. Tamas and Z. Kato, “Targetless Calibration of a Lidar - Perspective Camera Pair,” *ICCV Workshops*, 2013. [CVF Open Access](https://openaccess.thecvf.com/content_iccv_workshops_2013/W21/html/Tamas_Targetless_Calibration_of_2013_ICCV_paper.html)
[^P8]: L. Li et al., “Joint Intrinsic and Extrinsic LiDAR-Camera Calibration in Targetless Environments Using Plane-Constrained Bundle Adjustment,” arXiv:2308.12629, 2023. [arXiv 원문](https://arxiv.org/abs/2308.12629)

## 산출물 보존 정책

PDF와 JSON은 Manual Calibration 출력물의 원본으로 작업 공간에 보존한다. docs 저장소에는 생성 조건·schema·실측 기준·검증 결과만 기록하고, 촬영 이미지·PLY·PCD·로그 전체는 복사하지 않는다. 개인정보, 장비 접속 정보, 로컬 절대 경로는 문서에 넣지 않는다.
