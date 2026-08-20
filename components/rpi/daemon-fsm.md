# 통합 데몬 상태머신

`adts_daemon` 코어(`RPi/daemon/core/main.c`)의 스캔 상태 전이입니다.
전이 판정은 `core_eval_state()`, 허용 여부는 `core_transition()`에 있습니다.

## 상태

```
        ┌──────────────────────────────────────────┐
        │                                          │ rearm
        ▼                                          │
   ┌─────────┐  scan 요청   ┌──────────┐        ┌────────┐
   │ ST_IDLE │─────────────▶│ST_SCANNING│       │ST_DISARM│
   └─────────┘  (홈 선행)    └──────────┘        └────────┘
        ▲                         │                  ▲
        │  파일 마감 후 즉시        │ SCAN_DONE        │  링크 끊김 / 오류 /
        │                         │ · stop           │  스캔 후 유예 종료
   ┌──────────┐                   ▼                  │
   │ST_EXPORT │◀──────────────────┘                  │
   └──────────┘───────────────────────────────────────┘
```

| 전이 | 허용 대상 |
|---|---|
| `ST_IDLE` → | `ST_SCANNING`, `ST_DISARM` |
| `ST_SCANNING` → | `ST_EXPORT`, `ST_IDLE`, `ST_DISARM` |
| `ST_EXPORT` → | `ST_IDLE`, `ST_DISARM` |
| `ST_DISARM` → | `ST_IDLE` (rearm 뿐) |

## 각 상태에서 일어나는 일

### ST_IDLE

- **스캔 요청이 오면 항상 홈을 다시 잡고** 나서 `ST_SCANNING`으로 갑니다.
  홈 대기 중에는 요청을 소비하지 않습니다 — 소비하면 홈이 선 뒤 스캔이 사라집니다.
- `cmd/home` 단독 홈도 같은 대기 로직을 쓰고, 끝나도 `ST_SCANNING`으로 넘어가지만 않습니다.
- 새 작업이 들어오면 예약된 자동 DISARM을 **취소**합니다. 조작자가 킷을 계속 쓰는데
  유예가 끝났다고 안전정지로 떨어지면, 다음 스캔이 갑자기 거절되고 이유도 화면에 안 나옵니다.

### ST_SCANNING

완료 판정은 `STF_SCANNING` 플래그 해제입니다 — 드라이버가 `SCAN_START` ioctl 시점에
세우고, STM의 `CMD_SCAN_DONE` 수신 시 내립니다.

> 과거에 이 플래그가 계속 0이라(STM이 `CMD_STATUS`를 주기 발행하지 않던 시절)
> 첫 배치 몇 점만 받고 완료로 오판해 `.pcd`가 4점짜리로 끊긴 적이 있습니다.
> 드라이버가 명령 시점에 세우도록 고쳐 해결했습니다.

**안전망 — 두 종류의 타임아웃.** `SCAN_DONE`을 놓쳐도 반드시 빠져나옵니다.

| 상황 | 상수 |
|---|---|
| 아직 한 점도 못 받음 | `SCAN_FIRST_POINT_TIMEOUT_MS` (길게) |
| 점이 오다가 끊김 | `SCAN_IDLE_TIMEOUT_MS` (짧게) |

점 개수는 **탈출 자격이 아니라 타임아웃 길이 선택에만** 씁니다. 그래서 어느 경우에도
`ST_EXPORT`로 나가 파일을 마감합니다 (0점이면 0점으로).

### ST_EXPORT

파일 마감은 전이 **진입 시**에 끝나고, 곧바로 `ST_IDLE`로 복귀합니다.
복귀 후 `POST_SCAN_DISARM_MS` 뒤에 자동 DISARM이 예약됩니다 — STM32가 자율 수행하는
되감기가 끝날 때까지 기다리는 유예입니다. 다시 스캔하려면 조작자가 `cmd/rearm`을 눌러야 합니다.

`--once` 모드는 되감기를 끊지 않도록 **DISARM 없이** 종료합니다.

### ST_DISARM

들어오는 경로가 셋입니다.

1. STM 링크 heartbeat 끊김 (`ST_DISARM`이 아닌 모든 상태에서)
2. `ST_SCANNING` 중 `last_err != ERR_NONE`
3. 스캔 후 되감기 유예 종료

나가는 경로는 `cmd/rearm` 하나뿐입니다.

## degraded 모드

`turret_fd < 0`(장치 없음)이어도 **상태는 똑같이 움직입니다.** 실제 `CMD_DISARM`
송신만 `core_transition()`이 막습니다. 홈은 "degraded — turret 없이 홈 생략"으로 넘어갑니다.

## 관련 문서

- [STM32 ↔ RPI UART 프로토콜](../../interfaces/stm32-rpi-uart.md)
- [스캔 산출물 좌표계 · 포맷](../../interfaces/scan-output-format.md)
