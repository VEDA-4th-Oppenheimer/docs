# 스캔 좌표계와 산출물 계약

RPi 데몬이 생성하고 카메라 캘리브레이션과 Qt 포인트클라우드가 소비하는 JSON·PCD의
좌표계, 격자, 필드 의미를 정의한다.

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-DMN-31` |
| 담당 | 이현우 |
| 기준 구현 | RPi `2f58d6e` (2026-08-24), scan output은 `149bc63` 이후 변경 없음 |
| 산출물 | JSON schema 1.2 · organized PCD v0.7 |

## 산출물 역할

한 스캔은 같은 organized 격자를 표현하는 두 파일을 만든다.

| 파일 | 성격 | 소비자 |
|---|---|---|
| `..._pan_tilt_lidar.json` | 셀 대표 측정·병합 통계·기구·센서 메타데이터 | 카메라 캘리브레이션 |
| `..._sweep-000001.pcd` | 같은 격자를 3D 좌표로 투영한 파생물 | Qt 포인트클라우드 뷰 |

```mermaid
flowchart LR
  G[organized measurement grid] --> J[JSON schema 1.2]
  G --> P[organized PCD v0.7]
  J --> C[카메라 캘리브레이션]
  P --> Q[Qt 포인트클라우드]
```

JSON은 PCD 좌표를 재계산할 수 있는 계약 입력이다. 셀별 대표 샘플과 거리 분포를
보존하지만 병합 전 UART frame 전체를 보존하는 raw log는 아니다.

파일명 기준형은 다음과 같다.

```text
calib-20260821-162255_sweep-000001_pan_tilt_lidar.json
calib-20260821-162255_sweep-000001.pcd
```

## 기구각과 계약각

UART 스캔 점은 모터의 기구각을 담고 산출물은 `lidar_scan` frame의 계약각을 사용한다.
틸트 스윕이 nadir를 통과하므로 두 각 체계는 일대일로 같지 않다.

```text
기구 틸트 m <= 0 : 계약 pan = p         tilt = -900 - m
기구 틸트 m >  0 : 계약 pan = p + 1800  tilt = -900 + m
```

계약 pan은 `0..3599` 범위로 정규화한다. 각도 단위는 0.1도다.

| 기구각 `(p, m)` | 계약각 `(pan, tilt)` | 방향 |
|---|---|---|
| `(p, -900)` | `(p, 0)` | 벽 A 수평 |
| `(p, 0)` | `(p, -900)` | nadir |
| `(p, +900)` | `(p+1800, 0)` | 벽 B 수평 |

한 틸트 스윕이 방위 `p`와 `p+180°`를 함께 훑으므로 기구 팬을 약 180° 이동해 계약
방위 360°를 채운다.

## 계약 좌표계

frame 이름은 `lidar_scan`, 길이 단위는 meter다. 원점은 팬·틸트 회전축 교점이다.

```text
r = (distance_mm + 84mm) / 1000
x =  r · cos(tilt) · sin(pan)
y = -r · sin(tilt)
z =  r · cos(tilt) · cos(pan)
```

| 축 | 방향 |
|---|---|
| `+x` | right |
| `+y` | down |
| `+z` | forward |

84mm는 회전축 교점에서 라이다 발광면까지의 거리다. 라이다가 보고한 거리에 이를 더한
반경을 사용한다. `sensor_height_m`는 좌표에 더하지 않고 메타데이터로만 기록한다.

| 계약각 | 1.000m 반경의 좌표 |
|---|---|
| pan 0°, tilt 0° | `(0, 0, 1)` |
| pan 90°, tilt 0° | `(1, 0, 0)` |
| tilt −90° | `(0, 1, 0)` |
| pan 180°, tilt 0° | `(0, 0, −1)` |

## 표준 organized 격자

| 요청 기구각 | 값 | 출력 계약각 | 값 |
|---|---:|---|---:|
| pan | `0..1791` | 열 | 400 (`0..359.1°`) |
| tilt | `-900..+900` | 행 | 101 (`-90..0°`) |
| step | 9 (0.9°) | 셀 | 40,400 |
| height | 1805mm | 표준 소요 기준선 | 약 571.3초 |

팬 끝값 1791은 200줄 × 2방위 × 0.9°로 360°를 덮고 첫 줄과 마지막 줄이 같은 평면을
중복 스캔하지 않게 한다. nadir를 가로지르는 스캔은 방위축을 항상 360° 전체로 만들며
관측하지 않은 방향도 빈 셀로 보존한다.

진행률 분모인 표준 요청 위치 수는 40,200이고 출력 배열은 40,400셀이다. 전자는 기구각
요청 위치 수, 후자는 계약각으로 펼친 고정 격자 크기이므로 같은 수를 뜻하지 않는다.

### 셀 순서와 인덱싱

셀은 row-major 순서다. row 0은 가장 높은 계약 tilt이고 column은 계약 pan 증가 방향이다.
JSON과 PCD의 같은 `(row, column)`은 같은 방향을 나타낸다.

계약각은 `step/2` 기준으로 가장 가까운 셀에 반올림한다. full-circle 격자의 360° 인덱스는
0° 열로 접는다. 허용 범위를 벗어난 각도는 끝 셀에 고정하지 않고 제외하며 진단
카운터에 기록한다.

### 같은 셀의 측정 병합

같은 셀에 여러 샘플이 들어오면 거리 분포를 누적하고 셀 중심에 가장 가까운 샘플을
대표 메타데이터로 선택한다.

| 판정 | 조건 | 출력 거리 |
|---|---|---|
| 평균 가능 | `samples >= 2`, spread ≤ `max(30mm, min_distance × 15%)` | 반올림 평균 |
| 평균 거부 | spread가 허용치를 초과 | 대표 샘플 거리 |

평균 거부는 깊이 불연속의 앞뒤 표면을 섞어 실제로 존재하지 않는 중간 거리를 만드는
것을 방지한다. JSON의 `samples`, `spread_mm`, quality flag가 병합 결과를 설명한다.

## PCD v0.7

```text
# .PCD v0.7 - adts scan (organized)
# frame = lidar_scan (origin = pan/tilt axis intersection)  +x right +y down +z forward  unit = meter
# range_offset_m = 0.0840
# sensor_height_m = 1.8050
# session=calib-20260821-162255 scan=sweep-000001
VERSION 0.7
FIELDS x y z
SIZE 4 4 4
TYPE F F F
COUNT 1 1 1
WIDTH 400
HEIGHT 101
VIEWPOINT 0 0 0 1 0 0 0
POINTS 40400
DATA ascii
```

- `WIDTH × HEIGHT = POINTS`를 유지한다.
- 관측하지 않은 셀은 `nan nan nan`으로 기록한다.
- 관측된 셀은 `x y z`를 소수점 아래 4자리로 기록한다.
- PCD에는 기구각·센서 상태·병합 통계가 없으므로 해당 정보는 JSON에서 읽는다.

## JSON schema 1.2

| 블록 | 내용 |
|---|---|
| `interface_version` / `schema_version` | `1.0` / `1.2` |
| `session_id` / `scan_id` | 세션 시각 / 스캔 식별자 |
| `producer` | `adts_daemon`, protocol version |
| `sensor` | 모델, 100Hz, `range_offset_m` |
| `frame` | frame 이름·축·변환식 |
| `scan` | 격자 크기·계약각 범위·높이·시간 |
| `mechanism` | 기구각 요청·home provenance·각도 출처 |
| `diagnostics` | 병합·평균 거부·범위 밖·상태 histogram |
| `measurements` | 빈 셀을 포함한 40,400개 row-major 요소 |

```json
{ "sequence": 0, "row": 0, "column": 0,
  "timestamp_ns": 22991773463822,
  "device_time_ms": 22999333, "stm32_time_ms": 2053766,
  "pan_rad": 0.000000, "tilt_rad": -0.001745,
  "distance_m": 0.3250, "distance_status": 1,
  "samples": 4, "spread_mm": 4, "signal_strength": 8004,
  "range_precision_raw": 255, "checksum_valid": true,
  "angle_source": "step_count", "timestamp_source": "host_rx_monotonic",
  "valid": true,
  "quality_flags": ["VALID_RANGE","RANGE_AVERAGED","RANGE_PRECISION_NA"] }
