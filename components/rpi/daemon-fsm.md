# 통합 데몬 상태머신

**원본: [02-2. 100ms tick·heartbeat·HOME·FSM 전이 상세](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42565636)** (Confluence)

UI 관점의 상태 매핑은 [MQTT 토픽 계약 §5](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383)에
상태 다이어그램과 버튼 활성 조건까지 정리돼 있습니다.

구현은 `RPi/daemon/core/main.c` — 전이 판정 `core_eval_state()`, 허용 여부 `core_transition()`.

## 한눈에

```
OFFLINE ──접속──▶ IDLE ──cmd/scan──▶ SCANNING ──완료/stop──▶ EXPORT
                   ▲                     │                      │
                   └─────cmd/rearm───────┴──▶ DISARM ◀──15초────┘
```

`IDLE` / `SCANNING` / `EXPORT` / `DISARM` 네 상태이고, `OFFLINE`은 LWT로 브로커가 대신 알립니다.

## 밖에서 안 보이는 것 두 가지

1. **스캔 요청이 오면 항상 홈을 다시 잡습니다.** `cmd/home`은 축이 실제로 움직이고
   최악 11초까지 걸립니다 — 완료 판정은 `state/daemon`의 `homed`로 해야 합니다.
2. **스캔이 끝나면 15초 뒤 자동으로 DISARM 됩니다. 정상 동작이고 오류가 발행되지 않습니다.**
   STM32가 되감기를 마칠 시간을 준 뒤 전류를 끊는 것입니다. 다시 스캔하려면 `cmd/rearm`이 필요합니다.
   (15초는 되감기 실측 전까지의 잠정치입니다.)

## 관련

- [02. adts_daemon 코어·FSM·스캔 산출물](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41877508)
- [스캔 산출물 좌표계·포맷](../../interfaces/scan-output-format.md)
