# SPATIAL·VMS — Qt 관제 콘솔

| 항목 | 값 |
|---|---|
| 저장소 | `VEDA-4th-Oppenheimer/QT` (`main`) |
| 담당 | 송영빈 (Qt) |
| 문서 갱신 | 2026-08-21 (`e777e73` 기준) |
| 실행 파일명 | `spatial_vms` / 배포명 `SPATIAL-VMS` |
| 연관 계약 | MQTT 인터페이스 계약 (데몬=이현우 / Qt=송영빈 / 브로커·인증서=이현우·송영빈). 아래 §4 에 이 문서가 의존하는 부분을 그대로 옮겨 적었다 |

---

## 1. 이 앱이 하는 일

ADTS(1D LiDAR Pan-Tilt 스캐너 킷)의 **데스크톱 관제 UI** 다. 역할은 딱 두 가지다.

1. **CCTV 4채널 실시간 영상** — Hanwha Vision PNM-C16083RVQ 멀티센서 카메라의
   RTSP 스트림을 직접 받아 디코딩해 보여준다.
2. **스캔 제어·상태 관제** — RPi 통합 데몬과 MQTT 로 통신해 스캔을 시작/중단하고,
   진행률·결과·오류·IMU 수평 상태를 표시하며, 스캔 결과 포인트클라우드를 2D/3D 로
   그린다.

**두 경로는 서로 완전히 독립적이다.** 영상은 MQTT 를 타지 않고, 스캔 제어는 RTSP 와
무관하다. 카메라가 안 나와도 스캔은 되고, 브로커가 죽어도 영상은 나온다. 다른 파트에서
"Qt 가 왜 영상 토픽을 안 구독하냐"는 질문이 반복돼 왔는데, **영상은 애초에 MQTT 를
거치지 않는 설계**다 (§3).

플랫폼: macOS / Windows / Linux (Qt6 Widgets). **macOS 와 Windows 는 배포본 패키징과
타 PC 실행까지 검증했다**(§8). Linux 는 빌드만 가능하고 패키징 스크립트가 없다.

---

## 2. 전체 구조

```
  ┌────────────────────────┐
  │ PNM-C16083RVQ 카메라    │──RTSP(554)──┐          ※ RPi 를 거치지 않는다
  │ 센서 0~3 = CH1~4        │             │
  └────────────────────────┘             ▼
                              ┌──────────────────────┐
                              │ RtspDecoder ×4       │
                              │ FFmpeg, 채널당 1스레드 │──▶ CameraTile ×4 (대시보드 좌측)
                              └──────────────────────┘
  ┌────────────────────────┐
  │ RPi 4B                 │
  │  ├ Mosquitto (8883)    │◀─MQTT/mTLS──┐
  │  ├ 통합 데몬            │             │
  │  └ 발급 서비스 (8443)   │◀─HTTPS──┐   │
  └────────────────────────┘         │   │
                                     │   ▼
                              ┌──────┴───────────────┐
                              │ MqttBridge (Paho C++)│──▶ TopBar / TopViewPanel /
                              │ ScanFetcher (Qt Net) │    CalibrationTab / DevicesTab /
                              │ EnrollDialog         │    EventLogTab / StatusBar
                              └──────────────────────┘

  DemoBridge — 브로커·킷이 없어도 위 MQTT 경로를 시뮬레이션 (기본 꺼짐)
```

`DataBridge` 추상 클래스가 `MqttBridge`(실장비)와 `DemoBridge`(시뮬레이터)의 공통
시그널 인터페이스를 정의한다. 각 위젯은 `DataBridge*` 하나만 알고 어느 쪽이 붙어
있는지 신경 쓰지 않는다. `MainWindow` 가 두 소스를 같은 슬롯에 연결해두고,
`모드 → Demo Mode` 토글로 **어느 쪽을 구동할지만** 정한다.

RPi 한 대에서 포트 두 개를 쓴다는 점이 헷갈리기 쉽다.

| 포트 | 프로토콜 | 용도 |
|---|---|---|
| 8883 | MQTT + mTLS | 스캔 명령·상태 (상시 연결) |
| 8443 | HTTPS | ① 최초 등록 `POST /enroll` ② 스캔 파일 `GET /scan/<파일명>`, `GET /scans` |

---

## 3. RTSP — CCTV 영상

- `src/RtspDecoder` — libavformat/avcodec/swscale 로 **채널 1개당 스레드 1개**,
  소프트웨어 디코딩. 최대 960px 폭으로 다운스케일 후 `QImage` 로 `frameReady` 발행.
- `src/RtspSource` — `config/cameras.json` 을 읽어 채널별 디코더를 기동한다.
  설정되지 않은 채널은 건드리지 않아 Demo/Live 상태가 그대로 유지된다.
- **URL 형식** (`src/CameraConfig.h` 가 조립):
  `rtsp://<계정>:<비번>@<IP>:554/<0~3>/profile2/media.smp`
  센서 0~3 이 CH1~CH4. `profile2` 는 서브스트림 — 4채널 동시 디코딩이라 메인스트림
  (`profile1`)은 쓰지 않는다. 계정/비밀번호는 퍼센트 인코딩한다.
- **재연결 정책**: 연결 실패(또는 프레임을 한 장도 못 받은 세션)가 **3회 연속**이면
  자동 재시도를 멈춘다. 카메라 없는 자리에서 무한 재시도로 로그를 채우지 않기
  위해서다. 다시 붙이려면 `모드 → CCTV 재연결`. 프레임이 오던 스트림이 끊긴 경우는
  시도 횟수가 리셋되므로 정상 재연결은 그대로 동작한다.
- **카메라 정보는 사용자가 입력한다.** 카메라는 RPi 와 물리적으로 떨어져 있고 데몬은
  카메라를 건드리지 않으므로 서버를 경유할 이유가 없다. 등록 화면에서 받고, 이후
  `모드 → 카메라 설정…` 에서 바꾸면 **재시작 없이 즉시 적용**된다.

---

## 4. MQTT — 스캔 제어·상태

