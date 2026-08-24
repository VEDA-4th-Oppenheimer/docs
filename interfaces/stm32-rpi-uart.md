# Protocol v6 통신 계약

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-PRT-10` |
| 파트 | Protocol (RPi ↔ STM32) |
| 담당 | 이현우 |
| 대상 소스 | `RPi/shared/protocol.h` (394줄) — STM32 는 바이트 동일 사본 |
| 기준 코드 | RPi `2a683ee` / STM32 `bd53921` (`main`, 2026-08-21) |
| 직전 기준선 | RPi `f51ba0f` / STM32 `c5c1c67`; 네 기준선의 canonical 헤더 해시가 같음 |
| 계약 버전 | v6 · SHA-256 `657b8c88…e689e7` |
| 상태 | 구조·사본 동일성 검증 완료 · 실기 오류율과 거절 경로는 관측 수단이 없어 부분 검증 |

---

## 1. 개요

`protocol.h` 는 세 곳에서 동일하게 사용되는 단일 진실 소스다.

1. RPi 커널 드라이버 (`/dev/turret`) — 프레임 조립·파싱
2. STM32 펌웨어 — 프레임 파싱·조립
3. RPi 유저 데몬 — ioctl 호출 + `read()` 스캔 스트림

같은 헤더가 커널·펌웨어·유저 세 빌드에서 같은 바이트 레이아웃을 만들어야 하므로,
헤더와 CI가 이를 강제하는 장치를 네 겹 갖는다.

| 장치 | 막는 것 |
|---|---|
| 플랫폼 타입 레이어 (4.1) | 커널/유저/펌웨어의 정수 폭 차이 |
| `__packed` + 리틀엔디언 전제 | 컴파일러 패딩 |
| 컴파일타임 크기 assert (4.7) | 한쪽만 구조체가 바뀌는 것 |
| CI `protocol-sync-check` | 사본 간 내용 drift |

### 1.1 버전 이력

| 버전 | 변경 |
|---|---|
| v4 | 안티드론 조준 명령 제거, 스캔 스트림 추가, tilt 부호각 확장 |
| v5 | 스캔 점에 라이다 원시 품질 필드 추가(6B→18B), `CMD_HOMED` 에 엔코더 원본값 추가 |
| v6 | 오류에 축(axis) 필드, `ERR_BUSY`/`ERR_ENCODER` 신설, `proto_status` 확장 + STM32 가 실제로 주기 송신 |

---

## 2. 적용 범위와 경계

| 다루는 것 | 다루지 않는 것 |
|---|---|
| 와이어 프레임 형식과 CRC | 모터 구동·엔코더 판독 (강유근) |
| 명령·이벤트 코드와 payload | 라이다 NLink 프레임 파싱 (송영빈) |
| 각도 규약(기구각)과 오류 코드 | 계약 좌표계 변환 → `RPi/daemon/core/scan_output.c` |
| `/dev/turret` ioctl ABI | 드라이버 내부 → `RPi/driver/turret_driver.c` |

### 2.1 사본 관리

- push 순서: RPi `main` 을 먼저 반영한 뒤 STM32 를 push 한다. drift-check 가
  RPi `main` 의 raw 를 보므로 역순이면 STM32 PR 이 막힌다
- 복붙 사본 금지: `driver/protocol.h` 같은 사본을 두면 Makefile 의 `-I$(src)` 가
  `-I$(src)/../shared` 보다 앞이라 마스터를 가려 옛 헤더로 빌드된다

저장소 사본 현황 (2026-08-24 재확인):

| 경로 | SHA-256 앞 16자 | 판정 |
|---|---|---|
| `RPi/shared/protocol.h` | `657b8c882f9cb8fa` | canonical v6 |
| `STM32/shared/protocol.h` | `657b8c882f9cb8fa` | 일치 |
| `Final_Project/protocol.h` | `20ce8e591853547b` | v3, stale |
| `motor/STM32/shared/protocol.h` | `63941510f9912c41` | 불일치, stale |

CI 는 canonical 쌍만 보호한다. 제품 빌드의 include 경로가 이 둘만 보게 해야 한다.

---

## 3. 설계

### 3.1 프레임

```
+------+------+------+---------------------+---------+
| SOF  | CMD  | LEN  |     PAYLOAD (0~24)  |  CRC16  |
| 0xAA | 1 B  | 1 B  |                     |  2 B    |
+------+------+------+---------------------+---------+
   0      1      2      3 ..                 마지막 2
