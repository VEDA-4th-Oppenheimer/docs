# 데몬 모듈 계약과 공유 상태

`RPi/shared/daemon_module.h`가 정의하는 코어-모듈 계약과
`RPi/daemon/core/main.c`, `RPi/daemon/modules/`의 실제 동작을 정리한다.
기준 코드는 RPi `2a683ee`이며 대상 파일은 `f51ba0f` 이후 변경되지 않았다.

| 항목 | 값 |
|---|---|
| 모듈 계약 버전 | `DAEMON_MODULE_VERSION = 5` |
| 실행 모델 | 단일 epoll 스레드 |
| 등록 방식 | 실행 파일에 정적 링크 |
| 등록 순서 | MQTT → IMU → LED → camera |

## 계약의 경계

현재 모듈 구조는 `dlopen()`으로 불러오는 플러그인이나 별도 공유 라이브러리 ABI가 아니다.
네 모듈은 `adts_daemon` 하나에 정적으로 링크되며 C 헤더와 함수 테이블을 공유한다.
`DAEMON_MODULE_VERSION`은 시작 로그에 기록되는 소스 계약 버전이고 런타임 호환성
협상이나 구조체 레이아웃 검사는 수행하지 않는다.

핵심 계약은 함수 호출보다 공유 상태의 writer와 reader를 고정하는 데 있다.

```text
모듈 -- 요청·측정값 기록 --> shared_ctx <-- 상태·결과 기록 -- 코어
                         |
                         +-- 100ms tick에서 요청 소비·정책 적용
```

모든 콜백은 코어의 단일 epoll 스레드에서 호출된다. 이 실행 모델 안에서는 락이 필요
없지만 별도 스레드에서 `shared_ctx`나 `notice_post()`를 호출하는 것은 계약에 포함되지
않는다.

## 모듈 등록과 역할

코어는 setup에서 정적 getter를 호출해 모듈을 등록한다.

```c
const struct daemon_module *regs[] = {
    mqtt_module_get(),
    imu_module_get(),
    led_module_get(),
    camera_module_get(),
};
```

| 모듈 | 역할 | `get_fd()` | 주요 write | 주요 read |
|---|---|---:|---|---|
| `mqtt` | 명령 수신, 상태·진행률·결과·통지 발행 | Mosquitto 소켓, 재접속 시 변경 | `req`, 모든 `req_*` | `state`, `progress`, `result`, `level`, `link`, `notice` |
| `imu` | `/dev/imu`를 1Hz로 판독하고 설치각 보정값 계산 | `-1` | `level` | `state` |
| `led` | LED·부저 출력과 물리 스위치 입력 처리 | `/dev/led_sw` | 기본 `req`, `req_disarm`, `req_rearm` | `state`, `link` |
| `camera` | EXPORT 진입 시 측정 JSON을 mTLS 업로드 | `-1` | 업로드 실패 `notice` | `result` |

장치나 외부 의존성이 없을 때 현재 모듈은 대부분 degraded 상태를 로그로 남기고
`init()`에서 0을 반환한다. 모듈이 음수를 반환하면 코어 setup이 실패하고 데몬 기동도
중단된다.

## 공유 상태 소유권

| 필드 | writer | reader |
|---|---|---|
| `state` | 코어 | 모든 모듈 |
| `req` | MQTT, LED, CLI | 코어 |
| `req_scan_stop` | MQTT | 코어 tick |
| `req_disarm`, `req_rearm` | MQTT, LED | 코어 tick |
| `req_home` | MQTT | 코어 tick |
| `progress` | 코어 | MQTT |
| `result` | 코어 | MQTT, camera |
| `level` | IMU | 코어 수평 게이트, MQTT |
| `link` | 코어 | MQTT, LED |
| `notice` | 코어, camera | MQTT |
| `core` | 코어 setup | `core_*` API를 쓰는 모듈 |

`state`는 코어만 쓴다. MQTT와 LED는 상태를 직접 바꾸지 않고 요청 구조체나 플래그에
의도를 기록한다. 코어는 tick에서 플래그를 소비하며 같은 tick의 rearm을 먼저,
DISARM을 나중에 처리해 안전정지가 최종 상태가 되게 한다.

## 상태와 요청

```c
typedef enum {
    ST_IDLE = 0,
    ST_SCANNING,
    ST_EXPORT,
    ST_DISARM,
} daemon_state_t;
```

