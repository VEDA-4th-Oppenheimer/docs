# 스캔 산출물 생성기

`RPi/daemon/core/scan_output.c`와 `scan_output.h`가 UART 스캔 점을 organized 격자에
병합하고 JSON·PCD로 기록하는 방법을 정리한다. 기준 코드는 RPi
`2f58d6e`(2026-08-24)이며 대상 파일은 `149bc63` 이후 변경되지 않았다.

| 항목 | 값 |
|---|---|
| 구현 계층 | `RPi/daemon/core/scan_output.*` |
| 핸들 | 불투명 `struct scan_out` |
| 입력 | `scan_request`, `proto_scan_point` |
| 출력 | JSON schema 1.2, organized PCD v0.7 |
| 기본 출력 경로 | `/var/lib/adts/scans`, 실패 시 `./scans` |
| Linux 전용 이벤트 API | 사용하지 않음 |

## 분리 경계

`scan_output`은 다음 책임만 가진다.

- 스캔 요청에서 계약 격자 크기를 계산한다.
- 기구각을 `lidar_scan` 계약각으로 변환한다.
- 점을 격자 셀에 배치하고 같은 셀의 샘플을 병합한다.
- home provenance와 진단 통계를 보존한다.
- JSON과 PCD를 기록한다.
- 기록 성공 여부와 결과 경로를 코어에 반환한다.

epoll, timerfd, ioctl, `/dev/turret`, FSM 전이는 `main.c`가 담당한다. `scan_output`은
Linux 전용 이벤트 API에 의존하지 않아 macOS·Linux host harness에서 좌표와 격자 로직을
직접 검증할 수 있다.

## 공개 API

| API | 역할 |
|---|---|
| `scan_out_open(req, offset, log_core)` | 요청 복사, 경로 준비, 격자 할당 |
| `scan_out_add(out, point)` | 점 하나의 각도 변환·인덱싱·병합 |
| `scan_out_set_home(...)` | home encoder raw와 계약각 provenance 기록 |
| `scan_out_close(&out)` | JSON·PCD 기록, 메모리 해제, 성공 여부 반환 |
| `scan_out_point_count(out)` | 처음 채워진 셀 수 반환 |
| `scan_out_path(out)` | PCD 경로 반환 |
| `scan_out_json_path(out)` | JSON 경로 반환 |
| `scan_out_expected_points(req)` | 진행률 분모 계산 |
| `scan_out_warn_seam(req, log_core)` | 팬 양끝 중복 평면 경고 |

핸들의 내부 구조를 header에 노출하지 않는다. 코어는 getter와 반환값을 통해서만 상태를
읽으며 격자 메모리나 writer 내부 필드를 직접 수정하지 않는다.

## 내부 상태

`struct scan_out`은 한 스캔의 수명주기를 소유한다.

| 상태 | 의미 |
|---|---|
| `req` | 호출자가 요청을 지워도 사용할 수 있는 요청 사본 |
| `lidar_offset_mm` | 회전축 교점에서 발광면까지의 거리 |
| `grid`, `grid_rows`, `grid_cols` | organized 셀 배열과 크기 |
| `pc_written` | 처음 채워진 셀 수 |
| `merged` | 이미 채워진 셀에 추가된 샘플 수 |
| `avg_refused` | 거리 분산 때문에 평균하지 않은 셀 수 |
| `drop_range` | 격자 범위를 벗어나 제외한 샘플 수 |
| `status_hist[4]` | LiDAR distance status 분포 |
| `scan_start_ns`, `scan_end_ns` | host monotonic 시간 범위 |
| `session_id`, `scan_id` | 파일과 JSON에 기록할 식별자 |
| `pc_path`, `js_path` | 최종 출력 경로 |
| `home_*` | home encoder raw와 각도 provenance |

한 `scan_cell`은 대표 샘플의 각도·거리·품질·시각과 병합용 거리 합계·최솟값·최댓값을
함께 보존한다. `filled == false`인 셀은 JSON `null`과 PCD `NaN`으로 출력한다.

## open 단계

`scan_out_open()`은 다음 순서로 핸들을 준비한다.