### 4.1 실제로 오가는 토픽

> ⚠️ **계약서는 `adts/kit1/...` 이지만 RPi 데몬 실구현에는 `kit1` 세그먼트가
> 없다** (`daemon/modules/mqtt/mqtt_module.c`). 이 앱은 **실구현 쪽**에 맞췄다.
> 계약서가 재확정되면 `src/MqttBridge.cpp` 상단 상수와 함께 고쳐야 한다.

| 토픽 | 방향 | QoS | Retained | 페이로드 |
|---|---|---|---|---|
| `adts/cmd/scan` | Qt → 데몬 | 1 | **금지** | `{req_id, pan_ddeg:[a,b], tilt_ddeg:[a,b], step_ddeg, sensor_height_mm}` |
| `adts/cmd/stop` | Qt → 데몬 | 1 | 금지 | `{req_id}` |
| `adts/cmd/home` | Qt → 데몬 | 1 | 금지 | `{req_id}` — IDLE 에서만 |
| `adts/cmd/disarm` | Qt → 데몬 | 1 | 금지 | `{req_id}` — 안전정지 |
| `adts/cmd/rearm` | Qt → 데몬 | 1 | 금지 | `{req_id}` — **계약 외 확장** (§4.4) |
| `adts/state/daemon` | 데몬 → Qt | 1 | 예 | FSM·링크·IMU. **LWT 대상** |
| `adts/state/scan` | 데몬 → Qt | 1 | 예 | 스캔 결과 — **파일 경로만**, 점 데이터 없음 |
| `adts/event/progress` | 데몬 → Qt | 0 | 아니오 | 진행률 ~2Hz, 유실 가정 |
| `adts/event/error` | 데몬 → Qt | 1 | 아니오 | 오류 코드/메시지 |

Qt 는 `adts/state/#` 와 `adts/event/#` 두 줄만 구독한다.

**`cmd/*` 는 절대 retain=true 로 발행하지 않는다.** 재접속할 때마다 스캔이 재실행되는
안전 사고를 막기 위한 계약 §2 의 명시적 경고다.

**`req_id`** — 명령마다 UUID 앞 8자를 새로 만들고(`MqttBridge::newReqId`), 자신이 보낸
`req_id` 가 아닌 응답은 무시한다(`acceptsReqId`, 계약 §4). 다른 콘솔이 동시에 붙어
있을 수 있기 때문이다. `req_id` 가 없는 페이로드(`state/daemon` 등)는 항상 통과한다.

**LWT** — 데몬이 죽으면 브로커가 대신 `state/daemon` 에
`{"state":"OFFLINE","online":false}` 를 발행한다. Qt 는 이걸 그대로 반영하므로 별도
처리가 없다. 추가로 연결이 끊기면 keepalive 를 기다리지 않고 로컬 UI 도 즉시
OFFLINE 으로 내린다.

### 4.2 연결 설정

`config/mqtt.json`:

```json
{
  "host": "172.20.32.110",
  "port": 8883,
  "cert_dir": "certs",
  "server_name": "raspberrypi"
}
```

`cert_dir` 아래 `ca.crt` / `qt-console.crt` / `qt-console(-trad).key` 3개가 모두 있으면
`ssl://` (mTLS), 없으면 `tcp://` 평문으로 degraded 접속한다. 브로커가 TLS 전용이라
평문은 실제로는 실패한다 — **로컬에 평문 브로커를 띄운 개발 상황에서만 의미가 있다.**

TLS 1.2 로 고정한다(데몬 쪽 `mosquitto_tls_opts_set` 과 동일). keepalive 30초,
clean session, 최초 접속 실패 시 5초 주기 재시도(붙으면 자동으로 멈추고, 이후 끊김은
Paho 자동 재접속이 담당).

**Client ID 는 `qt-console-<호스트명>-<난수4자>`** 로 만든다. 계약 §1 은 고정
`qt-console` 이라고 적었지만, MQTT 는 같은 ID 로 두 번째가 붙으면 브로커가 첫 번째를
끊으므로 **여러 명이 동시에 콘솔을 켜면 서로 계속 끊어내는 상태**가 된다. 권한은
Client ID 가 아니라 인증서 CN 으로 판정되므로(`use_identity_as_username true` → ACL 의
`user qt-console`) 인증서·ACL 은 그대로 쓸 수 있다.

### 4.3 데이터 모델 (`src/Models.h`)

계약 §3 의 JSON 필드와 1:1 로 대응한다.

| 구조체 | 출처 토픽 | 주요 필드 |
|---|---|---|
| `DaemonState` | `state/daemon` | state, online, link_alive, homed, scanning, cur_pan/tilt_ddeg, last_err, **last_err_axis**, **diag{…}**, level{valid, roll, pitch} |
| `StmDiag` | `state/daemon.diag` | valid, tx_fail, rx_ovf, enc_retry, lidar_drop, reject_busy |
| `ScanResult` | `state/scan` | req_id, ok, pcd, points, stm_reported, ts *(+ 계약에만 있는 미수신 필드)* |
| `ScanProgress` | `event/progress` | req_id, points, expected, percent |
| `KitError` | `event/error` | req_id, code, name, msg, fatal, **axis** |

**STM 진단 카운터 (`diag`, proto v6)** — STM32 가 `CMD_STATUS` 로 1초마다 올리는 부팅 이후
누적값이고 65535 에서 포화한다.

| 필드 | 0 이 아니면 |
|---|---|
| `tx_fail` | STM32 UART 송신 실패 — 상행 프레임이 유실돼 스캔 점 수가 실제보다 적을 수 있다 |
| `rx_ovf` | 수신 링버퍼 오버플로 — **STM32 메인루프가 오래 막혔다** (256B = 하행 프레임 20개분) |
| `enc_retry` | 엔코더 I2C 판독 재시도(양축 합). 계속 오르면 배선 접촉 의심 |
| `lidar_drop` | 라이다 큐가 차서 버린 샘플. 격자에 빈 셀로 남는다 |
| `reject_busy` | 진행 중이라 거절한 SCAN_START. 조작자가 중복으로 눌렀다는 뜻 |

