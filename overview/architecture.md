# 시스템 아키텍처

> **초안입니다.** 각 컴포넌트 문서에서 뽑아 재구성했습니다.
> ⚠️ 표시가 붙은 곳은 문서끼리 서로 다르게 적혀 있어 확인이 필요한 부분입니다.

## 한 줄 요약

Pan-Tilt 2축 위에 올린 1D 라이다로 공간을 훑어 포인트클라우드를 만들고,
CCTV 4채널 영상과 함께 데스크톱 콘솔에서 관제하는 킷.

> ⚠️ **이름과 실제 기능이 어긋나 있습니다.** 펌웨어·드라이버 문서는 A.D.T.S를
> "Anti-Drone Tracking & Targeting System"으로 정의하지만, `protocol.h` v4에서
> 안티드론 조준(`SET_TARGET`/`ALIGNED`/`MODE`/`DISTANCE`)이 제거됐고 지금은
> 스캐너·캘리브레이션 킷으로 동작합니다. 무엇이 맞는지 정하고 각 문서 첫 줄을 맞춰야 합니다.

## 구성도

```
 ┌──────────────────────────┐
 │ Hanwha PNM-C16083RVQ     │
 │ 멀티센서 카메라 (센서 0~3) │
 └───────────┬──────────────┘
             │  RTSP :554  (RPi를 거치지 않는 독립 경로)
             ▼
 ┌───────────────────────────────────────────┐
 │ Qt 관제 콘솔  "SPATIAL·VMS"                │
 │  · RtspDecoder ×4 (FFmpeg, 채널당 1스레드)  │
 │  · MqttBridge / ScanFetcher / EnrollDialog │
 │  · DataBridge 추상화 → 실장비 / Demo 전환   │
 │  macOS · Windows · (Linux 빌드만)          │
 └───────────┬───────────────────┬───────────┘
             │ MQTT+mTLS :8883   │ HTTPS :8443
             │ 스캔 명령·상태     │ 등록(/enroll) · 스캔파일(GET /scan)
             ▼                   ▼
 ┌───────────────────────────────────────────┐
 │ Raspberry Pi 4B   (Linux 6.12.y 고정)      │
 │                                           │
 │  Mosquitto 브로커 :8883                    │
 │  발급 서비스 adts_enroll :8443             │
 │                                           │
 │  통합 데몬 adts_daemon                     │
 │   core/  epoll 루프 · FSM · 좌표변환 · pcd  │
 │   modules/  mqtt · imu(/dev/imu) · led(⏳)  │
 │                    │                      │
 │  커널 드라이버 /dev/turret (serdev)         │
 └────────────────────┼──────────────────────┘
                      │ UART USART1, 115200 8N1
                      │ protocol.h 프레임
                      ▼
 ┌───────────────────────────────────────────┐
 │ STM32F401RE (NUCLEO)  펌웨어 `adts`        │
 │  App/uart_rpi  프로토콜 디스패처            │
 │  App/motor     2축 스텝 구동 · 램프 · 홈    │
 │  App/lidar     TOFSense-F2 P (NLink 파서)  │
 │  엔코더 MT6701 (양축 절대)                  │
 └───────────────────────────────────────────┘
```

## 컴포넌트

| 컴포넌트 | 하는 일 | 문서 |
|---|---|---|
| STM32 | 2축 스텝 구동, 홈 확립, 라이다 프레임 수집, RPi 링크 | [components/stm32/](../components/stm32/overview.md) |
| RPi 드라이버 | `/dev/turret` — serdev char 드라이버, `shared/protocol.h` 직접 include | [components/rpi/](../components/rpi/overview.md) |
| RPi 데몬 | epoll 루프·FSM, 좌표 변환, pcd 내보내기, MQTT·IMU 모듈 | [components/rpi/](../components/rpi/overview.md) |
| RPi 브로커 | Mosquitto(mTLS) + 인증서 발급 서비스 | [components/rpi/](../components/rpi/overview.md) |
| Qt 콘솔 | CCTV 4채널 + 스캔 제어·상태·포인트클라우드 | [components/qt/](../components/qt/overview.md) |

## 세 개의 경계

| 경계 | 매체 | 계약 | 진실 소스 |
|---|---|---|---|
| STM32 ↔ RPi | UART 115200 8N1 | `[SOF 0xAA][CMD][LEN][PAYLOAD][CRC16]` | `shared/protocol.h` |
| RPi ↔ Qt | MQTT/mTLS :8883, HTTPS :8443 | `adts/cmd/*`, `adts/state/*`, `adts/event/*` | 데몬 `mqtt_module.c` |
| 카메라 → Qt | RTSP :554 | `rtsp://…/<0~3>/profile2/media.smp` | `CameraConfig.h` |

여기에 **네 번째 계약**이 하나 더 있습니다 — 스캔 산출물(`.json`/`.pcd`)의 좌표계입니다.
매체가 아니라 파일이라 위 표에 안 들어가지만, 소비자(Qt·카메라 캘리브레이션)가 있는
엄연한 경계입니다.

→ 상세: [STM32↔RPI UART](../interfaces/stm32-rpi-uart.md) ·
[Qt↔RPi mTLS 발급](../interfaces/qt-rpi-enroll-mtls.md) ·
[스캔 산출물 좌표계·포맷](../interfaces/scan-output-format.md)

## 데이터가 흐르는 순서

1. Qt가 `adts/cmd/scan` 발행 (`req_id`, 팬·틸트 범위, 격자 간격, 센서 높이)
2. 데몬이 **홈을 먼저 잡고** `ST_SCANNING` 진입 → 드라이버가 `CMD_SCAN_START`
3. STM32가 틸트를 빠르게 스윕하며 라이다 프레임을 `CMD_SCAN_DATA`(18B)로 올림
   — 팬은 줄마다 1°씩 (기구 180°만 돌아도 계약 방위 360° 확보)