```text
1. scan_out 핸들 zero allocation
2. scan_request와 LiDAR offset 복사
3. 출력 디렉터리 생성
4. 현재 local time으로 session_id 생성
5. JSON·PCD 경로 생성
6. PCD 경로에 실제 probe file 생성·close·삭제
7. 요청에서 격자 행·열 계산
8. rows × columns scan_cell zero allocation
9. 통계와 monotonic 시작 시각 초기화
```

기본 디렉터리 `/var/lib/adts/scans`를 만들 수 없으면 `./scans`를 사용한다. 두 경로 모두
준비할 수 없으면 `NULL`을 반환한다.

디렉터리가 존재하는지만 확인하지 않고 PCD 최종 경로를 실제로 열어 본다. 기존 디렉터리가
읽기 전용이거나 daemon uid에 쓰기 권한이 없는 경우 스캔을 시작하기 전에 실패시킨다.
probe file은 close 후 삭제해 실패한 0B 산출물로 보이지 않게 한다.

session ID는 `calib-YYYYMMDD-HHMMSS`, scan ID는 현재 `sweep-000001` 형식이다.

```text
<dir>/calib-YYYYMMDD-HHMMSS_sweep-000001.pcd
<dir>/calib-YYYYMMDD-HHMMSS_sweep-000001_pan_tilt_lidar.json
```

## 격자 기하 계산

`grid_geometry()`는 요청 기구각을 계약각 영역으로 펼쳐 다음 값을 만든다.

```c
struct grid_geom {
    int32_t  step;
    int32_t  pan_origin_ddeg;
    int32_t  tilt_top_ddeg;
    uint32_t rows;
    uint32_t cols;
    bool     full_circle;
};
```

틸트 범위가 nadir를 가로지르면 한 기구 pan이 서로 반대인 계약 방위 두 개를 만든다.
이 경우 column 축을 360° 전체로 고정하고 관측하지 않은 방위는 빈 셀로 둔다. nadir를
가로지르지 않는 요청은 실제 pan span을 열 범위로 사용한다.

step이 0인 내부 방어 경로에서는 1.0°를 사용하지만 코어 요청 검증은 step 0을 스캔 시작
전에 거부한다.

`grid_index()`는 계약 pan을 origin 기준으로 wrap하고 `step/2`를 더해 가장 가까운 열로
반올림한다. full-circle에서 계산된 360° 열은 0° 열로 접는다. 행은 가장 높은 계약
tilt를 row 0으로 두고 아래 방향으로 계산한다. 범위를 벗어난 점은 `drop_range`만 올리고
셀에 넣지 않는다.

## add 단계

`scan_out_add()`는 점 하나를 다음 순서로 처리한다.

```text
proto_scan_point
  -> 기구각을 계약각으로 변환
  -> 계약각을 row·column으로 변환
  -> distance status histogram 갱신
  -> 빈 셀이면 대표 샘플로 기록
  -> 채운 셀이면 거리 분포에 병합
  -> 셀 중심에 더 가까운 샘플이면 대표 메타데이터 교체
```

기구각 변환식은 다음과 같다.

```text
m <= 0 : contract pan = p         contract tilt = -900 - m
m >  0 : contract pan = p + 1800  contract tilt = -900 + m
```

계약 pan은 `0..3599`로 정규화한다. 셀에는 계약각과 STM32가 보낸 기구각을 모두 남겨
좌표 변환 오류와 모터 위치 오류를 산출물만으로 구분할 수 있게 한다.

같은 셀에 추가 샘플이 들어오면 `n_samples`를 255에서 포화시키고 거리 합계·최솟값·
최댓값을 갱신한다. 대표 샘플은 계약각이 셀 중심에 더 가까울 때만 교체한다. 대표
메타데이터에는 그 샘플의 시각, 각도, signal strength, distance status가 들어간다.

## 거리 병합

출력 거리는 셀의 거리 분포에 따라 결정한다.

```text
spread = d_max_mm - d_min_mm
tolerance = max(30mm, d_min_mm × 15%)
```