> **`valid=false` 는 "정상"이 아니라 "모른다"다.** STM32 에 구버전 펌웨어가 올라가 있어
> `CMD_STATUS` 를 아예 안 보내거나 첫 주기가 아직 안 온 것이다. 0 을 그대로 초록불로
> 그리면 안 된다 — `level.valid` 와 같은 함정이다.

**축 표기 (`last_err_axis` / `KitError.axis`, proto v6)** — 0=축무관 / 1=팬 / 2=틸트 /
3=양축. **비트 플래그라 3 은 "둘 다"** 라는 뜻이다. 데몬 자체 판정(100번대)은 항상 0 이다.
`axisLabel()` 이 축무관일 때 빈 문자열을 돌려주므로 그대로 이어 붙여도 된다
(`[3] STM_ERROR … (팬)` / `[100] ERR_DISARM …`).

> **계약 §3.4 와 실구현의 차이** — `state/scan` 실구현은
> `{req_id, ok, pcd, points, stm_reported, ts}` 만 보낸다. `session_id` / `scan_id` /
> `json` / `rows` / `columns` / `expected` / `duration_s` 는 계약에 있지만 아직 안 온다.
> 구조체에는 계약대로 남겨뒀고(나중에 추가되면 코드 변경 없이 채워진다), UI 는 값이
> 실제로 온 항목만 표시하고 나머지는 `—` 로 둔다.

**IMU** — `state/daemon.level` 이 계약상 유일한 IMU 출처다(별도 `imu/level` 토픽 없음).
`valid=false` 면 "아직 측정 없음"이므로 **값을 표시하지 않고 `N/A` 로 둔다.** 여기를
잘못 만들면 데이터가 안 와도 roll=0/pitch=0 이 "정상 수평"으로 초록색 표시돼 킷이
멀쩡해 보인다.

**수평 허용 오차는 ±10.0°** 다(`ImuState::level(tolDeg=10.0)`). 원래는 캘리브레이션
권장값(1~2°)을 따라 1.5° 였는데, 그러면 **데몬은 스캔을 정상적으로 도는데 화면에만
"기울었다" 배너가 계속 떠서** 배너가 무의미해졌다. 브링업 동안은 데몬 게이트
(`LEVEL_GATE_MAX_DEG`)와 같은 값으로 두고, 배너가 뜨면 실제로 스캔도 거부되는 상태이도록
맞춘다.

> 근본 원인은 Qt 가 아니다 — 킷이 실제로 3.6° 기울어 있는데 **그 자세를 IMU 설치각
> 오프셋의 기준으로 잡아버린** 것이다. 거치를 바닥평면 기준으로 바로잡고 오프셋을 다시
> 재면 데몬 쪽을 3.0° 이하로 조일 수 있고, 그때 여기도 같이 조여야 한다. **이 값은 데몬
> 값과 항상 같이 움직인다** (2026-08-21, `e777e73`).

**오류 코드** — `code` 로 **출처**가 갈린다. 100 미만은 STM32 가 `CMD_ERROR` 로 올린
원본이고, 100 이상은 데몬 자신의 판정이다.

| 코드 | 이름 | 뜻 |
|---|---|---|
| 1 | BAD_CRC | STM32: 프레임 CRC 불일치 |
| 2 | BAD_LEN | STM32: 프레임 길이 이상 |
| 3 | NOT_HOMED | STM32: 홈이 안 잡힌 상태에서 이동 요청 |
| 4 | OUT_OF_RANGE | STM32: 요청 각도가 가동 범위 밖 |
| 5 | STALL | STM32: 탈조 감지 |
| 6 | LIDAR | STM32: 라이다 이상 |
| 100 | ERR_DISARM | 데몬: 안전정지 |
| 101 | HOME_TIMEOUT | 데몬: 홈 무응답으로 요청 취소 |
| 102 | NOT_LEVEL | 데몬: 수평 게이트가 스캔을 거부 |
| 103 | UPLOAD_FAIL | 데몬: 카메라 업로드 실패 — **파일은 로컬에 남는다** |
| 104 | BAD_REQUEST | 데몬: `cmd` 페이로드 필드 누락/형식 오류 |
| 105 | EXPORT_FAIL | 데몬: 산출물 기록 실패 — **측정값 복구 불가** |
| 106 | BUSY | 데몬: 지금 상태에서 받을 수 없는 요청 |

> 이 경계가 생기기 전에는 **4 하나가 세 뜻으로 쓰여서**, `code=4` 를 받고도 STM 이 거절한
> 건지 데몬이 페이로드를 못 읽은 건지 구분할 수 없었다. 103 과 105 를 가른 것도 같은
> 이유다 — 103 은 파일이 남지만 105 는 측정값 자체가 없다.

`name` 은 STM 오류면 항상 `"STM_ERROR"`(코드별 세부 이름이 아니다)로 오고, 데몬 판정이면
`"ERR_NOT_LEVEL"` 처럼 구체적으로 온다. 화면에 코드를 같이 찍어야 하는 이유다.

`fatal` 은 데몬이 실제로 채운다(2026-08-12). 정의가 "하드웨어가 고장났나"가 아니라
**화면을 어떻게 그릴까** 의 기준이라는 점에 유의.

| `fatal` | 의미 | 해당 코드 |
|---|---|---|
| `true` | 작업이 멈췄고 사용자가 개입해야 한다 — 배너·모달 | 3 NOT_HOMED / 5 STALL / 6 LIDAR / 100 안전정지 / 101 홈 타임아웃 / 102 수평 NG / 105 산출 실패 |
| `false` | 로그 한 줄이면 된다. 계속되거나 다시 시도하면 된다 | 1 BAD_CRC / 2 BAD_LEN / 4 OUT_OF_RANGE |

### 4.4 REARM — 계약 외 확장

