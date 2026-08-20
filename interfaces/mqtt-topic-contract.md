# MQTT 토픽 계약 — Qt 관제 ↔ RPi 스캐너 데몬

> **원본**: [MQTT 토픽 계약 (Confluence, 팀 내부)](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383)
> **이 사본**: 2026-08-21 기준 스냅샷 · 계약 버전 **v1.4** · 현행 구현 대조 2026-08-19
> (`RPi main/7b347a4` + `STM32 main/003e483` + `Qt main/5888153`)

**이 문서는 계약서다.** Qt 쪽은 이 문서만 보고 구현할 수 있어야 하고, 데몬 쪽은 여기
적힌 것만 발행·구독한다. 바꾸려면 양쪽 합의 후 이 문서를 먼저 고친다.

데몬 담당: 이현우 · Qt 담당: 송영빈 · 브로커/인증서: 이광진

**데몬측·Qt측 모두 구현 완료.** mTLS end-to-end 검증 완료 — 인증서 없는 접속 거부 /
명령 수신 / FSM 트리거 / 진행률 발행 / 중복 `req_id` 무시 / LWT 발동. 스캔 완주 +
카메라 mTLS 업로드까지 실기 확인.

## 1. 연결 정보

| 항목 | 값 | 비고 |
|---|---|---|
| 브로커 | Mosquitto (RPi 상주) | 킷 자체가 통신 허브 |
| 포트 | **8883** (MQTT over TLS) | 평문 1883은 외부에 열지 않음 |
| 인증 | **mTLS** (클라이언트 인증서) | §6 |
| MQTT 버전 | 3.1.1 | libmosquitto / QtMqtt 기본 |
| Keepalive | 30초 | LWT 발동 시간에 영향 |
| Client ID | `qt-console` | 중복되면 서로 끊는다 (데몬은 `adts-daemon`) |
| 파일 전송 | **8443** (HTTPS, 같은 mTLS 인증서) | §3.4 |

## 2. 토픽 일람

구조: `adts/<class>/<name>`

| 토픽 | 방향 | QoS | Retained | 내용 |
|---|---|---|---|---|
| `adts/cmd/scan` | Qt → 데몬 | 1 | **금지** | 스캔 시작 |
| `adts/cmd/stop` | Qt → 데몬 | 1 | 금지 | 스캔 중단 |
| `adts/cmd/home` | Qt → 데몬 | 1 | 금지 | 홈만 수행 (**축이 움직인다**) |
| `adts/cmd/disarm` | Qt → 데몬 | 1 | 금지 | 안전정지 (모터 전류 차단) |
| `adts/cmd/rearm` | Qt → 데몬 | 1 | 금지 | DISARM 해제 |
| `adts/state/daemon` | 데몬 → Qt | 1 | **예** | FSM·링크·홈·현재각·수평·진단 (LWT 대상) |
| `adts/state/scan` | 데몬 → Qt | 1 | **예** | 마지막 스캔 결과 (파일 경로) |
| `adts/event/progress` | 데몬 → Qt | 0 | 아니오 | 진행률 (스캔 중 약 2Hz) |
| `adts/event/error` | 데몬 → Qt | 1 | 아니오 | 오류 발생 |

**Qt 구독**: `adts/state/#` + `adts/event/#` 두 줄. **Qt 발행**: `adts/cmd/*` 만.

### kit id 계층을 두지 않는 이유 (v1.0의 `adts/kit1/...`에서 변경)

브로커가 킷마다 상주하므로 그 브로커 위의 모든 토픽은 이미 그 킷 것이다 — kit id는
중복 정보다. 나중에 여러 킷을 중앙 브로커로 모으더라도 Mosquitto 브리지가 접두사를
붙여줄 수 있어 **클라이언트 코드를 한 줄도 고치지 않고** 확장된다.

```
connection central
address central-broker:8883
topic # out 0 "" "adts/kit1/"
```

### ⚠️ cmd 토픽에 retained를 절대 걸지 말 것 (안전 문제)

retained된 `cmd/scan`은 데몬이 재접속할 때마다 다시 배달된다. 전원을 껐다 켜거나 데몬을
재시작할 때마다 **킷이 혼자 스캔을 시작한다.** 사람 손이 기구에 들어가 있을 수 있으므로
단순 버그가 아니라 안전 사고다.

QtMqtt: `publish(topic, payload, 1, false)` — 네 번째 인자가 retain. **반드시 false.**

## 3. 페이로드 규격

전부 UTF-8 JSON. 모르는 필드는 무시할 것(전방 호환). 데몬은 cJSON으로 파싱한다.

### 3.1 `cmd/scan` — 스캔 시작

```json
{
  "req_id": "a1b2c3d4",
  "pan_ddeg":  [0, 1791],
  "tilt_ddeg": [-900, 900],
  "step_ddeg": 9,
  "sensor_height_mm": 1805
}
```

