# MQTT 토픽 계약

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-MQT-40` |
| 담당 | 이현우 |
| 대상 소스 | `RPi/daemon/modules/mqtt/mqtt_module.c` |
| 기준 코드 | RPi `d3eee3e` (2026-08-19). 대상 파일은 이후 변경 없음 |
| 경계 | Qt 관제 ↔ RPi 데몬 |
| 계약 버전 | v1.4 |

---

## 1. 개요

브로커(Mosquitto)는 RPi 에 상주하고, 접속은 mTLS(8883)만 허용한다. 권한은 클라이언트
인증서의 CN 으로 판정한다.

데몬은 별도 네트워크 스레드를 두지 않고 mosquitto 소켓을 코어 epoll 에 등록한다.
재접속으로 fd 가 바뀌므로 `core_refresh_module_fds()` 가 매 tick 재등록한다.

모듈은 명령을 직접 실행하지 않는다. `on_message` 는 `shared_ctx` 의 요청 플래그만
세우고, 실제 전이는 다음 100ms `core_tick` 이 정해진 순서로 수행한다. 수신 콜백에서
상태를 바꾸면 코어의 전이 순서와 경쟁하기 때문이다.

---

## 2. 토픽 목록

| 토픽 | 방향 | QoS | retained |
|---|---|---:|---|
| `adts/cmd/scan` | Qt → 데몬 | 1 | 금지 |
| `adts/cmd/stop` | Qt → 데몬 | 1 | 금지 |
| `adts/cmd/home` | Qt → 데몬 | 1 | 금지 |
| `adts/cmd/disarm` | Qt → 데몬 | 1 | 금지 |
| `adts/cmd/rearm` | Qt → 데몬 | 1 | 금지 |
| `adts/state/daemon` | 데몬 → Qt | 1 | 예 (LWT 포함) |
| `adts/state/scan` | 데몬 → Qt | 1 | 예 |
| `adts/event/progress` | 데몬 → Qt | 0 | 아니오 |
| `adts/event/error` | 데몬 → Qt | 1 | 아니오 |

cmd 토픽에 retained 를 걸면 안전 사고다. 데몬이 재접속할 때마다 다시 배달돼
전원을 껐다 켤 때마다 킷이 혼자 스캔을 시작한다.

구독은 `adts/cmd/#` 로 잡으므로 토픽을 추가해도 ACL 변경이 필요 없다.

---

## 3. 명령 (Qt → 데몬)

### 3.1 `adts/cmd/scan`

```json
{
  "req_id": "qt-1755589abc",
  "pan_ddeg":  [0, 1791],
  "tilt_ddeg": [-900, 900],
  "step_ddeg": 9,
  "sensor_height_mm": 1805
}
```

`pan_ddeg` / `tilt_ddeg` 는 기구각 쌍이다. `sensor_height_mm` 은 선택이며 좌표에
적용되지 않는 메타데이터다.

### 3.2 나머지 명령

| 토픽 | payload | `shared_ctx` 변화 |
|---|---|---|
| `stop` | `{"req_id": …}` | `req_scan_stop = 1` |
| `disarm` | `{"req_id": …}` | `req_disarm = 1`, 사용자 의도 표시 |
| `rearm` | `{"req_id": …}` | `req_rearm = 1` |
| `home` | `{"req_id": …}` | `req_home = 1` |

### 3.3 `req_id` 와 중복 제거

- `req_id` 가 없으면 중복 게이트를 생략한다.
- `req_id` 가 있으면 토픽별로 직전 ID 와 비교해 같으면 무시한다.

토픽별로 나눈 이유는 QoS1 재전송 때문이다. 전역 하나로 두면 서로 다른 토픽의 명령이
서로를 삼킨다. `stop`·`disarm` 같은 멱등 안전 명령은 ID 가 없어도 통과시켜 안전 경로가
막히지 않게 한다.

---

## 4. 상태 (데몬 → Qt)

### 4.1 `adts/state/daemon` (retained)

```json
{
  "state": "IDLE",
  "online": true,
  "link_alive": true, "homed": true, "scanning": false,
  "cur_pan_ddeg": 0, "cur_tilt_ddeg": -900,
  "last_err": 0, "last_err_axis": 0,
  "diag": { "valid": true, "tx_fail": 0, "rx_ovf": 0,
            "enc_retry": 0, "lidar_drop": 0, "reject_busy": 0 },
  "level": { "valid": true, "roll_deg": 10.05, "pitch_deg": 0.4,
             "raw_roll_deg": 7.05, "raw_pitch_deg": 4.4 },
  "ts": 1755589000
}
```

`state` 는 `IDLE` / `SCANNING` / `EXPORT` / `DISARM` 중 하나다.

발행 조건은 상태 전이 즉시, 그리고 tick 에서 수평 판정 변화 또는 5초 heartbeat
(`STATE_HEARTBEAT_MS`)다.

LWT 는 같은 토픽에 `online:false` 를 retained 로 걸어두고, 정상 종료 시에도 직접 한 번
발행한다.

`diag.valid` 가 false 면 카운터는 "모른다"이지 "정상"이 아니다. `CMD_STATUS` 를 한 번도
받지 못했다는 뜻이다(구버전 펌웨어이거나 첫 주기 전).

`level` 에 `roll_deg` 와 `raw_roll_deg` 를 함께 싣는 이유는 전자가 설치각을 뺀 이탈(게이트가
보는 값)이고 후자가 중력벡터 각 그대로이기 때문이다. 둘을 같이 봐야 리그가 기울었는지
IMU 마운트가 틀어졌는지 구분할 수 있다.

### 4.2 `adts/state/scan` (retained)