계약 §5 표는 DISARM 상태의 "복구" 버튼을 규정하면서 대응 토픽을 비워뒀다. 그대로 두면
**DISARM 을 한 번 누르는 순간 HOME/SCAN 이 영구히 비활성**이 되어 빠져나올 방법이 없다.
그래서 DISARM 상태에서는 HOME 버튼이 `REARM` 으로 바뀌고 `adts/cmd/rearm` 을 발행한다.

- RPi `develop` 브랜치 데몬(`core_rearm()`)이 이 토픽을 구독해 `DISARM → IDLE` 로
  복구한다. **계약 문서 반영은 이현우 협의 대기.**
- 복구 가능 여부는 **데몬이 판정한다.** DISARM 이 아니거나 STM32 링크가 죽어 있으면
  거부하고 데몬 로그에 사유를 남긴다. Qt 는 미리 걸러내지 않는다 — 판정 기준이 두
  곳으로 갈라지는 것을 막기 위해서다. 거부되면 `state/daemon` 이 DISARM 그대로다.
- 복구는 데몬 상태만 되돌린다. **축 위치는 여전히 미지**이고 대기 중이던 스캔 요청은
  폐기되므로, 스캔은 다시 요청해야 한다.

---

## 5. 화면과 조작

### 5.1 상단 바 (TopBar)

좌측에 MQTT 연결 / IMU / 데몬 STATE 칩, 우측에 명령 버튼 4개.

| 버튼 | 활성 조건 | 발행 |
|---|---|---|
| HOME | `state == IDLE` | `cmd/home` — 스캔 없이 홈만 세운다(설치·정비용). 스캔 직전에는 데몬이 자동으로 홈을 잡는다 |
| SCAN | `state == IDLE` | `cmd/scan` — pan `[0, 1791]` / tilt `[-900, 900]` / step `9` (0.1° 단위) |
| STOP | `state == SCANNING` | `cmd/stop` |
| DISARM | **항상** | `cmd/disarm` — 비상정지라 상태와 무관하게 누를 수 있어야 한다 |
| REARM | `state == DISARM` (HOME 자리에 표시) | `cmd/rearm` (§4.4) |

> **팬 끝각이 1800 이 아니라 1791 인 이유** — 틸트가 바닥을 지나면 한 줄이 방위 `p` 와
> `p+180` 을 함께 훑으므로 팬은 반 바퀴만 돌면 된다. 1800 까지 돌면 첫 줄과 마지막 줄이
> 같은 평면이라 중복된다. 그래서 `1800 − step` 까지만 간다. **step 을 바꾸면 이 값도
> 같이 바꿔야 한다** (10 → 1790, 9 → 1791).

**스캔 후 자동 DISARM** — 스캔이 끝나면 데몬이 되감기 유예(15초) 뒤 스스로 DISARM 으로
내려간다. 그래서 다음 스캔 전에 REARM 을 한 번 눌러야 한다. 유예 중에 새 스캔/홈을
요청하면 예약은 취소된다.

### 5.2 탭 5개

**① 메인 대시보드**

- 좌: CH1~4 CCTV 2×2 그리드(RTSP 직결)
- 우: TOP-VIEW 패널 — 2D 조감도 / 3D 점군 전환, IMU ROLL·PITCH, SCAN PTS·EXPECTED
- 좌우 비율은 **스플리터 드래그로 조절**하고 `QSettings` 에 저장된다(현장마다 영상
  위주인지 스캔 위주인지가 다르다)
- TOP-VIEW 는 **별도 창 전체화면**으로 뺄 수 있다 — 헤더의 `⛶ 전체화면`, 지도
  더블클릭, `모드 → TOP-VIEW 전체화면 켜기/끄기`. 되돌리기는 `Esc` 또는 같은 동작
- 2D 는 배치도(카메라·감지객체와 같이 보는 용도), 3D 는 벽 높이 확인용이다. 바닥
  투영만으로는 벽과 바닥이 같은 점으로 겹쳐 구분이 안 된다
- 3D 칸은 **파일 목록 → 뷰어** 2단 화면이다. 드래그 회전 / 휠 확대 / Shift+드래그 이동
  / 더블클릭 시점 초기화

**② CALIBRATION** — 계약 §5 FSM 4단계(IDLE → SCANNING → EXPORT → IDLE) 진행 표시 +
SESSION LOG + PROGRESS(`event/progress`) + LAST SCAN RESULT(`state/scan`).
실구현이 아직 안 보내는 필드는 `—` 로 뜬다.

**③ DEVICES / MQTT** — 장비 카드 4개(IMU / TOFSense-F2 P / STM32+DRV8825 / RPi4B) +
`adts/...` 토픽 9개 테이블(RATE·방향·retain 여부).

**④ EVENT LOG** — 모든 로그(`logLine` 시그널)를 TIME / TAG / SOURCE / MESSAGE 로
시간순 표시. 태그별 색상 배지.

**⑤ SETTINGS** — 테마 전환, Demo Mode, 카메라 설정·재접속, TOP-VIEW 전체화면, 센서 높이,
스캔 파일 열기, 로그아웃.

`모드`·`테마` 메뉴에 흩어져 있던 것을 성격별로 묶어 한 화면에 모았다. 메뉴는 항목이
늘수록 찾기 어렵고 **현재 값(센서 높이, 카메라 IP)을 보여줄 수 없다** — 값과 조작을 같이
두려고 탭으로 옮겼다. 메뉴 항목은 그대로 남아 있어 둘 중 아무 쪽으로나 해도 된다.

> 이 위젯은 **상태를 갖지 않는다.** 테마를 바꾸면 `MainWindow::rebuildUi` 가 중앙 위젯을
> 통째로 다시 만들기 때문에, 생성 시점의 값을 받아 표시만 하고 조작은 전부 시그널로
> 넘긴다. 값이 바뀔 때는 탭을 다시 만들지 않고 `setSensorHeight` / `setCameraSummary` /
> `setTopViewDetached` / `setDemoMode` 로 표시만 갱신한다.

### 5.3 경고 배너 (TiltBanner)