샘플이 둘 이상이고 spread가 tolerance 이하이면 거리 합계를 샘플 수로 나눈 반올림
평균을 사용한다. spread가 크면 셀 중심에 가장 가까운 대표 샘플의 거리를 그대로 쓴다.

평균을 거부한 셀은 JSON quality flag와 `avg_refused` 진단 통계에 반영한다. 거리만
평균하며 각도·시간·품질 메타데이터는 대표 샘플 값을 유지한다.

## PCD writer

`write_pcd()`는 row-major 전체 격자를 ASCII PCD v0.7로 쓴다.

- filled 셀은 LiDAR distance에 `lidar_offset_mm`을 더해 meter 좌표로 변환한다.
- 빈 셀은 `nan nan nan`으로 쓴다.
- `WIDTH`, `HEIGHT`, `POINTS`는 전체 organized 격자 크기다.
- `sensor_height_m`는 header 주석에만 쓰고 좌표에 더하지 않는다.
- `ferror()`와 `fclose()`를 모두 확인한다.

버퍼 flush가 `fclose()`에서 실패할 수 있으므로 모든 `fprintf()`가 성공해도 close 실패를
출력 실패로 처리한다.

## JSON writer

`write_json()`은 같은 row-major 격자와 다음 provenance를 기록한다.

- interface·schema version
- session·scan ID와 daemon protocol version
- LiDAR model·주기·range offset
- frame 축과 좌표 변환식
- scan 요청·격자·시간·sensor height
- home encoder raw와 각도
- filled·merged·average refused·out-of-range 통계
- distance status histogram
- 셀별 대표 샘플과 병합 분포

빈 셀은 측정 필드를 `null`, `samples = 0`, `valid = false`로 기록한다. 채운 셀은 대표
샘플과 병합된 거리 통계를 함께 기록한다. writer는 `ferror()`와 `fclose()`를 확인한다.

## close 단계

`scan_out_close()`는 JSON을 먼저 쓰고 PCD를 쓴다. 두 writer가 모두 성공한 경우에만
`true`를 반환한다.

```text
write_json
  -> write_pcd
  -> 성공·실패 로그
  -> grid free
  -> handle free
  -> caller pointer = NULL
  -> json_ok && pcd_ok 반환
```

인자가 `NULL`이거나 이미 닫힌 핸들이면 `false`를 반환한다. 중단·종료 경로에서 여러 번
호출해도 double free하지 않는다.

코어는 반환값을 `shared_ctx.result.valid`로 전달한다. 하나라도 실패하면 유효한 산출물로
발행하지 않고 카메라 업로드도 시작하지 않는다. close가 끝나면 격자 메모리를 해제하므로
writer 실패 시 메모리에 있던 측정값을 복구할 수 없다.

## 진행률과 결과 getter

`scan_out_expected_points()`는 기구 pan·tilt span을 step으로 나눈 요청 위치 수를 계산한다.
표준 요청에서는 40,200이다. 이는 출력 격자 40,400셀과 다른 영역을 센다.

`scan_out_point_count()`는 처음 채워진 셀 수를 반환한다. 같은 셀에 병합된 샘플은 이 값을
올리지 않는다. `scan_out_path()`와 `scan_out_json_path()`는 핸들이 없으면 빈 문자열을
반환한다.

`scan_out_warn_seam()`은 nadir를 가로지르는 요청에서 pan span의 두 배가 360° 이상이면
양끝이 같은 수직 평면임을 경고한다. 표준 0.9° 요청은 pan 끝을 179.1°로 제한해 중복을
피한다.

## 검증

| 항목 | 결과 |
|---|---|
| macOS host harness, clang `-Werror` | 축 방향점·격자·JSON·PCD 생성 통과 |
| 표준 요청 예상 위치 | 40,200 확인 |
| 표준 organized 격자 | 101×400 확인 |
| 750pps Run 2 JSON·PCD 전수 대조 | 40,400셀 순서·NaN·병합 수 일치 |
| JSON에서 PCD 좌표 재계산 | 유한점 40,182개, 최대 차이 0.054mm |
| 진단 보존 항등식 | filled 40,182 + merged 13,573 = histogram 53,755 |