```

### 필드 의미

| 필드 | 의미 |
|---|---|
| `scan.sample_count` | `rows × columns`, 즉 배열 길이 |
| `scan.valid_count` | 값이 채워진 셀 수 |
| `sequence` | 셀이 처음 채워진 순서 |
| `samples` | 해당 셀에 병합된 샘플 수 |
| `timestamp_ns` | 대표 샘플의 host 수신 monotonic 시각 |
| `distance_m` | 라이다 발광면 기준 거리. 좌표 계산 시 `range_offset_m`을 더함 |
| `valid` | 셀이 채워졌는지 여부 |
| `distance_status` | F2 P가 보고한 원본 거리 상태 |

빈 셀은 측정 필드를 `null`, `samples`를 0, `valid`를 `false`, `quality_flags`를
`["NO_MEASUREMENT"]`로 기록한다. 채워진 셀의 `valid`는 셀 존재 여부이므로 소비자는
품질 정책에 따라 `distance_status`와 `quality_flags`를 별도로 해석한다.

home provenance는 14bit pan·tilt encoder raw 값과 home 각도를 보존한다. 개별 측정각은
현재 `angle_source: "step_count"`이며 개별 `pan_encoder_count`와
`tilt_encoder_count`는 `null`이다.

## 발행 완료 조건

데몬은 JSON과 PCD를 모두 끝까지 기록하고 두 파일의 close 결과가 성공한 경우에만
`result.valid = 1`로 발행한다. 카메라 업로드와 Qt 결과 처리는 이 값을 확인한 뒤 파일을
소비한다.

`result.point_count`는 값이 채워진 셀 수다. PCD `POINTS`는 빈 셀을 포함한 organized
배열 길이 40,400이므로 두 값은 의미가 다르다.

## 검증 기준선

| 항목 | 근거 | 결과 |
|---|---|---|
| host conformance harness | 2026-08-24 clang `-Werror`, 축 방향점 4개 | expected 40,200, 격자 101×400, JSON·PCD 생성 통과 |
| 실측 쌍 전수 대조 | 2026-08-21 750pps Run 2, 40,400셀 | row-major·NaN·유한점·병합 수 일치 |
| 좌표 재계산 | JSON 거리·각도·84mm offset으로 PCD 전수 재계산 | 40,182점 일치, 최대 차이 0.054mm |
| 보존 항등식 | filled 40,182 + merged 13,573 | 상태 histogram 합 53,755와 일치 |
| 실기 시간 | 같은 Run 2 | 571.3초, filled 99.46%, 범위 밖 0 |