IMU 가 허용 오차(±10.0°, §4.3)를 벗어나면 상단에 빨간 배너가 뜬다. 수평으로 돌아오면 자동으로
사라지고, `DISMISS` 로 닫을 수도 있다. 수평 이탈이 **시작될 때만** EVENT LOG 에
한 줄 남긴다(계속 뜨는 동안 로그를 도배하지 않게).

### 5.4 테마

`테마` 메뉴에서 **개발자 모드(다크 · 한화비전 오렌지)** / **사용자 모드(라이트)** 전환.
화면 구성은 같고 색만 바뀐다. Qt 스타일시트는 위젯 생성 시점에 굳어 재적용이 안 되므로,
전환하면 중앙 위젯을 통째로 다시 만든다(`MainWindow::rebuildUi`). 마지막으로 받은
상태값을 즉시 다시 채워 넣어 깜빡임을 없앤다.

### 5.5 스캔 1회 흐름

```
사용자 SCAN 클릭
  → adts/cmd/scan 발행 (req_id 생성)             ─ CALIBRATION 탭으로 자동 전환
  → state/daemon: SCANNING                       ─ STATE 칩·FSM 단계 갱신
  → event/progress ~2Hz                          ─ 진행률 바 · SCAN PTS
  → state/daemon: EXPORT + state/scan (경로)     ─ LAST SCAN RESULT
  → ScanFetcher 가 .pcd 를 가져와 Top-View 에 표시  ─ 2D/3D 점군
  → state/daemon: IDLE
  → (15초 뒤) state/daemon: DISARM                ─ 다음 스캔 전 REARM 필요
```

---

## 6. 스캔 포인트클라우드 (ScanFetcher / ScanCloud)

`state/scan` 은 `.pcd` **경로만** 준다(파일 전달 방식은 계약 §9 미결). 그 경로는 RPi
기준이라 Qt 가 도는 PC 에는 없다. 그래서 `src/ScanFetcher` 가 파일명만 떼어 두 갈래로
찾는다.

1. **로컬 `scans/`** 에 이미 있으면 그대로 읽는다 (개발 중 `scp` 로 받아둔 파일).
   `scans/` 는 gitignore 대상.
2. 없으면 **`GET https://<host>:8443/scan/<파일명>`** 으로 받아온다.

2번을 위해 발급 서비스에 읽기 전용 경로를 추가했다(RPi `broker/enroll_service.c`).
인증서를 발급하는 서비스에 파일 경로를 여는 것이라 세 겹으로 막았다.

- **검증된 클라이언트 인증서 필수.** `/enroll` 은 인증서를 받기 *전에* 부르므로
  인증서를 요구할 수 없다. 그래서 `SSL_VERIFY_PEER` 만 켜고 `FAIL_IF_NO_PEER_CERT` 는
  켜지 않는다 — 핸드셰이크는 누구나 되지만 `/scan` 핸들러가 `SSL_get_verify_result` 를
  직접 확인해 거부한다.
- **파일명만.** `/` 나 `%` 가 하나라도 있으면 400. 디렉터리는 `ADTS_SCAN_DIR` 고정.
- **`.pcd` 확장자만.**

수동으로도 열 수 있다 — `모드 → 스캔 파일 열기… (.pcd)`.

**지원 형식**: `FIELDS x y z`, `DATA ascii` 및 `binary`(float32/64). `binary_compressed`
(LZF)는 지원하지 않고 명확한 에러로 거부한다.

**좌표계** — PCD 원본 프레임은 `+x 오른쪽 / +y 아래 / +z 전방`, 원점은 센서다.
Top-View 는 `+x 오른쪽 / +y 북` 이라 평면 투영은 `(x, z)` 를 그대로 얹으면 된다.
높이는 화면 관례(위가 +)에 맞춰 부호만 뒤집어 **색상에만** 쓰고 좌표에는 반영하지 않는다.
점 색은 높이 기준(낮음=짙은 청색, 높음=밝은 난색)이며, 상태색(Ok/Warn/Danger)과
일부러 다른 계열을 쓴다 — "초록 점 = 정상"으로 읽히면 안 되기 때문이다.

**센서 높이** — `모드 → 센서 높이 설정…` 또는 SETTINGS 탭 (미터로 입력, mm 로 저장,
`QSettings` 에 남아 재실행해도 유지된다). 좌표 계산에는 들어가지 않고 `.pcd` 헤더의
`sensor_height_m` 주석으로만 실린다. 소비자가 바닥평면을 잡거나 다른 좌표계로 옮길 때
쓴다. `0` 은 "모름".

기본값은 **1805mm** 다. 도면상 값을 쓰다가 실측(퍼짐 12mm)으로 바꾼 것이고 **600mm
차이가 났다.** 좌표에는 안 들어가지만 카메라 단이 이 값을 쓰므로 기본값을 실측으로
맞춰뒀다.

---

## 7. 설치·설정

접속에 필요한 것(인증서·브로커 주소·카메라 URL)은 전부 비밀정보라 **저장소에도
배포본에도 들어 있지 않다.** 그래서 사용자와 개발자의 설정 방법이 다르다.

### 7.1 일반 사용자 — 등록 마법사

앱을 처음 실행하면 등록 화면이 뜬다. 한 번만 입력하면 이후에는 묻지 않는다.

| 입력란 | 값 |
|---|---|
| 발급 서버 주소 | RPi IP (예: `172.20.32.110`) |
| 포트 | `8443` |
| 토큰 | 관리자에게 받은 **1회용** 문자열 |
| 기기 이름 | 자동으로 호스트명이 채워진다 — 브로커 로그 구분용 |
| 카메라 IP / 계정 / 비밀번호 | CCTV 접속 정보 |

토큰은 **인증서(스캐너 제어)** 를 받기 위한 것이고 카메라 입력란은 **CCTV 영상**을 위한
것이다. 둘은 서로 무관하다. 카메라 IP 를 비우면 발급 서버가 설정을 갖고 있을 때 그것을
폴백으로 쓰고, 서버에도 없으면 등록은 성공하되 영상이 나오지 않는다(완료 창이 알려준다).

