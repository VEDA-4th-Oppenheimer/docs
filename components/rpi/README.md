# Raspberry Pi

A.D.T.S — 커널 드라이버(`/dev/turret`)와 통합 데몬, 그리고 폰 브라우저용 관제 서비스.

- **담당**:
- **코드**: `RPi/`

## 문서

| 문서 | 내용 |
|---|---|
| [overview.md](overview.md) | 드라이버 · 통합 데몬 전체 설명 |
| [daemon-fsm.md](daemon-fsm.md) | 스캔 상태머신 — 상태·전이·타임아웃·degraded 모드 |
| [web.md](web.md) | `adts-web` — 폰 브라우저용 관제 서비스 |

> 문서가 늘어나면 `driver-*.md` / `daemon-*.md` 로 접두어를 붙이고,
> 각각 4~5개가 되면 그때 폴더로 나누세요.

## 관련 인터페이스

- [STM32 ↔ RPI UART 프로토콜](../../interfaces/stm32-rpi-uart.md)
- [Qt ↔ RPi 발급 서버 계약 (mTLS)](../../interfaces/qt-rpi-enroll-mtls.md)
- [스캔 산출물 좌표계 · 포맷](../../interfaces/scan-output-format.md) — 데몬이 쓰는 쪽

> 통신 규격의 진실 소스는 `shared/protocol.h`입니다. **여기에 값을 복사하지 마세요.**

## 관련 가이드

- [커널 버전 고정 & 빌드 환경](../../guides/rpi-kernel-build.md)
- [Docker 빌드환경 (맥 M4 + CLion)](../../guides/rpi-docker-build-env.md)