오류는 별도 `ERROR` 상태가 아니라 `notice`와 링크 오류로 전달한다. 안전정지가 필요한
오류는 `ST_DISARM` 전이로 처리한다.

`scan_request.valid = 1`은 새 스캔 요청의 엣지다. MQTT, 물리 스캔 버튼, CLI가 요청을
만들고 코어가 소비한 뒤 0으로 내린다. 물리 버튼은 헤더의 표준 기본값을 사용한다.

| 상수 | 값 |
|---|---:|
| `SCAN_DEF_PAN_START_DDEG` | 0 |
| `SCAN_DEF_PAN_END_DDEG` | 1791 |
| `SCAN_DEF_TILT_START_DDEG` | -900 |
| `SCAN_DEF_TILT_END_DDEG` | 900 |
| `SCAN_DEF_STEP_DDEG` | 9 |
| `SCAN_DEF_HEIGHT_MM` | 1805 |

`sensor_height_mm`는 `lidar_scan` 좌표에 더하지 않고 산출물 메타데이터에만 기록한다.

요청 플래그는 큐가 아닌 1바이트 래치다.

| 플래그 | 처리 |
|---|---|
| `req_scan_stop` | SCANNING이면 현재 점까지 마감하고 EXPORT로 전이 |
| `req_disarm` | DISARM 전이 요청 |
| `req_rearm` | 링크 상태를 검사한 뒤 IDLE 복구 시도 |
| `req_home` | IDLE에서만 단독 홈 수행 |

## 진행률과 결과

`scan_progress`의 필드는 같은 대상을 세지 않는다.

| 필드 | 의미 |
|---|---|
| `points` | organized 격자에서 처음 채워진 셀 수 |
| `expected` | 요청한 기구 위치의 예상 개수 |
| `percent` | `min(points × 100 / expected, 100)`, `expected == 0`이면 0 |

표준 요청의 `expected`는 40,200이고 organized 출력 격자는 40,400셀이다. 코어는
EXPORT 진입 시 진행률을 강제로 100으로 바꾸지 않는다.

| 결과 필드 | 의미 |
|---|---|
| `path` | organized PCD 경로 |
| `json_path` | 카메라 단에 업로드할 organized 측정 JSON 경로 |
| `point_count` | 실제로 값이 채워진 격자 셀 수 |
| `stm_reported` | STM32 완료 점 수를 담기 위한 필드 |
| `valid` | JSON과 PCD를 모두 완전히 기록했으면 1 |

PCD는 빈 셀까지 포함한 40,400개 organized cell을 기록한다. 따라서 `point_count`와 PCD
헤더의 `POINTS`는 의미가 다르다. 현재 turret driver는 완료 점 수를 별도로 노출하지
않으므로 `stm_reported`는 0으로 남는다.

## 통지와 링크 상태

`notice_post()`는 `code`, `fatal`, `name`, `msg`를 먼저 기록하고 문자열의 NUL 종료를
보장한 뒤 마지막에 `seq`를 증가시킨다. MQTT는 `seq` 변화로 새 사건을 판정한다.

| 코드 | 이름 | 의미 |
|---:|---|---|
| 100 | `DISARM` | 안전정지 |
| 101 | `HOME_TIMEOUT` | 홈 대기 시간 초과 |
| 102 | `NOT_LEVEL` | 수평 게이트 거부 |
| 103 | `UPLOAD_FAIL` | 카메라 업로드 실패 |
| 104 | `BAD_REQUEST` | 요청 형식·범위 오류 |
| 105 | `EXPORT_FAIL` | 산출물 기록 실패 |
| 106 | `BUSY` | 현재 상태에서 요청 수용 불가 |

코드 100 이상을 사용해 STM32 오류 코드 대역과 구분한다. 게시 순서는 단일 스레드 계약
안에서만 유효하며 원자적 게시나 스레드 간 메모리 장벽을 제공하지 않는다.

`link_status`는 코어가 turret driver 상태를 복사해 만든 모듈용 스냅샷이다.
`status_seen == 0`이면 진단 카운터의 0은 정상값이 아니라 아직 알 수 없다는 의미다.

## 수평 상태

IMU는 SCANNING 중 판독을 건너뛰고 그 외 상태에서 1Hz로 `level`을 갱신한다.

```c
#define LEVEL_GATE_MAX_DEG       10.0f
#define IMU_INSTALL_ROLL_DEG     -3.0f
#define IMU_INSTALL_PITCH_DEG     4.0f
```

