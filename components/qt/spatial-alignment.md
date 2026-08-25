# Qt CCTV–LiDAR 공간 좌표 정합과 2D/3D 시각화

## 문서 기준

이 문서는 `auto_calib/QT`의 `7935fc9`(2026-08-24, `lkj000619`)를 기준으로 한다. 해당 변경은 CCTV metadata와 LiDAR point cloud를 같은 공간 좌표계로 정합하고, Top-View 2D와 OpenGL 3D 화면에서 함께 확인하는 Qt pipeline을 통합했다.

## 처리 흐름

```text
calibration_profiles.json
  -> channel별 K+D+R,t profile
RTSP video/data/subtitle packet
  -> JSON/ONVIF XML metadata parse
  -> image 좌표면이면 camera ray + ground plane 투영
  -> top_view_m 객체
  -> 2D Top-View overlay + 3D point-cloud overlay
```

## Calibration profile과 좌표계

`config/calibration_profiles.json`은 channel별 image size, intrinsic `K`, RadTan distortion, `R,t`, ground height를 보관한다. Core 계약은 다음과 같다.

```text
p_camera = R_camera_lidar * p_lidar + t_camera_lidar
Top-View: +x = LiDAR X, +y = LiDAR Z(전방)
```

Automatic/Manual 모드를 전환하면 같은 K+D에 서로 다른 `R,t` profile을 적용한다. `SpatialProjector`는 profile을 JSON에서 읽고, scan cloud가 제공한 실제 room bounds가 있으면 기본 `±5 m` 범위를 덮어쓴다.

## Image-to-ground 투영

1. normalized pixel 또는 원본 pixel을 camera profile 해상도에 맞춘다.
2. OpenCV RadTan 왜곡을 최대 8회 iterative undistortion으로 역보정한다.
3. camera ray를 `Rᵀ`로 LiDAR frame에 변환한다.
4. `Y_lidar = groundY` 평면과 ray의 교점을 계산한다.
5. 얕은 하향각의 거리 폭발을 막기 위해 유효 ray와 최대 8 m 결과 cap을 적용한다.
6. `(x,z)`를 Top-View `(x,y)`로 저장한다.

사람 BoundingBox는 기본적으로 하단 중심을 사용한다. 상체·머리 위주로 잘린 box나 낮은 aspect ratio에서는 box 폭을 이용해 예상 발 위치를 보정한다. 결과는 방 경계로 clamp한다.

## Metadata 파서와 RTSP 연결

`SpatialMetadata`는 다음 입력을 인식한다.

| 입력 | 처리 |
|---|---|
| JSON `objects/detections/targets/persons/people` | id, class, confidence, x/y, bbox를 정규화 |
| ONVIF XML `Object` | `BoundingBox`, `CenterOfGravity`, `Type`, likelihood 파싱 |
| coordinate frame | `top_view_m`, `lidar_xy_m`, `kit_xy_m`, `world_m`는 Top-View로 취급 |
| image/pixel/bbox | profile이 있으면 ground 투영, 없으면 unprojected로 보존 |
| 분할 payload | channel별 metadata buffer로 다음 packet과 조립 |

`RtspDecoder`는 FFmpeg의 비디오 외 data/subtitle stream을 metadata 후보로 전달하고, metadata stream이 없으면 비디오 packet의 `BoundingBox`/`ObjectId` 흔적도 검사한다. `RtspSource`는 channel별 최신 객체 목록을 유지한 뒤 전체 channel 객체를 합쳐 UI에 전달한다.

## 시간 안정화와 화면 표현

동일 channel·track ID마다 독립 EMA tracker를 사용한다.

| 항목 | 기준 |
|---|---:|
| EMA alpha | `0.35` |
| EMA 적용 간격 | 이전 관측 후 `2.5 s` 이내 |
| tracker 정리 | `5 s` 초과 미관측 |
| room bounds | PCD 실측 bounds 우선, 기본 `±5 m` |
| IMU 수평 경고 | roll/pitch 절대값 `10°` 초과 |

## 함께 반영한 관제 진단

`7935fc9`에는 공간 정합 외에 센서 상태를 잘못 정상으로 표시하지 않기 위한 진단 계약도 포함된다.

- STM32 proto v6 누적 진단 카운터는 첫 유효 packet 전까지 `unknown`으로 취급한다.
- 오류의 pan/tilt/both axis bit를 보존해 화면에서 축별 원인을 구분한다.
- IMU 미수신 상태는 정상 수평으로 간주하지 않고, 유효한 roll/pitch가 `10°`를 초과할 때 수평 경고를 표시한다.

