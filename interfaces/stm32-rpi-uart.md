# STM32 ↔ RPI UART 프로토콜

**원본: [01-2. UART protocol·ABI·CRC·ioctl 계약 상세](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42860546)** (Confluence)

**값의 진실 소스는 `shared/protocol.h`** 입니다. CMD 번호와 구조체 레이아웃을
문서에 복사하지 마세요 — 헤더 사본이 하나 더 늘고, CI drift-check는 코드 사본만 봅니다.

| 사본 | 경로 | 역할 |
|---|---|---|
| RPi | `RPi/shared/protocol.h` | **마스터** — 프로토콜 변경은 여기서 먼저 |
| STM32 | `STM32/shared/protocol.h` | 다운스트림 — CI drift-check가 마스터와 대조 |

두 사본은 일치합니다 (`PROTO_VERSION 6`, md5 동일 확인 2026-08-20).

> 💡 **로컬에서 v5로 보인다면 브랜치를 확인하세요.** 오래된 feature 브랜치에는 v5가
> 남아 있습니다. 기준은 `RPi origin/main`입니다.

## 프레임

```
+-------+-------+-------+-----------------+---------+
|  SOF  |  CMD  |  LEN  |     PAYLOAD     |  CRC16  |
| 0xAA  |  1B   |  1B   |   0..24 B       |   2B    |
+-------+-------+-------+-----------------+---------+
        |<--------- CRC 계산 범위 (SOF~PAYLOAD) --->|
```

CRC-16/CCITT-FALSE (`poly=0x1021`, `init=0xFFFF`). `PROTO_VERSION`은 와이어로
보내지 않습니다 — 버전 불일치는 드라이버의 payload 길이 불일치 경고로 잡습니다.

## 새 명령을 추가한다면

번호 대역이 이미 정해져 있습니다. `enum proto_cmd`에 추가하고 사본을 동기화하세요.

| 대역 | 방향 |
|---|---|
| `0x01`~`0x02` | 생존 확인 (PING/PONG) |
| `0x10`~`0x1F` | RPi → STM32 (명령) |
| `0x20`~`0x2F` | STM32 → RPi (보고) |

프로토콜 변경은 비용이 고정으로 듭니다 — 사본 동기화 → push 순서(RPi 먼저 → STM32)
→ 드라이버·데몬·Qt 반영. **여러 변경을 묶어서 한 번에 하세요.**

## 관련

- [01. RPi 시스템 아키텍처·저장소 구조](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844762)
- [04-2. turret_driver — serdev RX parser·kfifo·read/poll/ioctl](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42467352)
- [components/stm32/sensors/lidar.md](../components/stm32/sensors/lidar.md) — 스캔 점 상행 계약
