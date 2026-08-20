# Confluence 지도

**팀의 실제 문서는 Confluence에 있습니다.** 이 저장소는 그리로 가는 지도이고,
Confluence에 없는 것만 여기 둡니다.

→ [VEDA07_PROJECT_TEAM1 (VPT) 스페이스](https://lkj000619.atlassian.net/wiki/spaces/VPT)
· 페이지 104개 · 최종 확인 2026-08-20

> 아래 링크된 내용을 이 저장소에 복사하지 마세요. Confluence 쪽이 계속 갱신되므로
> 복사본은 만든 순간부터 낡습니다. [작성 규칙 0번](CONTRIBUTING.md)과 같은 이유입니다.

---

## 먼저 읽을 것

| 문서 | 왜 |
|---|---|
| [00. RPi 개발 문서 읽는 법·핵심 용어 사전](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057154) | 아래 01~06 시리즈의 진입점 |
| [2축 스캐너 디바이스 아키텍처 — RPi·STM32 전체 동작 명세](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/29032450) | 시스템 전체 그림 |
| └ [아키텍처 다이어그램 (Mermaid)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/29360148) | |
| [Device 파트 아키텍처 및 역할 분담 V2](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/19464224) | 누가 뭘 맡는지 |

## 계약 문서 — 여러 파트가 함께 보는 것

**바꾸려면 양쪽 합의가 필요한 문서들입니다.** 구현 전에 반드시 확인하세요.

| 계약 | 경계 |
|---|---|
| [MQTT 토픽 계약 v1.4 — Qt ↔ RPi 데몬](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) | Qt ↔ RPi |
| [스캔 산출물 포맷 — .json/.pcd 전 필드 레퍼런스](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38240259) | 데몬 → Qt·캘리브레이션 |
| [01-2. UART protocol·ABI·CRC·ioctl 계약 상세](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42860546) | STM32 ↔ RPi |
| [05. mTLS·Broker·Enrollment·배포](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844783) | 인증서 전반 |

## RPi 코드 기반 완전 개발 보고서

[최상위 페이지](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844741) · `develop 4372771` 기준 (2026-08-19)

가장 최신이고 가장 상세한 문서 묶음입니다. 하위 5개 시리즈 24페이지.

| 시리즈 | 하위 |
|---|---|
| [01. 시스템 아키텍처·저장소 구조](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844762) | [01-1 물리 구성·커널 경계](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42401796) · [01-2 UART 계약](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42860546) · [01-3 빌드·배포 경로](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42991633) |
| [02. adts_daemon 코어·FSM·산출물](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41877508) | [02-1 core·epoll](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42795011) · [02-2 tick·heartbeat·HOME·FSM](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42565636) · [02-3 점 수집·timeout](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057175) · [02-4 기구각→계약각·격자](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057196) · [02-5 파일 lifecycle](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42565657) |
| [03. 데몬 모듈](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41943041) | [03-1 module ABI](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42467331) · [03-2 MQTT](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696707) · [03-3 IMU](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42991656) · [03-4 LED](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42598413) · [03-5 Camera](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42729475) |
| [04. 커널 드라이버](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41877529) | [04-1 driver 기초](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42893316) · [04-2 turret_driver](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42467352) · [04-3 imu_driver](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42795032) · [04-4 led_sw_driver](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42500098) · [04-5 Device Tree·Kbuild](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42893337) |
| [05. mTLS·Broker·Enrollment·배포](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844783) | [05-1 TLS·PKI](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057218) · [05-2 Mosquitto ACL](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696728) · [05-3 Enrollment](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42795053) · [05-4 systemd·runbook](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42532870) |
| [06. 검증·결함·테스트](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41877550) | [06-1 수정 내역](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42598435) · [06-2 남은 결함·backlog](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42729496) · [06-3 test matrix](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42565678) · [06-4 진단·장애 runbook](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696749) |

## STM32

| 문서 |
|---|
| [STM32 Firmware](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/5505025) · [Protocol](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/3833923) · [Protocol Test](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/9207839) |
| [탈조 감지(Stall Detection) 및 재영점 메커니즘 설계서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44728327) |
| [17HS4401 & DRV8825 2축 스텝모터 제어 시스템 명세 v2.1](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/24215569) · [Motor 동작 flowchart](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/20381721) · [가감속 문서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44466191) |
| [MT6701 14비트 엔코더 I2C 드라이버 명세 v2.2](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/20283415) |
| [라이다 센서 문서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/24182819) · [IMU 센서 문서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44728356) |
| [STM32 UART/USART](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4030507) · [(STM32↔RPI)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4718599) · [(USART2 VCP)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4685835) · [IWDG](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/8454164) · [Basic](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/3506191) · [Networking 비교](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/5472281) |

## RPi 드라이버·데몬

| 문서 |
|---|
| [RPi 통합 데몬 — adts_daemon](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/35848195) |
| [RPi 커널 드라이버 — /dev/turret · /dev/imu · /dev/led_sw](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/36012034) · [driver 개요](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38764551) · [turret_driver 상세](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38240283) |
| [led_sw 통합 커널 드라이버 명세 v2.1](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/39550978) ([v2.0](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38895618)) |
| [MQTT CLI 테스트 가이드 — mosquitto_pub/sub](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/30703632) |
| [CrossCompile 환경세팅](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/14450710) · [Device 환경 세팅](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/11534342) |

## Qt 관제

[QT proto v2](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/40435717) · [QT v1](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31522817) · [LiDAR JSON 수신 애플리케이션 작업 정리](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/39419909)

## 자동 캘리브레이션 · 카메라

| 문서 |
|---|
| [Architecture Design of Automatic Calibration](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/26214404) |
| [논문 리뷰 — Automatic Online Calibration of Cameras and Lasers](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/23396359) |
| [02. Point Cloud 이후 Camera Automatic Calibration 상세 계획](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/26673178) |
| [sample 코드 분석·리뷰](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/27361308) · [sam_segmentation 개발 정리](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/32473089) · [run_neural_network 샘플 구조](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/9928708) · [Display_image_opencv 실행 정리](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/28672002) |
| [Open Platform SDK Try Docs](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4456517) |

## 기획 · 요구사항

| 문서 |
|---|
| [전체 프로젝트 계획서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/27361281) |
| [소프트웨어 요구사항 명세서(SRS) - 초안](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/22052873) |
| [CAL 문서 (SRS v0.3 · SDD v0.2)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/25657346) |
| [1D LiDAR Pan-Tilt 구조를 통한 Edge AI CCTV 2D 마커리스 자동 캘리브레이션 시스템](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/21561348) |
| [기획서v2 - A.D.T.S](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/11141122) · [기획서 초안 - 드론 관제 좌표계산](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/1146881) |
| [01. Point Cloud 생성 및 인계 계획](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/27492353) |

## 품질 · 도구

[Coding Convention](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4522032) · [코드 품질 및 자동화 가이드라인 v2.0](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/13991958) · [정적 분석 및 예외 관리 가이드라인](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4096023) · [Jenkins install guide](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/21037072) · [scan_batch.sh 사용법](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/37322753)

## 실험 · 브링업 기록

[1축 임시 스캔 브링업 (2026-07-29)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/28180499) · [자이로 센서 선정 테스트 — MPU-6050 vs ICM-20948](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/20906012) · [imu센서 드라이버 테스트](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/22511619)

## 회의록 · 일지

[회의록 폴더](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/425985) — [2026.07.02](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/98435) · [7.9 디바이스](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/9011201) · [2026-07-08 멘토링 질문](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/6979585)

[일일 관리 일지 폴더](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/1278101) — 1~8주차

---

## 이 저장소가 유일한 사본인 문서

⚠️ **아래 넷은 다른 어디에도 없습니다.** 원래 각 코드 저장소의 `docs/`에 있었지만
git으로 추적되지 않던 파일이라, 지금은 여기가 유일한 사본입니다.

| 문서 | 원래 위치 |
|---|---|
| [components/qt/overview.md](components/qt/overview.md) | `QT/docs/QT_CONSOLE_OVERVIEW.md` |
| [components/stm32/motor-ramp.md](components/stm32/motor-ramp.md) | `STM32/docs/motor_ramp.md` |
| [components/stm32/sensors/lidar.md](components/stm32/sensors/lidar.md) | `STM32/docs/lidar.md` |
| [components/stm32/sensors/imu.md](components/stm32/sensors/imu.md) | `STM32/docs/imu.md` |

> **각 코드 저장소에 커밋하는 편이 낫습니다.** 코드와 같은 PR에서 리뷰되어야
> 안 썩습니다. 옮기고 나면 여기는 스텁으로 줄이면 됩니다.

## 여기서 작성한 문서

| 문서 | 비고 |
|---|---|
| [overview/architecture.md](overview/architecture.md) | Confluence 아키텍처 문서를 가리키는 스텁 + **코드 대조로 확인된 낡은 부분 표** |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 이 저장소의 작성 규칙 |
| [decisions/](decisions/) · [meetings/](meetings/) | 템플릿만 있음 |

## 코드 저장소 README를 가리키는 스텁

[components/rpi/overview.md](components/rpi/overview.md) ·
[components/rpi/web.md](components/rpi/web.md) ·
[components/stm32/overview.md](components/stm32/overview.md) ·
[components/qt/build-and-deploy.md](components/qt/build-and-deploy.md) ·
[guides/](guides/)
