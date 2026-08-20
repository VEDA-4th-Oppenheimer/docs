# STM32

A.D.T.S 펌웨어 (`adts`) — 2축 스텝 구동, 라이다 스캔, RPi와의 UART 링크.

- **담당**:
- **코드**: `STM32/`

## 문서

| 문서 | 내용 |
|---|---|
| [overview.md](overview.md) | 펌웨어 전체 구조와 빌드 |
| [motor-ramp.md](motor-ramp.md) | 속도 프로파일, 램프 산수, 타이머 시간축, ISR 연결 |
| [sensors/](sensors/) | 센서별 문서 (1인 1파일) — [IMU](sensors/imu.md) · [라이다](sensors/lidar.md) |

## 관련 인터페이스

- [STM32 ↔ RPI UART 프로토콜](../../interfaces/stm32-rpi-uart.md) — 프레임 구조와 명령 개요

> 통신 규격의 진실 소스는 `shared/protocol.h`입니다. **여기에 값을 복사하지 마세요.**

## 관련 가이드

- [정적분석](../../guides/stm32-static-analysis.md)