| 필드 | 타입 | 범위 | 필수 | 설명 |
|---|---|---|---|---|
| `req_id` | string | 1~32자 | 권장 | Qt가 생성. 결과 대조용 (§4) |
| `pan_ddeg` | [int,int] | 0~3599 | 예 | 0.1도 단위 `[시작,끝]` |
| `tilt_ddeg` | [int,int] | −900~900 | 예 | 0.1도 단위, 부호 있음 |
| `step_ddeg` | int | **1~3600** | 예 | 격자 간격. **9 (=0.9도) 권장** |
| `sensor_height_mm` | int | 0 이상 | 아니오 | 지면→**회전축 교점**. 좌표엔 미적용 |

필수 필드가 없거나 형식이 틀리면 `104 ERR_BAD_REQUEST`를 발행한다.

**⚠️ 스캔 중에 보내면 즉시 거절된다 (v1.4).** `106 ERR_BUSY`가 온다. 예전에는 요청이
큐에 남아 있다가 스캔이 끝나는 순간 새 스캔이 자동으로 시작됐다 — 14분짜리라 조작자가
의도한 적 없는 동작이고 화면에 이유도 안 나왔다. DISARM 상태에서 보내도 마찬가지로
거절된다(먼저 `cmd/rearm`).

**⚠️ `sensor_height_mm`은 지면에서 팬/틸트 축이 만나는 지점까지다.** 산출물의 원점
`(0,0,0)`과 같은 지점이며, 라이다 발광면은 축에서 84mm 더 나가 있고 그건
`range_offset_m`이 따로 담당한다. **천장 높이가 아니다.**

**⚠️ 팬 끝각은 `step`에 따라 달라진다** — 한 바퀴를 딱 채워야 한다.

틸트 스윕이 바닥을 지나면서 한 줄이 방위 *p*와 *p+180*을 함께 훑는다. 그래서 팬을
0~180 양끝 포함으로 돌리면 첫 줄과 마지막 줄이 **같은 수직 평면**을 잡아 방위 0도와
180도만 두 번 측정된다.

| `step_ddeg` | 팬 끝각 | 줄 수 | 격자 |
|---|---|---|---|
| 10 (1.0°) | **1790** | 180 | 91 × 360 |
| **9 (0.9°)** | **1791** | 200 | **101 × 400** |

**⚠️ 0.9도는 모터 분해능이 아니라 샘플 간격에 맞춘 값이다.** 1.0도로 잡으면 샘플과
어긋나 **빈 셀과 중복이 동시에** 생긴다(실측 365 / 2,789건).

**UI 기본값 권장**: `pan [0,1791] / tilt [-900,900] / step 9 / height 1805`
→ 격자 101×400, 약 14분 소요. 데몬의 `SCAN_DEF_*` 상수와 같다.

### 3.2 `cmd/stop` / `cmd/home` / `cmd/disarm` / `cmd/rearm`

```json
{ "req_id": "e5f6g7h8" }
```

| 명령 | 동작 | 언제 쓰나 |
|---|---|---|
| `stop` | 스캔 중단. **여기까지 받은 점으로 파일을 마감한다** | 중간에 끊고 싶을 때 |
| `home` | 홈 수행. **⚠️ 축이 실제로 움직인다** | 설치·정비 때. 스캔 전에는 불필요 |
| `disarm` | 즉시 정지 + 모터 전류 차단 | 비상. **UI에 항상 보이는 버튼으로** |
| `rearm` | **DISARM 해제 → IDLE 복귀** | DISARM 후 다시 쓰려면 **반드시 필요** |

**⚠️ `cmd/home`은 "구동 없음, 엔코더 판독 1회"가 아니다.** 지금은 ① 엔코더를 읽어
현재 위치를 확정하고 ② **양축을 기구각 0(홈 자세)으로 이동**시킨 뒤 ③ 도달·정착을
확인하고, 오차가 0.3도를 넘으면 **최대 10회 세부조정**한다. 최악의 경우 **팬 180도
이동(≈8초) + 정착(3초)**. Qt는 즉시 끝난다고 가정하면 안 되고, `state/daemon`의
`homed`로 완료를 판정해야 한다.

**⚠️ `homed`는 절차가 끝났을 때만 참이다 (v1.4).** 엔코더 판독만 되고 자세 이동이
남아 있으면 아직 거짓이다. 이 구분이 없어서 실기에서 홈이 끝나기 전에 스캔이 나갔고
`ERR_BUSY`로 거절됐다.

**⚠️ `disarm`과 `rearm`은 대칭이 아니다.**

| | `disarm` | `rearm` |
|---|---|---|
| STM32에 명령 | **보냄** (`CMD_DISARM`) | **안 보냄** |
| 모터 전류 | 끊는다 | **안 켠다** (다음 명령 때 STM32가 스스로) |
| 진행 중 스캔 | 중단 + **파일 마감** | — |
| 대기 중 요청 | 그대로 | **버린다** |
| 어느 상태에서 | **어디서든** | **DISARM에서만** |
| 거부 조건 | 없음 | 링크가 죽어 있으면 거부 |