```

| 상수 | 값 | 의미 |
|---|---:|---|
| `PROTO_VERSION` | 6 | 소스 수준 계약 버전. 와이어에 실리지 않는다 |
| `PROTO_SOF` | 0xAA | 프레임 시작 |
| `PROTO_HEADER_LEN` | 3 | SOF + CMD + LEN |
| `PROTO_MAX_PAYLOAD` | 24 | payload 상한 |
| `PROTO_CRC_LEN` | 2 | CRC16 리틀엔디언 (low byte 먼저) |
| `PROTO_MAX_FRAME` | 29 | 3 + 24 + 2 |
| `HB_TIMEOUT_MS` | 300 | heartbeat 판정 (데몬 소유) |

CRC 는 CRC-16/CCITT-FALSE(다항식 `0x1021`, 초기값 `0xFFFF`)이며 SOF 부터 payload
끝까지 계산한다.

헤더 순서는 SOF, CMD, LEN 이다. 일부 이전 문서의 SOF→LEN→CMD 표기는 소스와 다르며
2026-08-20 코드 감사에서 정정했다.

### 3.2 payload 상한 24

가장 큰 payload 는 `proto_scan_point`(18B), 다음이 `proto_status`(15B)다. 이 상한이
설계를 강제한 사례로, `proto_status` 의 진단 카운터를 u32 로 하면 25B 가 되어 상한을
넘는다. 그래서 u16 + 포화로 설계했다(4.5).

### 3.3 버전을 와이어로 보내지 않는 이유

CI drift-check 가 지키는 것은 RPi·STM32 canonical 사본 두 개뿐이다. 드라이버의
payload 길이 불일치 경고는 `HOMED`·`STATUS`·`ERROR` 일부 경로에서 구 펌웨어를
발견할 수 있지만, `SCAN_DATA`·`SCAN_DONE` 길이 불일치는 조용히 버리고 같은 크기의
의미 변경도 잡지 못한다. 따라서 이 경고가 와이어 버전을 완전히 대신한다고 보지 않는다.

ioctl 쪽은 자동으로 걸린다. `struct turret_link_state` 가 v5·v6 에서 두 번 커져
`_IOR` 인코딩이 바뀌었으므로 구버전 유저스페이스는 `-ENOTTY` 로 즉시 실패한다.

> **드라이버와 데몬은 함께 재빌드한다**
> 한쪽만 갱신하면 `TURRET_GET_STATE` 가 `-ENOTTY` 로 실패한다.

---

## 4. 구현 — 코드 해설

### 4.1 플랫폼 타입 레이어 (`:21~34`)

```c
#ifdef __KERNEL__
  #include <linux/types.h>
  typedef __u8  proto_u8;
  typedef __u16 proto_u16;
  typedef __s16 proto_s16;
  typedef __u32 proto_u32;
#else
  #include <stdint.h>
  typedef uint8_t  proto_u8;
  ...
