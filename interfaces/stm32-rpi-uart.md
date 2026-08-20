# STM32 ↔ RPI UART 프로토콜

## 단일 진실 소스는 이 문서가 아니라 `shared/protocol.h` 입니다

이 문서에 CMD 번호와 구조체 레이아웃을 **다시 적지 마세요.** 적는 순간 헤더 사본이
하나 더 늘어나고, CI의 drift-check는 코드 사본만 보기 때문에 문서가 어긋나도 아무도
모릅니다. 값이 필요하면 헤더를 여세요.

| 사본 | 경로 |
|---|---|
| STM32 펌웨어 | `STM32/shared/protocol.h` |
| RPi (드라이버·데몬) | `RPi/shared/protocol.h` |

> ⚠️ **현재 두 사본이 어긋나 있습니다.** STM32 = `PROTO_VERSION 6`, RPi = `PROTO_VERSION 5`
> (133줄 차이). v6에서 `proto_err.axis` 추가(1B→2B), `ERR_BUSY`/`ERR_ENCODER` 신설,
> `proto_status` 5B→15B 확장이 들어갔는데 RPi 쪽에 반영되지 않았습니다.
> 헤더 주석의 "수정 시 3자 모두 재빌드하고 VERSION을 올린다" 규칙이 지켜지지 않은 상태입니다.

## 이 문서가 담는 것

헤더에 **못 담는 것**만 담습니다.

- 프레임 주고받는 순서 (홈 → 스캔 시작 → 점 스트림 → 완료)
- 에러가 났을 때 양쪽이 각각 어떻게 복구하는지
- 왜 그렇게 설계했는지 (헤더 주석에 있는 내용은 링크로)
- 브링업할 때 "통신이 안 된다"를 원인별로 가르는 법

## 프레임 구조

```
+-------+-------+-------+-----------------+---------+
|  SOF  |  CMD  |  LEN  |     PAYLOAD     |  CRC16  |
| 0xAA  |  1B   |  1B   |   0..24 B       |   2B    |
+-------+-------+-------+-----------------+---------+
        |<--------- CRC 계산 범위 (SOF~PAYLOAD) --->|
```

- `PROTO_HEADER_LEN` 3 · `PROTO_MAX_PAYLOAD` 24 · `PROTO_CRC_LEN` 2
- CRC-16/CCITT-FALSE (`poly=0x1021`, `init=0xFFFF`) — 세 구현이 같은 함수를 공유합니다.
- `PROTO_VERSION`은 **와이어로 보내지 않습니다.** 버전 불일치는 드라이버의
  payload 길이 불일치 경고로 잡습니다.

## 명령 개요

번호 대역이 이미 정해져 있습니다 — **새 명령은 방향에 맞는 대역에서 고르세요.**

| 대역 | 방향 |
|---|---|
| `0x01`~`0x02` | 생존 확인 (양방향) |
| `0x10`~`0x1F` | RPi → STM32 (명령) |
| `0x20`~`0x2F` | STM32 → RPi (보고) |

| CMD | 이름 | 방향 | PAYLOAD |
|---|---|---|---|
| 0x01 | `CMD_PING` | R→S | 없음 (100ms 주기) |
| 0x02 | `CMD_PONG` | S→R | 없음 |
| 0x10 | `CMD_HOME` | R→S | 없음 |
| 0x11 | `CMD_SCAN_START` | R→S | `proto_scan_start` (10B) |
| 0x12 | `CMD_SCAN_STOP` | R→S | 없음 |
| 0x13 | `CMD_DISARM` | R→S | 없음 (즉시 안전정지) |
| 0x20 | `CMD_HOMED` | S→R | `proto_homed` (8B) |
| 0x21 | `CMD_STATUS` | S→R | `proto_status` (15B, 1초 주기) |
| 0x22 | `CMD_SCAN_DATA` | S→R | `proto_scan_point` (18B) |
| 0x23 | `CMD_SCAN_DONE` | S→R | `proto_scan_done` (4B) |
| 0x2F | `CMD_ERROR` | S→R | `proto_err` (2B) |

> 위 표는 **`PROTO_VERSION 6` 기준 스냅샷**입니다. 헤더와 다르면 헤더가 맞습니다.
> 필드 단위·범위·의미는 `protocol.h`의 구조체 정의와 주석을 보세요.

## 스캔 점 상행 계약

`CMD_SCAN_DATA`에 무엇이 실리고 무엇이 실리지 않는지, 왜 스윕 구간의 점만
올리는지는 라이다 문서에 정리돼 있습니다.

→ [components/stm32/sensors/lidar.md § 5. 상행 계약](../components/stm32/sensors/lidar.md)

주의: `signal_strength`는 F2P 원본 그대로이고 calibrated reflectivity가 아닙니다.
**재질 판별에 단독으로 쓰면 안 됩니다.**

## 프레임 시퀀스

<!-- 실제 흐름으로 채워주세요 -->

```
RPi                          STM32
 |---- CMD_HOME ------------>|
 |<--- CMD_HOMED ------------|
 |---- CMD_SCAN_START ------>|
 |<--- CMD_SCAN_DATA --------|  (× N)
 |<--- CMD_SCAN_DONE --------|
```

## 에러 복구

| 상황 | STM32 동작 | RPi 동작 |
|---|---|---|
| CRC 불일치 (`ERR_BAD_CRC`) | | |
| LEN 초과 (`ERR_BAD_LEN`) | | |
| 동기 깨짐 | SOF 재탐색 | |
| 타임아웃 | | |

UART 에러 복구는 [lidar.md § 6](../components/stm32/sensors/lidar.md)도 참고.

## 프로토콜을 바꿀 때

헤더 주석에 적힌 대로 비용이 고정으로 듭니다 — 사본 동기화 → push 순서
(RPi 먼저 → STM32) → 드라이버·데몬·Qt 반영. **여러 변경을 묶어서 한 번에 하세요.**

1. `protocol.h` 수정 + `PROTO_VERSION` 증가
2. 모든 사본 동기화 (현재 STM32/RPi 2곳)
3. 이 문서의 명령 개요 표와 아래 이력 갱신
4. 양쪽 재빌드·재플래시

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|---|---|---|
| v6 | 2026-08-19 | `proto_err.axis` 추가, `ERR_BUSY`/`ERR_ENCODER` 신설, `proto_status` 15B 확장 및 주기 송신 |
| v5 | | 스캔 점에 라이다 원시 품질 필드 추가 (6B → 18B) |
| v4 | | 안티드론 조준(SET_TARGET/ALIGNED/MODE/DISTANCE) 제거 |