`rearm`은 **데몬 잠금 해제일 뿐** 아직 아무것도 움직이지 않는다. 전류는 다음
`cmd/scan`·`cmd/home`이 들어올 때 STM32가 `motor_enable()`로 켠다.

`rearm`이 대기 요청을 버리는 이유: DISARM 직전에 들어와 있던 스캔 요청을 그대로 두면
**복구하자마자 시키지도 않은 스캔이 시작된다.** 비상정지를 누른 사람이 가장 원하지
않는 동작이다.

### 3.3 `state/daemon` — 데몬 상태 (retained)

```json
{
  "state": "SCANNING",
  "online": true,
  "link_alive": true,
  "homed": true,
  "scanning": true,
  "cur_pan_ddeg": 450,
  "cur_tilt_ddeg": -230,
  "last_err": 0,
  "last_err_axis": 0,
  "diag": { "valid": true, "tx_fail": 0, "rx_ovf": 0,
            "enc_retry": 0, "lidar_drop": 0, "reject_busy": 0 },
  "level": { "valid": true, "roll_deg": 0.58, "pitch_deg": -0.91,
             "raw_roll_deg": 3.58, "raw_pitch_deg": -4.91 },
  "ts": 1785500123
}
```

| 필드 | 값 | UI 활용 |
|---|---|---|
| `state` | `IDLE`/`SCANNING`/`EXPORT`/`DISARM`/`OFFLINE` | 메인 상태 표시 (§5) |
| `online` | bool | `false` = LWT로 브로커가 대신 보낸 것 = 데몬 죽음 |
| `link_alive` | bool | RPi↔STM32 링크. false면 하드웨어 문제 |
| `homed` | bool | **홈 절차 완료** 여부 |
| `cur_pan_ddeg` / `cur_tilt_ddeg` | int (0.1도) | 현재 각도. **기구각**이다 (§7) |
| `last_err` | int | 0=정상. 코드표는 §3.5 |
| `last_err_axis` | int | 0=축무관 / 1=팬 / 2=틸트 / 3=양축 (비트 플래그) |
| `ts` | int (unix sec) | 발행 시각 |

**발행 시점**: 상태 전이 즉시 + 무변화여도 5초마다(생존 신호 겸용).

#### `diag` — STM32 진단 카운터 (v1.4 신설)

STM32 펌웨어가 `CMD_STATUS`로 **1초마다** 올리는 누적 카운터다. 부팅 이후 누적이고
65535에서 포화한다.

| 필드 | 0이 아니면 |
|---|---|
| `tx_fail` | STM32의 UART 송신 실패. 상행 프레임이 유실됐다는 뜻이라 스캔 점 수가 실제보다 적을 수 있다 |
| `rx_ovf` | 수신 링버퍼 오버플로. **STM32 메인루프가 오래 막혔다**는 뜻 (256B = 하행 프레임 20개분) |
| `enc_retry` | 엔코더 I2C 판독 재시도(양축 합). 계속 오르면 배선 접촉 의심 |
| `lidar_drop` | 라이다 큐가 차서 버린 샘플. 격자에 빈 셀로 남는다 |
| `reject_busy` | 진행 중이라 거절한 `SCAN_START`. 조작자가 중복으로 눌렀다는 뜻 |

**⚠️ `valid`가 false면 나머지 값은 "모른다"이지 "정상"이 아니다.** STM32에 구버전
펌웨어가 올라가 있거나 아직 첫 주기가 안 온 것이다. **0을 그대로 초록불로 그리면 안 된다.**

> 이 카운터들은 펌웨어 안에서 오래 전부터 세고 있었지만 읽을 방법이 없었다. proto v6에서
> `CMD_STATUS`를 실제로 송신하기 시작하면서 처음으로 관측 가능해졌다.

#### `level` — IMU 수평

IMU는 **ICM-20948**(`/dev/imu`, 주소 0x69)다. v1.2의 "MPU-6050"은 2026-08-13에 교체됐다.

- `roll_deg`/`pitch_deg` = **설치각 오프셋을 뺀 값**. 게이트 판정과 Qt 표시가 둘 다 이걸 쓴다
- `raw_roll_deg`/`raw_pitch_deg` = 오프셋 적용 전 원본
- 임계를 넘으면 **데몬이** `cmd/scan`을 거부하고 `102 ERR_NOT_LEVEL`을 발행한다