#endif
```

커널 빌드는 `linux/types.h`, 유저·STM32 빌드는 `stdint.h` 를 쓴다. 같은 struct 가 세
빌드에서 같은 폭을 갖게 하는 장치다. 커널 코드에서 `uint8_t` 를 직접 쓰면 헤더
의존이 꼬인다.

### 4.2 명령 코드 (`:81~96`)

```c
enum proto_cmd {
    CMD_PING        = 0x01,   /* R->S */
    CMD_PONG        = 0x02,   /* S->R */
    CMD_HOME        = 0x10,   /* R->S */
    CMD_SCAN_START  = 0x11,   /* R->S : proto_scan_start */
    CMD_SCAN_STOP   = 0x12,   /* R->S */
    CMD_DISARM      = 0x13,   /* R->S */
    CMD_HOMED       = 0x20,   /* S->R : proto_homed */
    CMD_STATUS      = 0x21,   /* S->R : proto_status */
    CMD_SCAN_DATA   = 0x22,   /* S->R : proto_scan_point */
    CMD_SCAN_DONE   = 0x23,   /* S->R : proto_scan_done */
    CMD_ERROR       = 0x2F,   /* S->R : proto_err */
};
```

번호 대역이 의미를 갖는다 — `0x0x` 링크 감시, `0x1x` RPi→STM32 제어, `0x2x`
STM32→RPi 통지.

| CMD | 펌웨어 진입점 | 드라이버 처리 |
|---|---|---|
| `PING` | `CMD_PONG` 즉시 송신 | — |
| `HOME` | `scan_home()` | `STF_HOMED` 선 클리어 후 송신 |
| `SCAN_START` | `scan_start(&ss)` | FIFO 비우고 `STF_SCANNING` set |
| `SCAN_STOP` | `scan_stop()` | 송신만 |
| `DISARM` | `scan_abort()` → `motor_disarm()` | 송신만 |
| `PONG` | — | `pong_seq++` |
| `HOMED` | — | provenance 캐시 + notify |
| `STATUS` | — | 각도·flags·진단 캐시 |
| `SCAN_DATA` | — | kfifo push |
| `SCAN_DONE` | — | `last_point_count`, `STF_SCANNING` clear |
| `ERROR` | — | `last_err` + `last_err_axis` |

명령 ioctl 은 fire-and-forget 이다. ioctl 반환 0 은 UART 로 프레임을 넘겼다는 뜻이지
STM32 가 작업을 끝냈다는 뜻이 아니다.

`CMD_DISARM` 은 `scan_stop` 이 아니라 `scan_abort` 를 부른다. 전자는 `SC_DONE` 을
거쳐 가짜 `SCAN_DONE` 을 보내고 파킹 목표를 다시 만든다. 현재 `motor.c`의 `s_armed`가
전류 차단 뒤 펄스와 스텝카운트 갱신을 막으므로 실제 유령 이동은 생기지 않지만,
완료 통지와 파킹 상태 전이 자체가 비상정지 의미에 맞지 않는다.

### 4.3 오류 코드와 축 (`:98~138`)

```c
enum proto_err_code {
    ERR_NONE = 0,
    ERR_BAD_CRC = 1, ERR_BAD_LEN = 2, ERR_NOT_HOMED = 3,
    ERR_OUT_OF_RANGE = 4, ERR_STALL = 5, ERR_LIDAR = 6,
    ERR_BUSY = 7,          /* v6 */
    ERR_ENCODER = 8,       /* v6 */
};

enum proto_err_axis {      /* v6 — 비트 플래그 */
    ERR_AXIS_NONE = 0,
    ERR_AXIS_PAN  = 1u << 0,
    ERR_AXIS_TILT = 1u << 1,
    ERR_AXIS_BOTH = (1u << 0) | (1u << 1),
};
```

코드는 "무엇이", axis 는 "어디서"를 말한다. axis 를 비트 플래그로 잡은 것은 축별
판정을 OR 로 합치기 위해서다.

```c
/* scan.c 의 실제 사용 — 양축 동시 실패를 보존한다 */
const uint8_t ax = (uint8_t)((ok_p ? 0u : (uint8_t)ERR_AXIS_PAN)
                           | (ok_t ? 0u : (uint8_t)ERR_AXIS_TILT));