4. 데몬이 기구각 → 계약각 변환 + 라이다 오프셋 보정 후 organized 격자에 담음
5. `CMD_SCAN_DONE`(또는 타임아웃) → `ST_EXPORT`에서 `.json`/`.pcd` 한 번에 기록
6. `adts/state/scan`에 **파일 경로만** 발행 → Qt가 HTTPS로 파일을 따로 받아 렌더링

→ [데몬 상태머신](../components/rpi/daemon-fsm.md)

## 알아둘 설계 결정 세 가지

**1. 영상 경로와 제어 경로는 완전히 분리돼 있습니다.**
카메라는 RPi를 거치지 않고 Qt가 직접 RTSP로 받습니다. 카메라가 죽어도 스캔은 되고,
브로커가 죽어도 영상은 나옵니다. "Qt가 왜 영상 토픽을 구독하지 않느냐"는 질문이
반복돼 왔는데, **영상은 애초에 MQTT를 타지 않는 설계**입니다.

**2. 스캔 결과는 MQTT로 흐르지 않습니다.**
`adts/state/scan`에는 **파일 경로만** 실립니다. 점 데이터는 Qt가 HTTPS로
`GET /scan/<파일명>` 해서 따로 받습니다. 브로커에 대용량 페이로드를 태우지 않기 위한 분리입니다.

**3. `cmd/*` 토픽은 절대 retain하지 않습니다.**
retain하면 재접속할 때마다 스캔이 다시 실행되는 안전 사고가 납니다.
명령마다 `req_id`(UUID 앞 8자)를 붙여 자기가 보낸 응답만 받습니다 — 콘솔이 여러 대
붙을 수 있기 때문입니다.

## 담당

| 영역 | 담당 |
|---|---|
| STM32 `uart_rpi`·`shared`, RPi 드라이버·데몬 core | 이현우 |
| STM32 `motor`, 정적분석·CI (QA) | 강유근 |
| STM32 `lidar`·메인루프·IWDG, 데몬 `imu` | 송영빈 |
| 브로커·인증서·데몬 `mqtt` | 이광진 |
| `vision` (CLAHE/샤프닝) ⏳ | 이영민 |

미구현: `led` 모듈(`/dev/led`) STUB, `vision` 진행 중.

## ⚠️ 이 문서를 읽기 전에 — 진짜 최신은 Confluence입니다

이 문서는 **로컬 작업 트리의 코드와 README에서** 재구성한 것입니다. 그런데 팀의 실제
문서는 [Confluence VPT 스페이스](https://lkj000619.atlassian.net/wiki/spaces/VPT)에 104개
페이지로 있고, 그쪽이 훨씬 최신입니다. 아래는 대조하면서 확인된 차이입니다.

**원인을 특정했습니다**: `~/ClionProjects/RPi`가 `feature/web-console` 브랜치에 있고
`origin/main`보다 **65커밋 뒤처져** 있습니다. QT(`5888153`)와 STM32(`003e483`)는
계약서가 인용한 커밋과 정확히 일치하니, RPi 하나만 낡은 것입니다.

| 항목 | 이 저장소가 근거로 삼은 로컬 트리 | Confluence·`origin/main` 현행 |
|---|---|---|
| `protocol.h` | RPi v5 / STM32 v6 | **양쪽 v6, md5까지 동일** — drift-check 정상 |
| MQTT 계약 | "v1.0의 `adts/kit1/...`과 실구현이 다름" | **v1.4** — `kit1`은 의도적으로 제거(YAGNI) |
| `cmd/rearm` | "계약 외 확장" | **v1.2에서 정식 추가된 계약** |
| IMU | MPU-6050 | **ICM-20948** (2026-08-13 교체) |
| 데몬 모듈 | mqtt · imu · led(STUB) | **+ camera 모듈** (JSON을 mTLS TCP 2222로 카메라에 직접 업로드) |

→ [MQTT 토픽 계약 v1.4](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) ·
[스캔 산출물 포맷 전 필드 레퍼런스](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38240259) ·
[RPi 코드 기반 완전 개발 보고서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844741)

**로컬 작업 트리(`~/ClionProjects`)가 낡았습니다.** 원격 브랜치를 받아오면
위 차이는 대부분 사라질 것으로 보입니다.

## 아직 열려 있는 것 (Confluence 기준)

문서 불일치가 아니라 실제 미결 사항입니다.

1. **방위 부호(손대칭) 미검증** — 평평한 천장·바닥은 회전 대칭이라 mirror 버그를 못 잡습니다.
   비대칭 지형지물로 대조하기 전까지 방위 손대칭을 신뢰하면 안 됩니다.
2. **IMU 설치각 오프셋을 킷이 3.6° 기울어진 상태에서 잡았습니다.** 보정이 기울기를
   줄이는 게 아니라 키우는 상태라, 데몬 게이트 임계가 10.0°로 열려 있습니다 — 사실상
   아무것도 막지 않습니다. 킷을 바로 세우고 재측정해야 합니다.
3. **되감기 15초는 잠정치** — 프로토콜에 "되감기 완료" 통지가 없어 시간으로 때우고 있습니다.
4. **파일명 충돌 가능** — 초 단위 session + 고정 `sweep-000001`이라 같은 초에 두 결과를
   마감하면 덮어씁니다.

---

*채워야 할 것: 전원·배선 계통, 성능 목표(스캔 1회 소요 시간, 점 밀도),
카메라 ↔ 스캔 데이터를 합치는 캘리브레이션 파이프라인.*