**⚠️ 지금 이 값을 신뢰하면 안 된다.** 설치각 오프셋을 **킷이 3.6도 기울어진 상태에서**
잡아버려서, 보정이 기울기를 줄이는 게 아니라 키우는 상태다. 그래서 데몬측 게이트 임계가
브링업용으로 크게 열려 있다(2026-08-19 기준 10.0도). 킷을 바닥평면 기준으로 바로 세운
뒤 오프셋을 다시 재야 이 값이 의미를 갖는다.

**⚠️ Qt의 경고 임계(1.5도)와 데몬의 거부 임계(10.0도)는 일부러 다르다.** 전자는 "화면에
경고를 띄울 기준", 후자는 "스캔을 거부할 기준"이라 용도가 다르다. **화면에 배너가 뜨는데
스캔은 그냥 도는 것이 지금은 정상이다** — 버그로 오해하지 말 것.

### 3.4 `state/scan` — 스캔 결과 (retained)

```json
{
  "req_id": "a1b2c3d4",
  "ok": true,
  "pcd": "/var/lib/adts/scans/calib-20260811-091522_sweep-000001.pcd",
  "points": 40342,
  "stm_reported": 41255,
  "ts": 1785500428
}
```

`points` = 격자에 배치된 유효 점 수, `stm_reported` = STM32가 `CMD_SCAN_DONE`으로
보고한 총 상행 점 수. 둘의 차이가 중복·범위밖으로 버려진 양이다.

**⚠️ `ok`가 이제 실제 파일 기록 성공을 반영한다 (v1.4).** 예전에는 격자를 다 채웠으면
무조건 `true`라, 권한이나 디스크 문제로 파일을 못 써도 성공이 나갔다. 지금은 `fclose`
결과까지 확인하고, 실패하면 `ok:false`와 함께 `105 ERR_EXPORT_FAIL`이 발행된다.

**포인트클라우드 파일 자체는 MQTT로 오지 않는다.** JSON이 25MB, PCD가 0.9MB라 브로커에
부담이고 페이로드 한계에도 걸린다. **경로만** 온다.

**파일 전달 = HTTPS 8443.** 인증서 발급 서비스(`enroll_service`)가 같은 포트에서 스캔
파일도 서빙한다. **브로커(8883)와 같은 mTLS 인증서를 쓰므로 Qt는 이미 가진 파일 3개로
그대로 접속된다.**

| 요청 | 응답 |
|---|---|
| `GET https://<rpi>:8443/scans` | 스캔 파일 목록 (JSON) |
| `GET https://<rpi>:8443/scan/<파일명>` | 파일 본문 |

서빙 경로는 `/var/lib/adts/scans` (`ADTS_SCAN_DIR`로 변경 가능).

⚠️ 서버 인증서가 `CN=raspberrypi`로 발급되므로, IP로 접속할 때 TLS 호스트명 검증용
이름을 따로 지정해야 한다(Qt `ScanFetcher` 참조).

> 카메라 단으로 가는 **원시 측정 JSON**은 이 경로가 아니라 별도 mTLS TCP **2222**로
> 데몬이 직접 올린다. 이 계약 밖이다.

### 3.5 `event/error`

```json
{ "req_id": "a1b2c3d4", "code": 8, "name": "STM_ERROR",
  "msg": "STM32 오류 통지", "fatal": true, "axis": 1, "ts": 1785500130 }
```

**code로 출처가 갈린다** — `< 100`은 STM32가 `CMD_ERROR`로 올린 것, `>= 100`은 데몬
자신의 판정이다. 이 경계가 있기 전에는 `4` 하나가 세 뜻으로 쓰여서, Qt가 `code=4`를
받고도 STM이 거절한 건지 데몬이 페이로드를 못 읽은 건지 알 수 없었다.

#### STM32 오류 (`code < 100`)

| code | 의미 | `fatal` |
|---|---|---|
| 1 | `ERR_BAD_CRC` — 프레임 손상 | false |
| 2 | `ERR_BAD_LEN` — 길이 이상 | false |
| 3 | `ERR_NOT_HOMED` — 홈 전 스캔 요청 | **true** |
| 4 | `ERR_OUT_OF_RANGE` — 스캔 범위·격자가 유효 범위 밖 | false |
| 5 | `ERR_STALL` — 홈이 허용 오차 안에 수렴 못 함 | **true** |
| 6 | `ERR_LIDAR` — 라이다 무응답 | **true** |
| **7** | `ERR_BUSY` — 진행 중이라 요청을 받을 수 없다 (v1.4) | false |
| **8** | `ERR_ENCODER` — 엔코더 판독 실패 (I2C) (v1.4) | **true** |

⚠️ STM32에서 올라온 오류는 `name`이 전부 `STM_ERROR`다. 구분은 `code`로 한다.

#### 데몬 자체 판정 (`code >= 100`)

