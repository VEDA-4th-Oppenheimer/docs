# docs

A.D.T.S — VEDA 4th Oppenheimer 팀 문서 저장소입니다.

> **코드는 두지 않습니다.** `.md`만 커밋합니다.
> 값(CMD 번호, 구조체 레이아웃, 핀맵)은 코드가 진실 소스이고,
> 문서는 **왜 그렇게 했는지와 어떻게 쓰는지**를 담습니다.

## 인터페이스 — 두 컴포넌트가 함께 보는 문서

| 문서 | 내용 |
|---|---|
| [STM32 ↔ RPI UART 프로토콜](interfaces/stm32-rpi-uart.md) | 프레임 구조, 명령 개요, 시퀀스, 에러 복구 |
| [Qt ↔ RPi 발급 서버 계약 (mTLS)](interfaces/qt-rpi-enroll-mtls.md) | 인증서 발급, 토큰이 보증하는 것, CA 재발급 |

## 컴포넌트

| 컴포넌트 | 문서 |
|---|---|
| [STM32](components/stm32/) | [펌웨어 개요](components/stm32/overview.md) · [모터 램프](components/stm32/motor-ramp.md) · [센서](components/stm32/sensors/) |
| [Raspberry Pi](components/rpi/) | [드라이버·데몬 개요](components/rpi/overview.md) · [adts-web](components/rpi/web.md) |
| [Qt](components/qt/) | [관제 콘솔 개요](components/qt/overview.md) · [빌드·배포](components/qt/build-and-deploy.md) |
| [Yocto](components/yocto/) | *작성 전* |
| [OpenSDK](components/opensdk/) | *작성 전* |
| [자동 캘리브레이션](components/calibration/) | *작성 전* |

## 가이드

| 문서 | 내용 |
|---|---|
| [rpi-kernel-build.md](guides/rpi-kernel-build.md) | 커널 버전 고정 & 빌드 환경 (`/dev/turret`) |
| [rpi-docker-build-env.md](guides/rpi-docker-build-env.md) | RPi 빌드환경 Docker — 맥 M4 + CLion |
| [stm32-static-analysis.md](guides/stm32-static-analysis.md) | 펌웨어 정적분석 |

## 그 외

- [시스템 아키텍처](overview/architecture.md) · [요구사항](overview/requirements.md) — *작성 전*
- [decisions/](decisions/) — 기술 결정 기록(ADR)
- [meetings/](meetings/) — 회의록

---

문서를 추가하기 전에 [작성 규칙](CONTRIBUTING.md)을 읽어주세요.