scan_report_err((uint8_t)ERR_ENCODER, ax);
```

값을 바꾸면 이 관용구가 깨진다. 삼항 연산자로 하나만 고르면 양축 동시 실패 시 한쪽
비트가 누락된다.

v6 이전에는 축을 표시하려고 `SCAN_HOME_AXIS_PROBE` 라는 브링업 장치가 다른 오류코드를
빌려 썼다(4=팬, 6=틸트). 빌린 코드는 그 코드가 실제로 발생했을 때 오독을 부르므로
v6 에서 정식 필드로 올리고 장치를 제거했다.

`ERR_BUSY` 는 v6 에서 `CMD_STATUS` 주기 송신을 켠 뒤 드러난 문제를 잡았다. 데몬은
`TURRET_HOME` ioctl 이 `STF_HOMED` 를 내리므로 이후 `homed==1` 은 이번 HOME 의
응답이라는 불변식에 기대는데, 주기 송신이 이전 홈의 값을 되살려 홈 완료 전에
`SCAN_START` 가 나갔다.

`TURRET_HOME`에서 플래그를 내리는 경로는 Protocol v6 이전 RPi `4bb5708`에 이미
들어갔다. 따라서 v6 STATUS가 이 플래그를 내린 최초 수단은 아니다. 위 사건은 소스
주석과 커밋 설명에는 남아 있으나 당시 원본 UART 프레임 로그는 보존돼 있지 않다.

### 4.4 각도 규약 (`:140~186`)

```c
#define ANGLE_SCALE  10
#define PAN_MIN      0
#define PAN_MAX      3599
#define TILT_MIN     (-900)
#define TILT_MAX     900
```

- 단위 0.1도. `1234` = 123.4°
- `pan` 0~3599 (2축 스캔에서는 0~1800 만 사용)
- `tilt` −900~+900, 영점 = 바닥(nadir)

프로토콜이 나르는 각도는 전부 기구각이다. 계약 좌표계 변환은 데몬의
`mech_to_contract()` 하나가 소유한다.

```
기구 틸트 m <= 0 :  계약 pan = p        tilt = -900 - m     (벽 A 쪽 반)
기구 틸트 m >  0 :  계약 pan = p + 1800  tilt = -900 + m     (벽 B 쪽 반)
```

한 줄이 방위 p 와 p+180 을 함께 훑으므로 기구 팬이 180°만 돌아도 계약 방위 360°가
채워진다. 케이블이 감기지 않고 되감기가 불필요하다.

각도원은 스윕 중 스텝카운트다. 엔코더를 샘플마다 끼우지 않는 이유는 I2C 판독 완료
시각과 라이다 샘플 시각이 달라 동기 오차가 커지기 때문이다.

> **PRT-04 — 헤더 주석 두 곳이 구현과 다르다**
> §4는 틸트 끝점에서 스텝카운터를 재영점한다고 적지만 현재 `scan.c`는 감시만 한다.
> `proto_status.cur_tilt_ddeg`도 엔코더 각도라고 적혀 있으나 실제 STATUS 조립은 팬과
> 틸트 모두 `motor_get_pulse()` 기반이다. 구현 기준으로 주석을 정정해야 한다.

### 4.5 payload 구조체 (`:192~276`)

| 구조체 | 크기 | 프레임 | UART 점유 |
|---|---:|---:|---|
| `proto_scan_start` | 10 B | 15 B | — |
| `proto_scan_point` | 18 B | 23 B | 100Hz 기준 약 20% |
| `proto_homed` | 8 B | 13 B | — |
| `proto_scan_done` | 4 B | 9 B | — |
| `proto_status` | 15 B | 20 B | 1Hz |
| `proto_err` | 2 B | 7 B | — |

#### `proto_scan_point`

```c
struct proto_scan_point {
    proto_s16 pan_ddeg;          /* 기구 방위 (0.1도)                */
    proto_s16 tilt_ddeg;         /* 기구 고각 (0.1도, 부호)          */
    proto_u16 d_mm;              /* 거리 (mm)                        */
    proto_u16 signal_strength;   /* F2P 원본 신호세기 (정규화 안 함) */
    proto_u32 device_time_ms;    /* F2P system time 원본             */
    proto_u32 stm_ts_ms;         /* 래치 시각 (STM32 HAL tick)       */
    proto_u8  dis_status;        /* F2P 원본 거리상태                */
    proto_u8  range_precision;   /* F2P 원본 (F2P 는 0xFF 미지원)    */
} PROTO_PACKED;
```

펌웨어는 거르지 않는다. 판정 기준이 바뀌면 이미 수집한 스캔을 다시 해석할 수 있어야
하는데, 펌웨어가 미리 버리면 복구되지 않는다. 현재 데몬도 `dis_status`로 점을 제외하지
않고 범위 안에서 채워진 셀은 모두 `valid:true`로 쓴다. 원본 보존은 상위 필터가 가능한
경계라는 뜻이지 현재 데몬이 센서 유효성을 판정한다는 뜻은 아니다.

- `device_time_ms`(라이다 시계)와 `stm_ts_ms`(STM32 HAL tick)는 서로 다른 clock
  domain 이다. 산출물 JSON 의 `timestamp_ns` 는 데몬의 단조시계 수신 시각이다
- `signal_strength` 는 calibrated reflectivity 가 아니므로 재질 판별에 단독 사용
  금지다

#### `proto_homed`

```c
struct proto_homed {
    proto_u16 pan_encoder_raw;   /* MT6701 14비트 원본 (0~16383) */
    proto_u16 tilt_encoder_raw;
    proto_s16 pan_ddeg;          /* 영점 적용 후 절대각          */
    proto_s16 tilt_ddeg;
} PROTO_PACKED;
```

raw 를 함께 올리는 것이 이 구조체의 존재 이유다. `*_ddeg` 는 조립 시 실측한 영점
상수를 적용한 결과이므로, 영점이 틀린 것으로 밝혀지면 raw 로부터 각도를 재계산할 수
있어야 한다. 재스캔 없이 복구 가능한 유일한 경로이며, 데몬은 이 값을 산출물 헤더의
provenance 로 남긴다.

#### `proto_status` (15B)

```c
struct proto_status {
    proto_s16 cur_pan_ddeg;    /* 현재 방위 (스텝카운트)    */
    proto_s16 cur_tilt_ddeg;   /* 현재 고각                 */
    proto_u8  flags;           /* bit0=homed, bit1=scanning */
    /* --- v6 진단 카운터 (누적, 부팅 이후) --- */
    proto_u16 tx_fail;
    proto_u16 rx_ovf;
    proto_u16 enc_retry;
    proto_u16 lidar_drop;
    proto_u16 reject_busy;
} PROTO_PACKED;
```

v5 까지 이 구조체는 정의만 있고 송신되지 않았다. RPi는 `4bb5708`부터 HOME 요청 시
`STF_HOMED`를 내렸지만, STM32의 현재 상태를 주기적으로 드라이버 캐시에 반영하는
경로는 없었다. 진단 카운터도 펌웨어 내부에서 증가할 뿐 외부에서 읽을 수 없었다.

| 카운터 | 0 이 아니면 |
|---|---|
| `tx_fail` | STM32 `HAL_UART_Transmit` 실패·타임아웃. 이 값만으로 링크 품질이나 RPi 정체를 판정할 수 없음 |
| `rx_ovf` | 하행 입력이 255B 링버퍼 소비를 앞지름. 입력량과 메인루프 지연을 함께 봐야 함 |
| `enc_retry` | MT6701 I2C 재시도. 간헐 고장 지표 |
| `lidar_drop` | 라이다 샘플 큐 넘침 = 메인루프 지연 |
| `reject_busy` | 진행 중이라 거절한 `SCAN_START` |

카운터는 u16 이고 `sat16()` 으로 65535 에서 포화한다. 잘라내면 65536번째에 0 으로
보여 정상처럼 읽힌다.

`status_seen=0` 이면 카운터 0 은 정상이 아니라 unknown 이다. 드라이버 ABI 와 MQTT
`diag.valid` 가 이 구분을 보존한다.

### 4.6 CRC (`:348`)

```c
static inline proto_u16 proto_crc16(const proto_u8 *data, proto_u16 len)
{
    proto_u16 crc = 0xFFFFu;
    for (proto_u16 i = 0u; i < len; i++) {
        crc ^= (proto_u16)((proto_u16)data[i] << 8);
        for (proto_u8 b = 0u; b < 8u; b++) {
            if ((crc & 0x8000u) != 0u) { crc = (proto_u16)((crc << 1) ^ 0x1021u); }
            else                       { crc = (proto_u16)(crc << 1); }
        }
    }
    return crc;
}
```

`static inline`이라 세 빌드가 같은 구현을 쓴다. 테이블 없이 비트 루프를 사용하므로
CRC lookup table 메모리는 들지 않는다. 최대 프레임은 29B이나 실행시간 측정값은
남아 있지 않으므로 비용이 무시할 수준이라고 단정하지 않는다.

수신측 복원 관용구 (STM32 `proto_dispatch`):

```c
uint32_t raw     = ((uint32_t)buf[flen - 1u] << 8) | (uint32_t)buf[flen - 2u];
uint16_t rx_crc  = (uint16_t)raw;                    /* MISRA 10.8 회피 */
uint16_t crc_len = (uint16_t)len + (uint16_t)PROTO_HEADER_LEN;
uint16_t calc    = proto_crc16(buf, crc_len);
```

`uint32_t` 로 합성한 뒤 좁히는 것은 합성식 캐스트(MISRA 10.8)를 피하기 위해서다.
정적분석 게이트를 통과하려면 이 형태를 유지한다.

### 4.7 컴파일타임 계약 검증 (`:370~393`)

```c
typedef char proto_assert_scan_point_18B
    [(sizeof(struct proto_scan_point) == 18u) ? 1 : -1];