`나중에` 를 누르면 Demo Mode 로 떠서 화면 구성만 볼 수 있다.

받은 파일이 저장되는 위치 — 앱을 지우거나 다시 설치해도 남는다.

| OS | 위치 |
|---|---|
| macOS | `~/Library/Application Support/VEDA4th/SPATIAL-VMS/` |
| Windows | `C:\Users\<사용자>\AppData\Roaming\VEDA4th\SPATIAL-VMS\` |
| Linux | `~/.local/share/VEDA4th/SPATIAL-VMS/` |

**로그아웃** (`모드 → 로그아웃`) 은 이 폴더를 통째로 지우고 앱을 닫는다. 다시 쓰려면
새 토큰이 필요하다. (발급된 인증서 자체의 무효화(CRL)는 아직 없다 — 기기 분실 대응이
필요하면 브로커에 CRL 을 걸어야 한다.)

### 7.2 발급 서버 계약 (RPi 쪽 구현 기준)

```
POST https://<host>:8443/enroll
    {"token": "...", "device_name": "..."}

200 {"cn":"qt-console-<사용자>",
     "ca_crt":"-----BEGIN CERTIFICATE-----\n...",
     "client_crt":"-----BEGIN CERTIFICATE-----\n...",
     "client_key":"-----BEGIN RSA PRIVATE KEY-----\n...",
     "mqtt":{"host":"...","port":8883},
     "cameras":{"channels":{"1":"rtsp://...", ...}}}

400/401/404/500 {"error":"사유"}
```

서버 신원은 실행파일에 박아둔 `resources/ca.crt` 로만 검증한다(시스템 CA 는 쓰지 않는다).
발급 시점에는 클라이언트 인증서가 없어 검증 근거가 이것뿐이다. `ca.crt` 는 **공개**
인증서라 배포본에 들어가도 안전하다 — CA 를 재발급하면 이 파일도 같이 갱신해야 한다.

서버 구현에서 놓치기 쉬운 것:

- **발급할 때마다 브로커 ACL 에 CN 을 추가**해야 한다. mosquitto ACL 은 `user <CN>`
  정확 매칭이라 와일드카드가 없다. 빠뜨리면 인증서는 정상인데 구독·발행이 조용히 막힌다.
- 인증서 서명에 **`-extensions v3_client`** 를 붙인다. 빠지면 mTLS 핸드셰이크에서 거부된다.
- 클라이언트 키는 **전통 RSA 포맷**으로 내려준다. PKCS#8 이면 `QSslKey` 가 null 을
  반환하고 **조용히** 실패한다. (Paho 는 OpenSSL 을 직접 써서 PKCS#8 도 읽는다 —
  그래서 MQTT 는 되는데 8443 만 안 되는 모습이 나온다.)

### 7.3 개발자 — 저장소에서 빌드

```bash
brew install qt paho-mqtt-c paho-mqtt-cpp ffmpeg pkg-config   # macOS
cmake -S . -B build
cmake --build build
./build/spatial_vms.app/Contents/MacOS/spatial_vms
```

개발 트리에서는 등록 마법사를 거치지 않고 **프로젝트 안의 설정 파일**을 쓴다.

```bash
cp config/cameras.example.json config/cameras.json
cp config/mqtt.example.json    config/mqtt.json
```

인증서 3개는 `mqtt.json` 의 `cert_dir`(기본 `certs/`)에 둔다. RPi 의 `/etc/adts/certs/`
에서 받아오면 된다. **두 json 과 `certs/` 는 gitignore 대상이다 — 개인키는 어떤 경우에도
커밋하지 않는다.**

CLion 으로 실행할 때는 working directory 를 프로젝트 루트로 맞춰야 이 파일들을 찾는다.

### 7.4 설정 파일 탐색 순서 (`src/ConfigPath.h`)

1. **현재 작업 디렉터리** 기준 상대경로 — 터미널에서 프로젝트 루트에서 실행할 때
2. **실행파일 위치에서 위로 최대 6단계** — 개발 트리의 `.app` 을 Finder/IDE 로 실행할 때
3. **사용자 데이터 디렉터리** — 배포본

개발 트리를 먼저 보는 이유: 개발 중에는 프로젝트 파일을 고쳐 바로 확인할 수 있어야 하고,
배포본에는 개발 트리가 없어 자연히 3번으로 떨어지기 때문이다. 반대로 하면 개발자가 등록을
한 번 한 뒤로 프로젝트 파일 수정이 조용히 무시돼 헷갈린다.

> ⚠️ **빈 `certs/` 폴더를 배포본 옆에 두면 안 된다.** 실행파일 주변을 사용자 데이터
> 디렉터리보다 먼저 보기 때문에, 빈 `certs/` 가 발급받아 둔 인증서를 가려 **MQTT 가
> 조용히 평문으로 degrade** 된다.

---

## 8. 배포 패키징

번들에 들어가는 의존성: **Qt6 Widgets/Network/OpenGLWidgets + Paho(C·C++) + OpenSSL +
FFmpeg(avformat/avcodec/avutil/swscale)**. `OpenGLWidgets` 는 3D 스캔 뷰를 붙이면서
늘어난 것이라, 그 이전 배포본 절차와 비교하면 Qt 산출물이 더 많다.

| 플랫폼 | 스크립트 | 상태 |
|---|---|---|
| macOS | `scripts/package_macos.sh` → `build/SPATIAL-VMS.dmg` | **검증 완료** (2026-08-14 재확인, Qt 6.11.1 / FFmpeg 8.1.2 / OpenSSL 3.6.3) |
| Windows | `scripts/package_windows.ps1` → `build\SPATIAL-VMS-windows.zip` | **검증 완료** (2026-08-14, vcpkg + MSVC 2022 x64) |

**macOS** 재확인 결과: 번들 안 Mach-O 전체에서 `/opt/homebrew`·`/usr/local` 잔여 참조
0건, `.app` 115MB / `.dmg` 52MB, 인증서·설정 파일 혼입 0건, `env -i` 로 환경변수를
지우고 무관한 디렉터리에서 실행해도 정상 기동.

**Windows** 검증 결과: zip 을 만들어 **Qt/FFmpeg/Paho 가 설치되지 않은 다른 PC 에서
압축을 풀어 실행**하는 것까지 확인했다. 빌드·로컬 실행도 함께 재확인.

> ⚠️ **vcpkg 로 빌드했다면 `-ExtraDllDirs` 를 반드시 붙인다.**
> ```powershell
> .\scripts\package_windows.ps1 -ExtraDllDirs "C:\vcpkg\installed\x64-windows\bin"
> ```
> 스크립트는 DLL 을 `-ExtraDllDirs` → 실행파일 폴더 → `PATH` 순으로 찾는데, vcpkg 의
> `installed\x64-windows\bin` 은 PATH 에 없어서 인자 없이 돌리면 Paho/FFmpeg/OpenSSL
> DLL 을 못 찾는다. 그런데 스크립트는 **중단하지 않고 경고만 남긴 채 zip 을 만들므로**,
> 그 zip 은 다른 PC 에서 실행 직후 DLL 오류로 죽는다. 실제 검증에서도 이 인자가
> 필요했다 — **마지막 경고 목록이 비어 있는지 반드시 확인할 것.**

두 스크립트 모두 산출물에 인증서·설정이 섞이지 않는다. Windows 는 **비밀정보 혼입
검사**를 명시적으로 수행하고(스테이징에 `.key`/`.crt`/`.pem` 이나 `mqtt.json`/
`cameras.json` 이 있으면 중단), macOS 는 `config/`·`certs/` 를 번들 리소스로 넣는 CMake
규칙 자체가 없어 구조적으로 섞이지 않는다. 배포본에 인증서를 담으면 받은 사람 전원이
장비 명령 권한(`adts/cmd/#` 쓰기)과 카메라 admin 비밀번호를 갖게 된다.