2D Top-View는 점군, 벽·기둥 edge, channel/object marker를 한 지도에 표시한다. 3D view는 floor `(x,z)`와 height를 `(x,y,-z)`로 바꾸어 OpenGL 오른손 좌표계에서 좌우 반전을 막는다. 점군은 높이 또는 거리 기반 color ramp를 사용한다.

## 이슈와 대응

| 이슈 ID | 문제 | 코드·검증 대응 | 현재 판정 |
|---|---|---|---|
| QT-SP-01 | 같은 metadata가 pixel 좌표인지 이미 투영된 Top-View 좌표인지 구분되지 않으면 이중 투영이 발생함 | `coordinate_frame`을 우선 해석하고 `top_view_m`, `lidar_xy_m`, `kit_xy_m`, `world_m`은 재투영하지 않음 | parser 회귀 대상 |
| QT-SP-02 | BBox 중심은 사람의 실제 발 위치와 다를 수 있음 | BBox 하단 중심을 기본값으로 사용하고 낮은 aspect ratio·상체 검출에는 폭 기반 발 위치 보정 | projection fixture에서 확인 |
| QT-SP-03 | metadata가 split packet으로 오거나 channel별로 도착함 | JSON/XML buffer를 channel별로 조립하고 최신 channel object를 merge; 빈 frame은 해당 channel을 clear | source test 코드 포함, 실행 transcript 별도 확인 필요 |
| QT-SP-04 | Qt 3D 좌표계 변환에서 전방축을 반전할 수 있음 | LiDAR Top-View의 `+y=+Z`를 OpenGL `(x,y,-z)`로 변환하는 계약을 고정 | 시각화 코드·회귀 기준 |
| QT-SP-05 | STM32 진단 counter가 첫 packet 전 0이면 정상으로 오인될 수 있음 | 첫 유효 packet 전 `unknown`, pan/tilt/both bit 보존, IMU roll/pitch `10°` 초과 시 경고 | proto v6 처리 기준 |
| QT-SP-06 | 테스트 이름과 실제 실행 transcript가 다르면 PASS를 과장할 수 있음 | 소스 등록, fixture 테스트, 실제 `LastTest.log`를 각각 분리 기록 | 아래 증거 수준 참조 |

## 검증 항목

`7935fc9`에 포함된 테스트·도구는 다음을 검증한다.

| 대상 | 검증 |
|---|---|
| `spatial_metadata_tests` | JSON, ONVIF XML, top_view/image frame, bbox, prefix/suffix payload, class normalization |
| `spatial_projection_tests` | CH1 BBox 투영, ONVIF BBox 투영, room bounds, 30 fps × 30초를 가정한 900-frame synthetic jitter EMA 안정화 |
| `rtsp_metadata_source_tests` | 다중 channel merge, split JSON/XML 조립, image-only unprojected 처리, channel clear; 소스와 CMake 등록은 확인했으나 실제 transcript에는 미기록 |
| `spatial_metadata_replay` | 실제 metadata fixture replay와 화면 확인 |
| `rtsp_metadata_probe.sh` | RTSP metadata stream과 packet 후보 확인 |

900-frame projection test는 실제 30초를 기다리는 wall-clock 테스트가 아니다. 30 fps × 30초를 가정한 synthetic BBox jitter loop에서 room bounds 이탈이 없고 frame 간 이동량이 `0.15 m` 미만인지 확인한다. 이는 특정 fixture와 profile에 대한 회귀 기준이지 실시간 처리 성능이나 모든 설치의 정확도를 보장하는 측량 검증은 아니다.

## 실험·검증 로그

### 커밋·빌드 범위

| 항목 | 기록 |
|---|---|
| 기준 commit | `7935fc9ca2dbe089df0b3255bc27dbfb4fb9e7be` |
| 작성자 | `lkj000619` |
| commit 일시 | 2026-08-24 18:09:52 KST |
| 변경 범위 | 33 files, `+2589/-536` |
| 포함 영역 | metadata parser, projection, profile, RTSP source/decoder, 2D/3D view, proto v6 diagnostics, tests/tools |
| 테스트 등록 | CMake `BUILD_TESTING`에서 metadata/projection/source test와 replay tool 등록 |

### 테스트 케이스 로그