typedef char proto_assert_status_15B
    [(sizeof(struct proto_status) == 15u) ? 1 : -1];
typedef char proto_assert_status_fits_payload
    [(sizeof(struct proto_status) <= PROTO_MAX_PAYLOAD) ? 1 : -1];
```

구조체 크기가 세 빌드 중 한 곳에서만 달라지면 프레임이 어긋난다. "배열 크기가 음수"
에러로 빌드를 실패시켜 막는다. 공통 assert 매크로에서 이름을 합성하지 않고 typedef를
직접 나열한 것은 MISRA 20.10의 `##` 연산자를 피하기 위해서다.

assert 는 8개다 — 구조체 6종 크기 + `scan_point`/`status`의 payload 상한 적합성.

### 4.8 ioctl ABI (`:282~346`)

`__KERNEL__` 또는 `PROTO_WANT_IOCTL` 일 때만 열린다. STM32 펌웨어 빌드에는 포함되지
않는다.

```c
#define TURRET_IOC_MAGIC   'T'
#define TURRET_HOME        _IO (TURRET_IOC_MAGIC, 1)
#define TURRET_SCAN_START  _IOW(TURRET_IOC_MAGIC, 2, struct proto_scan_start)
#define TURRET_SCAN_STOP   _IO (TURRET_IOC_MAGIC, 3)
#define TURRET_DISARM      _IO (TURRET_IOC_MAGIC, 4)
#define TURRET_GET_STATE   _IOR(TURRET_IOC_MAGIC, 5, struct turret_link_state)
#define TURRET_PING        _IO (TURRET_IOC_MAGIC, 6)
```