**아직 안 해 본 것**: 그 PC 에서 등록 마법사로 실제 발급까지 받아보는 것. 발급
서비스(`/enroll`)가 아직 안 떠 있어서 §12 의 해당 항목이 풀려야 가능하다.

자세한 절차·주의사항(정상적으로 뜨는 ERROR 두 종류, vcpkg 의존성 설치, `PAHO_MQTTPP_IMPORTS`
등)은 저장소 `README.md` 의 "배포용 패키징" 절에 있다.

---

## 9. Demo Mode

`모드 → Demo Mode (브로커 없이 실행)` — **기본 꺼짐.** 다만 **설정이 없는 상태로 앱을
띄우면 자동으로 켜진다** (설정 없이 접속을 걸면 5초마다 재시도만 반복하고 화면은 비어
있어서, 빈 실화면보다 데모가 낫다).

계약서의 실제 세션 흐름을 그대로 재생한다: `cmd/scan` → `SCANNING` → `event/progress`
~2Hz → `EXPORT` + `state/scan` → `IDLE` → 자동 DISARM. IMU 는 주기적으로 드리프트하다
가끔 임계값을 넘겨 TILT 배너를 시연한다.

**RTSP 는 이 토글과 무관하다** — `cameras.json` 이 있으면 데모 모드에서도 실제 영상이
나온다.

---

## 10. 트러블슈팅

| 증상 | 원인 | 조치 |
|---|---|---|
| MQTT `DISCONNECTED` 로 계속 재시도 | 브로커 주소/포트, 또는 인증서 없음 | EVENT LOG 의 `MQTT` 태그 줄을 본다. "인증서 없음 … degraded" 가 보이면 `cert_dir` 문제 |
| 설정은 맞는데 안 붙는다 | 빈 `certs/` 가 실제 인증서를 가림 (§7.4) | 실행파일 주변의 빈 `certs/` 를 지운다 |
| `state/daemon` 이 `"online":false` | 브로커는 살아 있고 **RPi 데몬이 죽은** 것 | RPi 쪽 데몬 확인 |
| 브로커는 붙는데 **스캔 파일만 안 온다** | 8443 TLS 호스트명 검증 실패 (paho 는 verify 가 기본 꺼짐이라 8883 은 안 걸린다) | `mqtt.json` 의 `server_name` (§10.1) |
| 스캔 목록이 `로컬 N건 · 서버 목록 실패` | 아래 §10.2 | |
| 영상이 안 나오고 재시도도 안 한다 | 3회 연속 실패 후 자동 재시도 중단 | `모드 → CCTV 재연결` |
| DISARM 이후 아무 버튼도 안 눌린다 | 정상 동작 | HOME 자리의 `REARM` 을 누른다 (§4.4) |
| IMU 가 계속 `N/A` | `level.valid=false` — 데몬이 아직 IMU 값을 안 보낸다 | 정상 표시. 데몬 쪽 확인 |

브로커에서 직접 들여다보면 어느 구간이 끊겼는지 빨리 갈린다:

```bash
mosquitto_sub -h <RPi IP> -p 8883 \
  --cafile certs/ca.crt --cert certs/qt-console.crt --key certs/qt-console-trad.key \
  -t 'adts/#' -v -i debug-$$      # -i: 앱과 Client ID 가 겹치지 않게
```

### 10.1 TLS 호스트명 (`server_name`)

8443 접속은 `mqtt.json` 의 `host`(보통 DHCP 로 받은 IP)로 하는데, RPi 서버 인증서 SAN
에는 발급 당시의 IP 와 `raspberrypi`/`localhost` 만 들어 있다. 주소가 바뀌면
`The host name did not match any of the valid hosts for this certificate` 로
핸드셰이크가 깨진다.

그래서 `server_name`(기본 `raspberrypi`)으로 **검증할 호스트명만** 인증서상의 이름에
맞춘다. 사설 CA 체인 검증과 mTLS 는 그대로다. 서버 인증서를 현재 주소로 재발급했다면
`""` 로 두면 `host` 검증으로 돌아간다.