| code | name | 의미 | `fatal` |
|---|---|---|---|
| 100 | `ERR_DISARM` | 링크 두절 또는 STM32 오류로 안전정지 | **true** |
| 100 | `USER_DISARM` | **사용자가 누른** 안전정지 | **true** |
| 101 | `ERR_HOME_TIMEOUT` | 홈 무응답으로 요청 취소 | **true** |
| 102 | `ERR_NOT_LEVEL` | 수평 게이트가 스캔을 거부 | **true** |
| 103 | `ERR_UPLOAD` | 카메라 업로드 실패 (**파일은 로컬에 남는다**) | false |
| 104 | `ERR_BAD_REQUEST` | cmd 페이로드 필드 누락/형식 오류 | false |
| **105** | `ERR_EXPORT` | **산출물 기록 실패 — 측정값 복구 불가** (v1.4) | **true** |
| **106** | `ERR_BUSY` | 지금 상태에서 받을 수 없는 요청 (v1.4) | false |

**⚠️ 103과 105를 혼동하지 말 것.** 103은 파일이 로컬에 남아 있어 나중에 손으로 올릴 수
있지만, **105는 측정값 자체가 사라진 것**이라 복구 수단이 없다. 14분을 다시 돌려야 한다.

#### `axis` 필드 (v1.4 신설)

오류가 난 축이다. **STM32 오류에만 의미가 있고 데몬 자체 판정(100번대)은 항상 0**이다.
0=축무관 / 1=팬 / 2=틸트 / 3=둘 다 (비트 플래그).

> **왜 생겼나**: 이 필드가 없던 시절에는 홈 실패 시 어느 축인지 알려고 **다른 오류코드를
> 빌려 썼다**(`4`=팬, `6`=틸트). 축이 정식 필드가 되면서 4·6은 다시 본래 의미로만 쓰인다.

**어느 배선을 볼지가 곧 이 값이다.** UI에서 오류를 표시할 때 함께 보여주면 진단이 빨라진다.

#### `fatal` 필드

**정의가 "하드웨어가 고장났나"가 아니라 "화면을 어떻게 그릴까"다.** 그게 이 플래그를
쓰는 쪽이 실제로 묻는 질문이기 때문이다.

| 값 | 뜻 | UI 권장 |
|---|---|---|
| `true` | 작업이 멈췄고 **사용자가 개입해야** 다시 나간다 | 배너·모달. 조작을 막고 사용자를 부른다 |
| `false` | 계속되거나 다시 시도하면 된다 | 로그 한 줄 |

`USER_DISARM`은 장비가 고장난 건 아니지만 **REARM 전까지 스캔이 안 나가므로** `fatal`이다.

#### DISARM 발행 정책

**⚠️ 자동 DISARM에는 오류가 오지 않는다.** 예전에는 `DISARM` 전이를 무조건 오류로
발행했다. 그런데 스캔 후 자동 DISARM(§5)이 생기면서 **성공한 스캔마다** `code 100`이
하나씩 쌓였다. 오류 로그가 정상 동작으로 가득 차면 진짜 오류를 못 찾는다.

| 사유 | 발행 |
|---|---|
| 링크 두절 | `100 ERR_DISARM` "링크 두절 — 배선/전원 확인" `fatal` |
| STM32 오류 | `100 ERR_DISARM` "STM32 오류로 안전정지" `fatal` |
| 사용자가 `cmd/disarm` | `100 USER_DISARM` "사용자 안전정지" `fatal` |
| **스캔 후 자동** | **발행 안 함** (`state/daemon` 전이만) |

### 3.6 `event/progress`

```json
{ "req_id": "a1b2c3d4", "points": 12345, "expected": 40200,
  "percent": 38, "ts": 1785500250 }
```

스캔 중 약 2Hz(500ms). **QoS 0이라 유실될 수 있다** — 진행바 갱신용으로만 쓰고, 완료
판정은 `state/daemon`의 `state`로 할 것.

**⚠️ `expected`는 어림값이다 — `percent`가 100을 넘을 수 있다.** Qt는 0~100으로 clamp할 것.

| 숫자 | 뜻 | 실측 예 |
|---|---|---|
| 격자 셀 | 고각 행 × 방위 열(항상 360도) | 101 × 400 = **40,400** |
| `expected` | 팬 줄 × 틸트 스텝 | 200 × 201 = **40,200** |
| 실제 수신 샘플 | 연속 스윕이라 격자점에 안 맞음 | **41,255** |
| 채워진 셀 | 반올림 배정 결과 | **40,355** |

## 4. `req_id` 규칙

- Qt가 명령마다 **새로 생성**한다 (UUID 앞 8자 등, 재사용 금지)
- 데몬은 그 요청에서 파생된 모든 응답(`progress`/`state/scan`/`error`)에 **같은 값을 되돌려준다**
- Qt는 자기가 보낸 `req_id`가 아닌 응답은 **무시**할 것 — 다른 콘솔이 붙어 있을 수 있다

**왜 필요한가**: 스캔이 14분 걸린다. 그 사이 다른 클라이언트가 명령을 넣거나, QoS 1
특성상 같은 명령이 **중복 배달**될 수 있다.