`struct turret_link_state` 는 점이 아니라 최신 캐시다.

| 그룹 | 필드 | 도입 |
|---|---|---|
| 링크 | `link_alive`, `pong_seq` | v4 |
| 상태 | `flags`, `cur_pan_ddeg`, `cur_tilt_ddeg` | v4 |
| 오류 | `last_err` | v4 |
| 홈 provenance | `home_*_encoder_raw`, `home_*_ddeg` | v5 |
| 오류 축 | `last_err_axis` | v6 |
| 진단 | 카운터 5종, `status_seen` | v6 |

`_IOR` 에 구조체 크기가 인코딩되므로 v5/v6 데몬-드라이버 불일치는 `-ENOTTY` 로
드러난다.

---

## 5. 인터페이스 요약

### 5.1 `point_count` 의 의미

`proto_scan_done.point_count` 는 `HAL_UART_Transmit` 이 성공을 반환한 `SCAN_DATA`
프레임 수다. 드라이버가 받아들인 수도, 데몬이 저장한 수도 아니다.

| 단계 | 세는 것 | 현재 노출 |
|---|---|---|
| 1 | STM32 송신 성공 | `proto_scan_done.point_count` |
| 2 | 드라이버 CRC/LEN 통과, FIFO drop | 없음 |
| 3 | 데몬 read, 격자 삽입, 병합, 범위 밖 | JSON `diagnostics` 일부 |
| 4 | JSON filled/valid, PCD finite | JSON `scan.valid_count` |

1번 값이 드라이버에서 유저 공간으로 이어지지 않는다. 드라이버가
`last_point_count`로 저장하지만 `TURRET_GET_STATE` ABI에 포함하지 않아 데몬의
`result.stm_reported`가 항상 0이다(PRT-01).

### 5.2 오류 정의와 실제 동작

| 오류 | 헤더 정의 | STM32 실제 | 드라이버 실제 |
|---|---|---|---|
| bad CRC | `ERR_BAD_CRC` | 정의만 사용하고 DBG 후 폐기 | 로그 후 폐기, 누적 카운터 없음 |
| bad LEN | `ERR_BAD_LEN` | 정의만 사용하고 파서 폐기 또는 명령 무시 | `HOMED`·`STATUS`·`ERROR` 일부만 경고 |
| not homed | `ERR_NOT_HOMED` | ERROR 전송 | 캐시 → 데몬 |
| out of range | `ERR_OUT_OF_RANGE` | ERROR 전송 | 캐시 → 데몬 |
| stall | `ERR_STALL` + axis | ERROR 전송 | 캐시 → 데몬 |
| busy | `ERR_BUSY` | ERROR 전송 | 캐시 → 데몬 |
| encoder | `ERR_ENCODER` + axis | ERROR 전송 | 캐시 → 데몬 |
| lidar | `ERR_LIDAR` | 현재 발화 경로 없음 | 수신 처리만 가능 |
| unknown CMD | 정의 없음 | DBG 후 무시 | info 후 무시 |

enum 정의와 실제 dispatch 동작을 구분해야 한다.

---

## 6. 참고

- 소스: `RPi/shared/protocol.h` (canonical), `STM32/shared/protocol.h`
- CI: `STM32/.github/workflows/protocol-sync-check.yml`
- 소비자: `RPi/driver/turret_driver.c`, `STM32/App/uart_rpi/uart_rpi.c`
- 좌표 변환: `RPi/daemon/core/scan_output.c`