보정 후 `roll_deg`와 `pitch_deg`는 설치 기준 자세로부터의 이탈을 뜻하고,
`raw_roll_deg`와 `raw_pitch_deg`는 중력벡터에서 구한 원본 각도를 뜻한다. 코어의 수평
게이트와 MQTT 상태는 보정 후 값을 사용한다.

## 콜백 계약과 호출 순서

```c
struct daemon_module {
    const char *name;
    int  (*init)(struct shared_ctx *ctx);
    int  (*get_fd)(void);
    void (*on_event)(struct shared_ctx *ctx);
    void (*on_tick)(struct shared_ctx *ctx, daemon_state_t state);
    void (*on_state)(struct shared_ctx *ctx,
                     daemon_state_t old_st, daemon_state_t new_st);
    void (*deinit)(struct shared_ctx *ctx);
};
```

| 콜백 | 호출 시점 | 계약 |
|---|---|---|
| `init` | setup 1회 | 음수면 setup 실패, 0이면 계속 |
| `get_fd` | setup과 매 100ms tick | `>= 0`이면 epoll 등록, fd 변경과 동일 번호 재사용도 갱신 |
| `on_event` | 등록 fd의 이벤트 처리 | 코어 단일 스레드에서 호출, 논블로킹 I/O 필요 |
| `on_tick` | 요청 플래그 소비 뒤, FSM 평가 전 | 등록 순서대로 호출 |
| `on_state` | `ctx.state` 변경 직후 | MQTT → IMU → LED → camera 순서 |
| `deinit` | 종료 | 등록 순서대로 호출 |

카메라는 `ST_EXPORT`의 `on_state`에서 동기 업로드를 수행한다. MQTT 결과 발행과 LED
완료음 예약 뒤 카메라가 실행된다. 업로드가 끝나면 `core_hb_reprime()`이 마지막 PONG
기준 시각을 현재로 옮긴다.

timerfd와 모듈 fd가 같은 `epoll_wait()` 결과에 포함되면 배열 순서대로 처리한다.
timerfd 처리 뒤 모듈 `on_event`가 요청을 세운 경우 해당 요청은 다음 tick에서 소비된다.

## 코어 API

| API | 동작 |
|---|---|
| `core_request_state(core, want)` | 즉시 전이를 시도하고 0을 반환한다. 현재 등록 모듈은 호출하지 않는다 |
| `core_log(core, event, fmt, ...)` | monotonic timestamp와 event를 포함한 stderr 로그를 남긴다 |
| `core_hb_reprime(core)` | `hb_last_pong`을 현재 시각으로 바꾼다 |

등록 모듈은 상태 전이 API 대신 요청 필드를 사용한다. `core_hb_reprime()`은 블로킹 시간을
링크 단절로 오판하지 않게 하지만 블로킹 중 놓친 fd 이벤트를 복구하지는 않는다.

## 스캔 데이터 흐름

```text
MQTT 또는 LED on_event
  -> ctx.req 기록, valid = 1

core tick
  -> 요청 소비 및 홈 대기
  -> 수평 게이트 통과
  -> ST_SCANNING

turret fd event
  -> 점 스트림을 organized 격자에 병합
  -> ctx.progress 갱신

ST_EXPORT 진입
  -> JSON·PCD 마감
  -> ctx.result 기록
  -> mqtt on_state가 결과 발행
  -> led on_state가 완료음을 예약
  -> camera on_state가 json_path 업로드
```

## 검증

2026-08-24 ARM64 Linux 컨테이너에서 검증했다.

| 항목 | 결과 |
|---|---|
| GNU 13.3, C11, `-Wall -Wextra -Werror` 전체 빌드 | 통과 |
| cppcheck core·scan output·모듈 4종 | 통과 |
| `notice_post()` 순서·문자열 종료·상태 문자열 스모크 테스트 | 통과 |
| 장치·인증서·브로커 없는 degraded 기동과 SIGTERM 종료 | 4모듈 등록·정리 확인 |
| ARM64 관측 레이아웃 | `shared_ctx` 784B, `daemon_module` 56B |

구조체 크기는 현재 ARM64 빌드의 관측값이며 외부 바이너리 호환성 규격이 아니다.

## 관련 문서

- [데몬 코어](core.md)
- [스캔 좌표계와 산출물](../../../interfaces/scan-artifacts.md)
- [STM32-RPi UART 계약](../../../interfaces/stm32-rpi-uart.md)