### 10.2 스캔 목록이 안 뜰 때 (대개 RPi 쪽)

| 문구에 붙는 사유 | 뜻 | 조치 |
|---|---|---|
| `SSL handshake failed: The host name did not match…` | 인증서 SAN 불일치 | §10.1 |
| `HTTP 404` + `없는 경로입니다` | 발급 서비스에 `/scans` 라우트가 없다 — 옛 바이너리 | RPi `develop` 로 `adts_enroll` 재빌드·재배포 |
| `HTTP 404` + `스캔 디렉터리가 없습니다` | `ADTS_SCAN_DIR` 을 서비스가 못 읽는다 | 아래 |

마지막 건이 헷갈린다. 유닛(`broker/adts-enroll.service`)에 `ProtectHome=true` 가 걸려
있어 **`/home` 아래는 경로가 맞아도 못 읽는다.** 데몬은 `/var/lib/adts/scans` 를 1순위로
쓰지만 그 디렉터리가 없으면 작업 디렉터리의 `./scans`(= 홈 아래)로 조용히 폴백하므로,
이 상태가 되면 **파일은 쌓이는데 서비스는 하나도 못 본다.** `/var/lib/adts/scans` 를
`pi` 소유로 만들어 두면 양쪽이 같은 곳을 본다.

---

## 11. 소스 구조

```
src/
├── main.cpp / MainWindow      # 5탭 셸, 시그널 배선, Demo/Live 전환, 메뉴(카메라·센서높이·로그아웃)
├── ConfigPath.h               # 설정 파일 탐색 (개발 트리 → 사용자 데이터 디렉터리)
├── CameraConfig.h             # PNM 시리즈 RTSP URL 조립 (센서 0~3 → CH1~4)
├── EnrollDialog               # 최초 실행 등록 마법사 (1회용 토큰 → 인증서·설정 발급)
├── Theme.h / Models.h         # 디자인 토큰(다크/라이트), 계약 스키마 구조체
├── DataBridge / MqttBridge / DemoBridge     # 공용 시그널 인터페이스 + 실장비/데모 구현
├── RtspDecoder / RtspSource                 # 채널별 FFmpeg 디코딩 + config 로더
├── ScanFetcher / ScanCloud / ScanView3D     # .pcd 수신 · PCD 파서 · OpenGL 3D 뷰
├── TopBar / TiltBanner / StatusBar          # 상단 명령바 / 수평이탈 배너 / 하단 상태바
├── CameraTile / TopViewWidget / TopViewPanel # 대시보드 좌(CCTV) / 우(Top-View)
└── CalibrationTab / DevicesTab / EventLogTab / SettingsTab # 나머지 4개 탭

config/   cameras.example.json · mqtt.example.json   (실제 파일은 gitignore)
certs/    개발용 인증서 — 통째로 gitignore
resources/ ca.crt(실행파일 내장) · AppIcon.icns/.ico · app.rc
scripts/  package_macos.sh · package_windows.ps1 · gen_app_icon.cpp
scans/    개발 중 받아둔 .pcd — gitignore
```

---

## 12. 알려진 제약 / 협의 대기

| 항목 | 상태 | 담당·비고 |
|---|---|---|
| `cmd/rearm` 토픽 | **구현·동작 확인됨**, 계약 문서에는 없음 | 계약 반영은 **이현우** 협의 (§4.4) |
| 토픽의 `kit1` 세그먼트 | 계약서와 실구현이 다름 — 앱은 실구현을 따름 | 재확정 시 `MqttBridge.cpp` 상수 수정 |
| `state/scan` 필드 누락 | 계약 §3.4 중 7개 필드가 안 옴 | UI 는 `—` 로 표시. 데몬이 채우면 코드 변경 없이 표시됨 |
| 카메라 단 캘리브 결과(NCC/edge_rmse/extrinsic) | **발행 토픽 미정** | **이영민** 협의. 정해지면 CALIBRATION 탭에 QUALITY 패널 추가 |
| WiseAI 객체 실좌표 | **발행 토픽 미정** | 위와 동일. 지금은 TOP-VIEW 에 자리만 있음 |
| 포인트클라우드 전달 방식 | 8443 `GET /scan/<파일명>` 으로 구현했으나 계약 §9 는 여전히 미결 | 이 방식으로 확정하면 계약서도 고쳐야 함 |
| 벽/기둥 에지 추출 | 미구현 — 점을 그대로 찍을 뿐 선분을 뽑지 않는다 | |
| 발급 서비스 `/enroll` | **RPi 쪽 미기동** — 클라이언트는 §7.2 계약대로 준비돼 있다 | **송영빈**. 이게 떠야 새 PC 에서 등록 마법사 → 인증서 발급 → MQTT/RTSP 연결까지의 실사용 흐름을 한 번도 안 끊고 검증할 수 있다 |
| 인증서 무효화(CRL) | 없음 | 기기 분실 대응이 필요하면 브로커에 CRL |

---

## 13. 이 문서가 따르는 것

- **MQTT 인터페이스 계약** (데몬=이현우 / Qt=송영빈 / 브로커·인증서=이현우·송영빈) — 이 앱의
  MQTT 부분은 전적으로 이 계약을 따른다. 토픽·페이로드·QoS·retain 을 바꾸려면 계약을 먼저
  고쳐야 한다. **이 문서가 의존하는 부분은 §4.1·§4.3 에 값째로 옮겨 적었고, 실구현이 계약과
  다른 두 지점(`kit_id` 세그먼트 없음 / `state/scan` 필드 부족)도 거기 명시했다.**
- **`shared/protocol.h` v6** — STM32 가 올리는 오류 코드(1~6), 오류 축 비트, `CMD_STATUS`
  진단 카운터의 출처. Qt 는 데몬을 거쳐 받으므로 직접 읽지는 않는다.
- **카메라 단 캘리브 결과 스키마** — 이 MQTT 계약과는 별개다. 발행 토픽이 아직 정해지지
  않았고, 정해지면 CALIBRATION 탭에 QUALITY 패널을 붙인다(§12).
