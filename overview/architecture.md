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

## ⚠️ 지금 어긋나 있는 것들

아키텍처 그림보다 이쪽이 더 급합니다.

**1. `protocol.h` 사본이 마스터보다 앞서 있습니다.**

| 사본 | 버전 | 규칙상 |
|---|---|---|
| `RPi/shared/protocol.h` | **v5** | 마스터 — 여기서 먼저 고쳐야 함 |
| `STM32/shared/protocol.h` | **v6** | 다운스트림 — 마스터를 따라가야 함 |

규칙은 "RPi에서 먼저 수정하고 STM32 사본을 맞춘다"인데 반대로 돼 있습니다.
v6 변경(`proto_err.axis` 1B→2B, `ERR_BUSY`/`ERR_ENCODER`, `proto_status` 5B→15B)이
RPi에 없어서, STM32가 보내는 `proto_status`를 드라이버가 길이 불일치로 버립니다.
drift-check CI가 이걸 잡아야 하는데 통과하고 있다면 CI도 함께 확인하세요.

**2. 문서에 적힌 프로토콜 버전이 낡았습니다.**
`components/stm32/overview.md`는 `PROTO_VERSION=3`이라고 적고 있습니다(실제 v6).
[CONTRIBUTING 0번 규칙](../CONTRIBUTING.md)대로, 값을 문서에 적지 말고 헤더를 링크하세요.

**3. MQTT 토픽이 계약서와 다릅니다.**
계약서 v1.0은 `adts/kit1/...`인데 데몬 실구현에는 `kit1` 세그먼트가 없고,
Qt는 실구현 쪽에 맞춰져 있습니다. 계약서를 실구현에 맞추든 반대로 하든 한쪽으로 확정해야 합니다.

**4. `adts/cmd/rearm`은 계약 외 확장입니다.** 계약서에 반영이 필요합니다.

---

*채워야 할 것: 전원·배선 계통, 성능 목표(스캔 1회 소요 시간, 점 밀도),
카메라 ↔ 스캔 데이터를 합치는 캘리브레이션 파이프라인.*