```json
{ "req_id": "qt-1755589abc", "ok": true,
  "pcd": "/var/lib/adts/scans/calib-20260819-185256_sweep-000001.pcd",
  "points": 40088, "stm_reported": 0, "ts": 1755589123 }
```

`ST_EXPORT` 전이 시 발행한다. 파일 내용은 보내지 않는다. `.pcd` 는 HTTPS 8443(같은
인증서), 카메라용 원시 JSON 은 mTLS TCP 2222 로 나간다.

`stm_reported` 는 현재 항상 0 이다. 드라이버가 `CMD_SCAN_DONE` 의 `point_count` 를 ABI 로
내보내지 않기 때문이다. `points`(격자에 채운 셀 수)와 대조하려고 만든 필드인데 지금은
대조가 되지 않는다.

---

## 5. 이벤트 (데몬 → Qt)

### 5.1 `adts/event/progress` (QoS0)

```json
{ "req_id": "...", "points": 12345, "expected": 40400, "percent": 30, "ts": … }
```

스캔 중 500ms 주기(`PROGRESS_PERIOD_MS`)로 발행한다. QoS0 이라 유실을 허용한다 —
다음 주기에 더 정확한 값이 온다.

`points` 는 수신 프레임 수가 아니라 격자에 처음 채운 셀 수다. 병합된 중복은 올리지
않으므로 100% 에 못 미친 채 끝나는 것이 정상이다.

### 5.2 `adts/event/error` (QoS1, non-retained)

```json
{ "req_id": "...", "code": 102, "name": "ERR_NOT_LEVEL",
  "msg": "수평 NG: roll=10.05 pitch=0.40 (임계 10.0)",
  "fatal": true, "axis": 0, "ts": … }
```

| code 범위 | 출처 |
|---|---|
| 1 ~ 8 | STM32 `proto_err_code`. `axis` 는 v6 비트 플래그(1=팬, 2=틸트, 3=둘 다) |
| 100 ~ 106 | 데몬 자체 판정. `axis` 는 항상 0 |

데몬 판정 코드는 다음과 같다.

| code | 이름 | 뜻 |
|---:|---|---|
| 100 | `DISARM` | 안전정지 (링크 두절 / STM 오류 / 사용자) |
| 101 | `HOME_TIMEOUT` | 홈 무응답으로 요청 취소 |
| 102 | `NOT_LEVEL` | 수평 게이트가 스캔을 거부 |
| 103 | `UPLOAD_FAIL` | 카메라 업로드 실패 (파일은 로컬에 남음) |
| 104 | `BAD_REQUEST` | cmd 페이로드 필드 누락/형식 오류 |
| 105 | `EXPORT_FAIL` | 산출물 기록 실패 — 데이터 복구 불가 |
| 106 | `BUSY` | 현재 상태에서 수용 불가 — 요청 거절 |

100 을 경계로 나눈 이유는 그 전까지 `4` 하나가 세 뜻으로 쓰였기 때문이다. Qt 가
`code=4` 를 받고도 STM32 가 거절한 것인지 데몬이 페이로드를 못 읽은 것인지 알 수
없었다.

발행 규칙은 다음과 같다.

- 같은 STM32 오류가 반복되면 변화 엣지에서만 발행한다.
- 데몬 notice 는 `seq` 증가로 판정하므로 같은 오류의 재발도 새 사건이다.
- 정상 완료 뒤의 자동 DISARM 은 error 가 아니다(사용자 DISARM 과 구분).

---

## 6. 인증서

```bash
sudo bash broker/gen-certs.sh <RPi_IP> /etc/adts/certs   # 최초 1회
sudo bash broker/gen-certs.sh --client <CN>              # 클라이언트 추가
```

기본 경로는 `/etc/adts/certs/{ca.crt, daemon.crt, daemon.key}` 다.

`daemon.key` 권한이 가장 자주 걸린다. `gen-certs.sh` 가 `600 root` 로 두는데 데몬은
`User=pi` 로 돈다. 증상이 `MOSQ_ERR_INVAL`("Invalid function arguments")이라 권한
문제로 보이지 않는다.

```bash
sudo groupadd -f adts && sudo usermod -aG adts pi
sudo chgrp adts /etc/adts/certs/daemon.key && sudo chmod 640 /etc/adts/certs/daemon.key
```

`644` 로 두면 안 된다. 개인키가 모든 사용자에게 읽힌다.

---

## 7. 진단

```bash
mosquitto_sub -h localhost -p 8883 --cafile /etc/adts/certs/ca.crt \
  --cert /etc/adts/certs/qt-console.crt --key /etc/adts/certs/qt-console.key \
  -t adts/state/daemon -C 1 | jq .diag
```

---

## 8. 검증 기준선

| 항목 | 근거 | 결과 |
|---|---|---|
| 토픽 목록 | 2026-08-24 `mqtt_module.c` 문자열 전수 대조 | 문서 9개 = 코드 9개 + 구독 와일드카드 `adts/cmd/#` |
| 발행 주기 | 같은 커밋 `PROGRESS_PERIOD_MS` / `STATE_HEARTBEAT_MS` | 500ms / 5000ms 일치 |
| 데몬 판정 코드 | `RPi/shared/daemon_module.h` 대조 | 100~106 이름·뜻 일치 |
| 실기 발행 | 2026-08-19 스캔 (RPi `d3eee3e`) | `state/scan` 발행, `diag` 카운터 전부 0 |

---

## 9. 참고

- 구현: `RPi/daemon/modules/mqtt/mqtt_module.c`
- 공유 상태와 notice 코드: `RPi/shared/daemon_module.h`
- 오류코드 원본: `RPi/shared/protocol.h`
- 인증서 발급: `RPi/broker/gen-certs.sh`, `RPi/broker/README.md`
