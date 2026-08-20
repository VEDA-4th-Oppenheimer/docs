# docs

A.D.T.S — VEDA 4th Oppenheimer 팀 문서 저장소입니다.

천장에 거치한 2축 Pan-Tilt 유닛이 1D 라이다를 회전시켜 실내를 훑고, 구면 격자 형태의
3D 포인트클라우드를 만듭니다. 이 포인트클라우드가 Edge AI CCTV의 2D 영상과 매칭되어
**마커리스 외부 캘리브레이션**의 입력이 됩니다.

각 문서는 **그 문서만 읽고도 이해되도록** 쓰여 있습니다. 필요한 배경은 문서 안에
들어 있으니, 관심 있는 것부터 바로 여시면 됩니다.

## 전체 구조

| 문서 | 내용 |
|---|---|
| [overview/architecture.md](overview/architecture.md) | 2축 스캐너 전체 동작 명세 — 핀맵, 부품 사양, 기구각/계약각, 격자 설계, 모터 제어, 라이다 각도 동기, 엔코더 운용, 계층 구조, 동작 시퀀스 |

## 인터페이스 — 여러 파트가 함께 지키는 계약

바꾸려면 양쪽 합의가 필요한 문서들입니다. 구현 전에 확인하세요.

| 문서 | 경계 |
|---|---|
| [interfaces/mqtt-topic-contract.md](interfaces/mqtt-topic-contract.md) | Qt 관제 ↔ RPi 데몬 — 토픽, 페이로드, 오류 코드, 상태머신, mTLS |
| [interfaces/scan-output-format.md](interfaces/scan-output-format.md) | 데몬 → Qt·캘리브레이션 — `.json`/`.pcd` 전 필드 레퍼런스 |
| [interfaces/stm32-rpi-uart.md](interfaces/stm32-rpi-uart.md) | STM32 ↔ RPi — 프레임, CRC, payload, ioctl ABI |
| [interfaces/qt-rpi-enroll-mtls.md](interfaces/qt-rpi-enroll-mtls.md) | 인증서 발급 서버 계약 |

## STM32 펌웨어

| 문서 | 내용 |
|---|---|
| [components/stm32/overview.md](components/stm32/overview.md) | 디렉토리 구조, 빌드·플래시, 정적분석, CODEOWNERS |
| [components/stm32/motor-ramp.md](components/stm32/motor-ramp.md) | 사다리꼴 속도 프로파일 — 램프 산수, 타이머 시간축, ISR 삽입점 |
| [components/stm32/sensors/lidar.md](components/stm32/sensors/lidar.md) | TOFSense-F2P 수신 드라이버 — 프레임 파싱, 각도 래치 |

## Raspberry Pi

| 문서 | 내용 |
|---|---|
| [components/rpi/overview.md](components/rpi/overview.md) | 드라이버·통합 데몬 전체, 브로커·인증서 구축, 발급 서비스 운영 |
| [components/rpi/daemon-fsm.md](components/rpi/daemon-fsm.md) | 100ms tick, heartbeat, HOME, FSM 전이 |
| [components/rpi/imu.md](components/rpi/imu.md) | ICM-20948 수평 기준 — 오버레이부터 데몬 모듈까지 |
| [components/rpi/web.md](components/rpi/web.md) | `adts-web` 폰 브라우저용 관제 |
| [components/rpi/report/02-4-grid-merge.md](components/rpi/report/02-4-grid-merge.md) | 기구각→계약각, organized grid, 셀 병합 알고리즘 |

## Qt 관제 콘솔

| 문서 | 내용 |
|---|---|
| [components/qt/overview.md](components/qt/overview.md) | 앱 구조, RTSP 4채널, MQTT, 화면·조작, 포인트클라우드, 트러블슈팅 |
| [components/qt/build-and-deploy.md](components/qt/build-and-deploy.md) | 의존성 설치, 빌드, 배포 패키징 |

## 가이드

| 문서 | 내용 |
|---|---|
| [guides/cross-compile-setup.md](guides/cross-compile-setup.md) | Ubuntu → RPi arm64 커널 모듈 크로스컴파일 |
| [guides/rpi-kernel-build.md](guides/rpi-kernel-build.md) | 커널 버전 고정 & 빌드 환경 (`/dev/turret`) |
| [guides/rpi-docker-build-env.md](guides/rpi-docker-build-env.md) | RPi 빌드환경 Docker — 맥 M4 + CLion |
| [guides/stm32-static-analysis.md](guides/stm32-static-analysis.md) | 펌웨어 정적분석 (CI 게이트) |

## 아직 작성 전

- [overview/requirements.md](overview/requirements.md) — 요구사항
- [decisions/](decisions/) — 기술 결정 기록(ADR) 템플릿
- [meetings/](meetings/) — 회의록 템플릿
- [components/yocto/](components/yocto/) · [components/opensdk/](components/opensdk/) · [components/calibration/](components/calibration/)

---

문서를 추가하기 전에 [작성 규칙](CONTRIBUTING.md)을 읽어주세요.