**⚠️ 중복 제거 규칙이 바뀌었다 (v1.4).** 두 가지가 안전 명령을 삼키고 있었다.

| | 이전 | 지금 |
|---|---|---|
| 기억 범위 | **전역 하나** — `cmd/home`을 `"x"`로 보낸 뒤 `cmd/scan`을 같은 `"x"`로 보내면 스캔이 사라졌다 | **토픽별로** 기억한다 |
| id 없을 때 | 전부 `"-"`로 대체돼 **두 번째 무-id 명령부터 자기 자신과 충돌**했다 | **중복 판정을 하지 않는다 — 항상 실행** |

정지·안전정지는 두 번 실행돼도 해롭지 않지만 **한 번 안 되면 위험하다.**

## 5. 상태 머신 — Qt UI 매핑

```mermaid
stateDiagram-v2
    [*] --> OFFLINE
    OFFLINE --> IDLE : 데몬 접속
    IDLE --> SCANNING : cmd/scan (홈 자동 수행 + 수평 게이트 통과)
    SCANNING --> EXPORT : 스캔 완료
    SCANNING --> EXPORT : cmd/stop
    EXPORT --> IDLE : 파일 산출 완료
    IDLE --> DISARM : 스캔 후 15초 (자동, 오류 아님)
    IDLE --> DISARM : cmd/disarm 또는 링크 두절
    SCANNING --> DISARM : cmd/disarm 또는 오류
    DISARM --> IDLE : cmd/rearm
    IDLE --> OFFLINE : 데몬 종료 (LWT)
```

| state | 의미 | 버튼 활성 | 표시 |
|---|---|---|---|
| `OFFLINE` | 데몬 미접속 / 죽음 | 없음 | 회색 "연결 안 됨" |
| `IDLE` | 대기 — 스캔 가능 | **스캔 시작**, 홈 | 초록 "준비" |
| `SCANNING` | 스캔 중 | **중단**, 비상정지 | 진행바 + 남은 시간 |
| `EXPORT` | 파일 저장 중 (수 초) | 없음 | "저장 중..." |
| `DISARM` | 모터 전류 차단 | **REARM**, 비상정지 | — |

**⚠️ `SCANNING`·`DISARM`에서 보낸 `cmd/scan`은 큐에 쌓이지 않는다 (v1.4).** 그 자리에서
`106 ERR_BUSY`로 거절된다. UI는 그 상태에서 스캔 버튼을 비활성으로 두는 편이 낫다.

**⚠️ 스캔이 끝나면 자동으로 DISARM이 된다 — 정상 동작이다.** `EXPORT` → `IDLE`로
돌아온 뒤 **15초가 지나면 데몬이 스스로** `DISARM`으로 간다. 이유는 STM32가
`SCAN_DONE`을 보낸 **뒤에** 양축을 홈 자세로 되돌리기 때문이다. 그 되감기가 끝날 시간을
준 다음 전류를 끊어, 스텝 모터가 정지 상태에서 계속 여자되어 발열하는 것을 막는다.

```
스캔 완료 → (15초) → DISARM → [REARM 버튼] → IDLE → 스캔 시작 가능
```

⚠️ 15초는 **되감기 실측 전까지의 잠정치**다. 프로토콜에 "되감기 완료" 통지가 없어
시간으로 때우고 있다. 짧으면 되감기가 끊기고, 길면 그동안 스텝이 여자된 채 남는다.

### 5.1 정상 시퀀스

```mermaid
sequenceDiagram
    autonumber
    participant Q as Qt 관제
    participant B as Mosquitto
    participant D as 스캐너 데몬

    Note over Q,D: 접속 직후 — retained 로 현재 상태를 즉시 받음
    Q->>B: subscribe adts/state/# , adts/event/#
    B-->>Q: state/daemon (retained)
    B-->>Q: state/scan (retained) 이전 스캔 결과

    Q->>B: cmd/scan {"req_id":"a1b2",...}
    B->>D: 전달
    Note over D: 홈 자동 수행 (축 이동, 최대 11초)
    Note over D: 수평 게이트 검사
    D->>B: state/daemon {"state":"SCANNING"}

    loop 약 14분, 2Hz
        D->>B: event/progress {"percent":38,...}
    end

    D->>B: state/daemon {"state":"EXPORT"}
    D->>B: state/scan {"req_id":"a1b2","ok":true,"pcd":"..."}
    D->>B: state/daemon {"state":"IDLE"}

    Note over Q: HTTPS 8443 으로 .pcd 내려받기
    Q->>D: GET /scan/<파일명>

    Note over D: 15초 후 — 되감기 완료 여유 (오류 발행 없음)
    D->>B: state/daemon {"state":"DISARM"}
    Q->>B: cmd/rearm
    D->>B: state/daemon {"state":"IDLE"}
```

