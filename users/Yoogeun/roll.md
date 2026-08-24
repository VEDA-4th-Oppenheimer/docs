# 강유근 — 담당 범위와 작성 문서

## 담당 범위

| 파트 | 맡은 것 | 저장소 위치 |
|---|---|---|
| STM32 펌웨어 | 17HS4401 & DRV8825 2축 스텝모터 가감속 제어, S-Curve Q8 램프 및 750 PPS 최적화 | `STM32` — `App/motor/` |
| STM32 펌웨어 | MT6701 14비트 I2C 각도 엔코더 드라이버, 220Ω SI 댐핑 및 3단계 버스 복구 | `STM32` — `App/hallEffectSensor/` |
| STM32 펌웨어 | 2축 Grid Scan 시퀀서 원 구현, Serpentine 40ms 정착 및 `SC_PARK` 안전 제어 | `STM32` — `App/scan/` |
| RPi 드라이버 | LED, SWITCH, BUZZER 커널 드라이버 (`/dev/led_sw`) | `RPi` — `driver/led_sw_driver.c`, `driver/overlays/` |
| H/W & 기구 | 2축 Pan-Tilt 3D 기구 설계(SolidWorks V2.0), 센서 물리 오프셋 및 KiCad 회로도 | `SOLIDWORKS/PART/`, `docs/hardware/` |
| 품질 & CI | 임베디드 2-Track 정적 분석 (MISRA C:2012 Rule 15.5 리팩토링, Cppcheck CI) | `STM32` — `tools/`, `.github/workflows/` |

## 작성 문서

| 문서 | 다루는 것 |
|---|---|
| [2축 스텝모터 구동 및 가감속](../../components/stm32/motor.md) | S-Curve Q8 저크 제한 가감속, 750 PPS 골든레이시오 최적화(1.07 샘플/격자), V_REF 전류 튜닝, 소프트랜딩 착지 (송영빈과 공동) |
| [14비트 엔코더 I2C 드라이버](../../components/stm32/encoder.md) | MT6701 비접촉 절대 영점, 220Ω 직렬 댐핑 저항 SI 개선, 3단계 I2C 버스 복구, Monitor-Only 탈조 감시 |
| [2축 Grid Scan 시퀀서](../../components/stm32/scan.md) | 9단계 FSM 시퀀서, Serpentine 틸트 스윕, 40ms 정착 최적화, `SC_PARK` 500ms 후 자동 전원 차단 (이현우와 공동) |
| [LED, SWITCH, BUZZER 커널 드라이버](../../components/rpi/driver/led-sw.md) | BCM2835 Hardware PWM0 부저, 50ms 폴링 디바운스, kfifo 비동기 이벤트 스트리밍, DT Overlay |
| [임베디드 2-Track 정적 분석 CI](../../guides/static-analysis-ci.md) | Cppcheck & MISRA C:2012, Rule 15.5 단일 리턴 리팩토링, 오탐 억제 사유 관리, GitHub Actions CI |
