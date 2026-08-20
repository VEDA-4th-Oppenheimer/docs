# docs

A.D.T.S — VEDA 4th Oppenheimer 팀 문서 저장소입니다.

> ## 📍 팀 문서의 본진은 Confluence입니다
>
> **[→ Confluence 지도 (VPT 스페이스 104페이지)](confluence-map.md)**
>
> [→ 코드 대조 기록](verification-log.md) — 어느 문서를 확인했고 어디가 어긋나는지
>
> 이 저장소는 **그리로 가는 지도**이고, Confluence에 없는 것만 여기 둡니다.
> 문서를 찾고 있다면 지도부터 보세요.

**코드는 두지 않습니다.** `.md`만 커밋합니다.
값(CMD 번호, 구조체 레이아웃, 핀맵)은 코드가 진실 소스이고,
문서는 **왜 그렇게 했는지와 어떻게 쓰는지**를 담습니다.

## 인터페이스 — 두 컴포넌트가 함께 보는 문서

| 계약 | 경계 | 원본 |
|---|---|---|
| [MQTT 토픽 계약 v1.4](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) | Qt ↔ RPi 데몬 | Confluence |
| [스캔 산출물 좌표계·포맷](interfaces/scan-output-format.md) | 데몬 → Qt·캘리브 | Confluence |
| [STM32 ↔ RPI UART 프로토콜](interfaces/stm32-rpi-uart.md) | STM32 ↔ RPi | `shared/protocol.h` |
| [Qt ↔ RPi 발급 서버 (mTLS)](interfaces/qt-rpi-enroll-mtls.md) | 인증서 전반 | Confluence |

## 컴포넌트

| 컴포넌트 | 문서 |
|---|---|
| [STM32](components/stm32/) | [펌웨어 개요](components/stm32/overview.md) · [모터 램프](components/stm32/motor-ramp.md) · [센서](components/stm32/sensors/) |
| [Raspberry Pi](components/rpi/) | [드라이버·데몬 개요](components/rpi/overview.md) · [데몬 FSM](components/rpi/daemon-fsm.md) · [adts-web](components/rpi/web.md) |
| [Qt](components/qt/) | [관제 콘솔 개요](components/qt/overview.md) · [빌드·배포](components/qt/build-and-deploy.md) |
| Yocto · OpenSDK · 캘리브레이션 | [Confluence 지도](confluence-map.md) 참고 |

## 가이드

| 문서 | 내용 |
|---|---|
| [rpi-kernel-build.md](guides/rpi-kernel-build.md) | 커널 버전 고정 & 빌드 환경 (`/dev/turret`) |
| [rpi-docker-build-env.md](guides/rpi-docker-build-env.md) | RPi 빌드환경 Docker — 맥 M4 + CLion |
| [stm32-static-analysis.md](guides/stm32-static-analysis.md) | 펌웨어 정적분석 |

## 그 외

- [시스템 아키텍처](overview/architecture.md) — 구성도·경계·데이터 흐름 *(초안, Confluence 아키텍처 문서와 중복 주의)*
- [요구사항](overview/requirements.md) — *Confluence의 [SRS](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/22052873) 참고*
- [decisions/](decisions/) — 기술 결정 기록(ADR)
- [meetings/](meetings/) — *[Confluence 회의록](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/425985) 참고*

---

문서를 추가하기 전에 [작성 규칙](CONTRIBUTING.md)을 읽어주세요.
특히 **0번(코드에 있는 값을 베끼지 않는다)** 과, Confluence에 이미 있는 문서를
복사하지 않는다는 원칙을 지켜주세요.