### 5.2 데몬이 죽었을 때 (LWT)

데몬은 접속 시 **Last Will**을 등록한다. 프로세스가 죽거나 RPi 전원이 나가면 브로커가
대신 발행한다:

```json
{ "state": "OFFLINE", "online": false, "ts": 1785500551 }
```

retained + QoS 1. 정상 종료 시에는 LWT가 발동하지 않으므로 데몬이 직접 같은 내용을 남긴다.

**Qt는 이걸 반드시 처리해야 한다.** 없으면 데몬이 죽어도 화면에 `IDLE`이 그대로 남아
있어, 조작자가 "준비됨"으로 착각하고 버튼을 누르게 된다.

## 6. TLS / mTLS

포트 8883은 **MQTTS이자 mTLS**다 — 브로커가 클라이언트 인증서를 요구한다
(`require_certificate true`). 파일 전송용 8443도 **같은 인증서**를 쓴다.

### 6.1 Qt에 필요한 파일 3개

| 파일 | 용도 |
|---|---|
| `ca.crt` | 브로커 인증서 검증용 (우리 CA) |
| `qt-console.crt` | Qt 자신의 인증서. **CN = `qt-console`** (ACL 신원) |
| `qt-console.key` | Qt 자신의 개인키. **절대 저장소에 커밋하지 말 것** |

`ca.key`는 RPi에만 있고 배포되지 않는다. 발급은 이광진.

### 6.2 QtMqtt 코드

```cpp
QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
ssl.setCaCertificates(QSslCertificate::fromPath("certs/ca.crt"));

QFile cf("certs/qt-console.crt"); cf.open(QIODevice::ReadOnly);
ssl.setLocalCertificate(QSslCertificate(&cf, QSsl::Pem));

QFile kf("certs/qt-console.key"); kf.open(QIODevice::ReadOnly);
QSslKey key(&kf, QSsl::Rsa, QSsl::Pem);
if (key.isNull()) qFatal("개인키 로드 실패 — 포맷 확인");   // §6.3 ②
ssl.setPrivateKey(key);

ssl.setPeerVerifyMode(QSslSocket::VerifyPeer);
ssl.setProtocol(QSsl::TlsV1_2OrLater);

client->setHostname("10.144.31.125");
client->setPort(8883);
client->connectToHostEncrypted(ssl);
```

데몬측 `mosquitto_tls_set(mosq, ca, NULL, cert, key, NULL)`과 인자가 1:1 대응한다.

### 6.3 Windows 함정 3개

**① OpenSSL DLL 누락 — 가장 많이 걸린다.** Qt는 Windows에서 OpenSSL을 번들하지 않는다.
DLL이 없으면 TLS가 **조용히** 실패한다.

```cpp
qDebug() << QSslSocket::supportsSsl()                    // false 면 DLL 없음
         << QSslSocket::sslLibraryBuildVersionString()
         << QSslSocket::sslLibraryVersionString();
```

Qt 6은 `libssl-3-x64.dll` + `libcrypto-3-x64.dll`이 exe 옆이나 PATH에 있어야 한다.

**② 개인키 포맷.** OpenSSL 3.x는 기본이 PKCS#8(`-----BEGIN PRIVATE KEY-----`)인데
`QSslKey(..., QSsl::Rsa, ...)`에 주면 **null을 반환하고 조용히 실패**한다.

```sh
openssl rsa -in qt-console.key -out qt-console-trad.key
# 결과:  -----BEGIN RSA PRIVATE KEY-----
```

**③ SAN / 호스트명 검증.** IP로 접속하면 인증서에 **IP SAN**이 있어야 한다.
`setPeerVerifyMode(VerifyNone)`으로 끄면 mTLS의 의미가 사라지므로 발급자에게 SAN을 요청할 것.

⚠️ 브로커 재시작 후 CA가 재발급되어 Qt만 접속이 안 된 사례가 있었다. 증상이 "인자 오류"로
보여 원인을 찾기 어렵다 — `ca.crt` 지문을 서버 것과 대조해 볼 것.

## 7. ⚠️ 각도 해석 주의

`cmd/scan`과 `state/daemon`의 각도는 **기구각**이다 — 모터가 실제로 어디 있는지.
산출물 파일(.json/.pcd) 안의 각도는 **계약각**으로, 둘은 1:1이 아니다. 틸트 스윕이
바닥을 지나면서 한 줄이 방위 *p*와 *p+180*을 함께 훑기 때문이다.

```
기구 틸트 m ≤ 0 :  계약 pan = p        tilt = -90 - m
기구 틸트 m > 0 :  계약 pan = p + 180  tilt = -90 + m
```

**Qt는 기구각만 다루면 된다.** 변환은 데몬이 하고, 계약각은 파일 안에만 존재한다.
현재 각도를 화면에 그릴 때 "팬 45도"는 **모터 위치**지 빔이 보는 방위가 아니라는 점만 유의.

