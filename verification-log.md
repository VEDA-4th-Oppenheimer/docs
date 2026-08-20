# Confluence ↔ 코드 대조 기록

Confluence 문서를 코드와 맞춰본 결과입니다. **여기 없는 페이지는 대조하지 않은 것**이며,
"안 봤다"와 "봤는데 맞다"를 구분하기 위해 남깁니다.

기준: `STM32 main/003e483` · `RPi origin/main 7b347a4` · `QT main/5888153`

## 대조 완료

| Confluence 페이지 | 결과 |
|---|---|
| [MQTT 토픽 계약 v1.4](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) | ✅ 현행 (2026-08-19 대조 명시) |
| [스캔 산출물 포맷](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38240259) | ✅ `scan_output.c/h`와 일치 |
| [02-4. 기구각→계약각·격자·셀 병합](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057196) | ✅ 일치 — 변환식·84mm·허용치 공식·full-circle 열·seam 모두 확인 |
| [03-2. MQTT module](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696707) | ✅ 일치 — v1.4의 코드 7·8, notice 105·106만 미반영 |
| [01-2. UART protocol **v5**](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42860546) | ⚠️ **v5 기준, v6와 5곳 차이** → [상세](interfaces/stm32-rpi-uart.md) |
| [2축 스캐너 디바이스 아키텍처](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/29032450) | ⚠️ **2026-07-31 기준, 8곳 차이** → [상세](overview/architecture.md) |

## 대조 안 함

위 6개를 뺀 **98페이지.** 특히 [RPi 코드 기반 완전 개발 보고서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844741)
01~06 시리즈 중 위 둘을 뺀 22페이지는 제목과 계층만 확인했습니다.

01~06 시리즈는 전부 `develop 4372771` / 2026-08-19 기준으로 작성됐고, 01-2가
v5 기준인 것으로 보아 **시리즈 전체가 v6 머지 직전 스냅샷**일 가능성이 있습니다.
읽을 때 감안하세요.

## 코드에서 확인한 미결 결함

문서가 지적한 것이 실제로 남아 있는지 확인한 항목입니다.

**scan 파라미터 narrowing — `origin/main`에 그대로 있습니다.**
`daemon/modules/mqtt/mqtt_module.c` 451~455행이 JSON `int`를
`int16_t`/`uint16_t`로 **먼저 캐스팅**하고, 범위 검사(`scan_request_valid`)는
그 뒤에 좁혀진 값을 봅니다. 그래서 `step_ddeg: 65546`이 `10`으로 wrap되어
정상적인 1.0°처럼 통과합니다. 넓은 타입에서 검사한 뒤 캐스팅해야 합니다.
→ [01-2 §5.1](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42860546) · [03-2 §6](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696707)