| 대상 | 입력/시나리오 | 확인한 assertion 또는 출력 | 판정 범위 |
|---|---|---|---|
| `spatial_metadata_tests` | JSON objects/detections/targets, ONVIF XML, top-view/image frame, class normalization | `spatial_metadata_tests: PASS`; prefix/suffix payload, empty WiseAI event, nested XML까지 처리 | parser 계약 회귀 |
| `spatial_projection_tests` | CH1 BBox, ONVIF BBox, `groundY=1.789`, room bounds, ±10 px synthetic jitter | 900 frame 동안 `ok=true`, bounds 이탈 `0`, 거리 `0.5~6.0 m`, frame delta `<0.15 m` | 특정 fixture projection 회귀 |
| `rtsp_metadata_source_tests` | 다중 channel merge, channel clear, split JSON/XML, image-only object, channel 3/4 metadata | 소스에는 update sequence 1~6과 `PASS` 출력이 있으나 실제 `LastTest.log`에는 실행 기록이 없음 | source coverage; 실제 실행 증적 없음 |
| `spatial_metadata_replay` | `metadata_replay_fixture.json`, `metadata_replay_fixture.xml`, 실제 metadata 입력 선택 | offline point cloud와 2D/3D screenshot 생성 | 수동 화면 확인 도구 |
| `rtsp_metadata_probe.sh` | RTSP URL, FFmpeg `ffprobe`, TCP transport, stream/data packet selector | stream/packet log를 sanitize해 출력; 접속 실패 시 non-zero와 README 기록 | 현장 metadata stream probe |

### 실제 CTest transcript

`auto_calib/QT/build-repo/Testing/Temporary/LastTest.log`에서 확인되는 실제 실행은
다음 2개다.

```text
spatial_metadata_tests: PASS
  elapsed = 0.25 s

spatial_projection_tests: PASS
  elapsed = 0.21 s
  CH1 BBox -> TopView = (-1.86333, -3.10472)
  projected distance = 3.62095 m
  ONVIF object id = 2
  ONVIF class = PERSON
  synthetic frames = 900 (nominal 30 s at 30 fps)
  boundary violations = 0

CTest transcript summary = 2/2 PASS
```

따라서 `spatial_metadata_tests`와 `spatial_projection_tests`는 실제 transcript가
있는 fixture 회귀 PASS로 기록한다. `rtsp_metadata_source_tests`는 CMake 등록·소스의
assertion·PASS 출력은 확인되지만 위 transcript의 2/2 실행에는 포함되지 않았다. 이
테스트는 “실행 PASS”가 아니라 “실행 가능한 source coverage”로 기록하며, 실제 실행
후 별도의 stdout/stderr와 test count를 추가해야 한다.

### 900-frame synthetic 안정화 로그

```text
nominal frame rate       = 30 fps
nominal duration         = 30 s
generated frame count    = 900
BBox jitter              = ±10 px
room bounds              = x/y [-6, 6] m in test fixture
distance condition       = 0.5 m <= dist <= 6.0 m
boundary violations      = 0
frame delta threshold    = < 0.15 m
```

이 loop는 `sleep`이나 실제 RTSP frame clock을 사용하지 않는다. 따라서 시간적 입력 변화에 대한 projection/EMA 회귀 로그이지, 30초 wall-clock 처리율·drop rate·실제 위치 정확도 로그가 아니다.

### 검증 로그 보존 상태

소스의 PASS 출력과 CMake test registration은 `7935fc9`에 포함되어 있다. 현재 `auto_calib/QT` 작업 공간에서 별도의 CI terminal transcript나 장시간 실제 RTSP 실행 로그는 확인되지 않았으므로, 이 문서는 위 항목을 **소스/fixture 회귀 검증**으로 기록한다. 실제 장비에서 실행한 결과를 추가할 때는 camera profile, RTSP transport, fixture, 실행 시각, test binary hash, stdout/stderr와 screenshot을 함께 보존한다.

## 범위와 주의

- 이 문서는 Qt 관제 화면의 공간 표시·metadata 정합 범위를 다룬다.
- Calibration Core가 산출한 RT의 제품 승인 여부를 Qt가 대신 판정하지 않는다.
- RTSP 네트워크 원인 분석은 별도 분석 문서로 관리하며, 이 문서에는 parser·projection 연결만 기록한다.
- profile의 K+D, R,t, ground height, room bounds가 바뀌면 같은 fixture를 재사용하지 말고 profile version을 갱신한다.