## 8. 구현 체크리스트 (Qt)

- [ ] `QSslSocket::supportsSsl()`이 true인지 먼저 확인 (OpenSSL DLL)
- [ ] 구독은 `adts/state/#` + `adts/event/#` 두 줄
- [ ] **발행 시 retain=false** 확인 (cmd 토픽)
- [ ] `req_id` 생성 및 응답 대조 (남의 응답 무시)
- [ ] `state:"OFFLINE"` 처리 — 데몬 죽음을 화면에 반영
- [ ] `DISARM` 버튼은 **항상** 활성 (비상정지)
- [ ] `REARM` 버튼 — DISARM에서 빠져나오는 유일한 경로
- [ ] 자동 DISARM은 오류가 아니다 — 별도 필터 불필요
- [ ] `fatal`로 표시 강도 나누기 — true=배너/모달, false=로그
- [ ] `105 ERR_EXPORT`는 측정값이 사라진 경우 — 가장 크게 보일 것
- [ ] `axis`를 오류 표시에 함께 — 어느 배선을 볼지가 곧 이 값이다
- [ ] `diag.valid`가 false면 카운터를 초록불로 그리지 말 것
- [ ] 팬 끝각을 `step`에 맞추기 — `step 9 → 1791`, `step 10 → 1790`
- [ ] `percent`를 0~100으로 clamp
- [ ] 진행률 유실 가정 — 완료 판정은 `state`로
- [ ] `cmd/home`이 오래 걸린다고 가정 — `homed`로 완료 판정
- [ ] 파일은 **HTTPS 8443**으로 (`GET /scan/<파일명>`, 같은 인증서)
- [ ] 개인키를 저장소에 커밋하지 않기 (`.gitignore`)

## 9. 데몬측 참고

구현: `RPi/daemon/modules/mqtt/mqtt_module.c`. 의존: `libmosquitto-dev`,
`libcjson-dev`, `libssl-dev`.

인증서 경로는 환경변수로 덮어쓸 수 있다:

```sh
export ADTS_MQTT_HOST=10.144.31.125
export ADTS_MQTT_PORT=8883
export ADTS_MQTT_CA=/etc/adts/certs/ca.crt
export ADTS_MQTT_CERT=/etc/adts/certs/daemon.crt
export ADTS_MQTT_KEY=/etc/adts/certs/daemon.key
./adts_daemon
```

인증서가 없거나 브로커가 안 떠 있어도 데몬은 **degraded로 계속 구동**한다 — MQTT가 안
붙어도 CLI(`--scan`)로는 스캔이 되어야 하기 때문이다.

**systemd 상주**: `sudo bash daemon/tools/install-service.sh`. ⚠️ 상주 서비스가
`/dev/turret`을 점유하므로, CLI로 직접 스캔하려면 `sudo systemctl stop adts-daemon`이 먼저다.

**⚠️ proto v6에서 `turret_link_state`가 커져 ioctl 매직이 바뀌었다.** 드라이버와 데몬은
반드시 같이 재빌드해야 한다 — 구버전 유저스페이스는 `-ENOTTY`로 즉시 실패한다.

## 10. 구현 상태 · 미결 사항

- [x] 수평 게이트 거부 `NOTICE_NOT_LEVEL(102)` 발행
- [x] HOME timeout `NOTICE_HOME_TIMEOUT(101)` 발행
- [x] IMU 설치 오프셋 코드 반영 (⚠️ 값은 재측정 필요 — §3.3)
- [x] `core_refresh_module_fds()`로 MQTT reconnect fd 주기 갱신
- [x] Qt PCD 전달은 mTLS 8443으로 확정
- [x] safety 명령은 missing ID에서도 항상 실행 — dedup을 토픽별로 변경
- [x] scan 정수의 range·step 상한 검증 (`step ≤ 3600` + STM도 검사)
- [x] `scan_out_close()` 결과를 `state/scan.ok`까지 전파 (+ `105 ERR_EXPORT`)
- [x] reconnect가 같은 정수 fd를 재사용하는 edge case
- [x] STM32 진단 카운터 노출 — `CMD_STATUS` 실송신 + `diag` 객체
- [x] 오류 축 구분 — `axis` 필드
- [ ] hardware EMS가 `USER_DISARM` 또는 별도 reason으로 구분되는지 보강
- [ ] 되감기 완료 protocol 추가 또는 15초 고정값 검증
- [ ] 인터넷 없는 부팅에서 인증서 시간 검증을 위한 RTC/fake-hwclock 정책
- [ ] Camera 결과/객체 검출의 MQTT 토픽은 별도 협의
- [ ] **킷 거치 자세 교정 후 IMU 설치각 오프셋 재측정** — 그전까지 게이트는 사실상
      아무것도 막지 않는다
