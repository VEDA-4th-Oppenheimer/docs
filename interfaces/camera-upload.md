# 카메라 측정 JSON mTLS 업로드 계약

RPi 데몬이 스캔 완료 후 카메라 애플리케이션으로 측정 JSON을 push하는 전송 계약을
정리한다. 송신 구현은 `RPi/daemon/modules/camera/camera_module.c`, 설정 예시는
`RPi/daemon/camera.conf.example`, 참조 수신기는 `RPi/daemon/tools/fake_camera.py`다.

| 항목 | 값 |
|---|---|
| 기준 코드 | RPi `2f58d6e` (2026-08-24) |
| 전송 | TCP 2222 위 mTLS |
| 최소 TLS 버전 | TLS 1.2 |
| 연결당 파일 | 1개 |
| 송신 산출물 | organized 측정 JSON |
| 실행 시점 | 데몬 `ST_EXPORT` 진입 |

## 시스템 경계

카메라 모듈은 코어가 JSON과 PCD를 모두 완전히 기록한 뒤 `result.json_path`가 가리키는
JSON만 카메라 단에 보낸다. PCD는 이 채널로 보내지 않으며 캘리브레이션 계산도 RPi에서
수행하지 않는다.

| 채널 | 포트 | 역할 |
|---|---:|---|
| MQTT over mTLS | 8883 | 명령·상태·이벤트 |
| HTTPS | 8443 | Qt가 PCD를 조회하는 경로 |
| camera upload | 2222 | 카메라 단으로 측정 JSON을 push하는 전용 스트림 |

대용량 파일 전송을 MQTT 제어 채널과 분리한다. 카메라 소켓은 코어 epoll에 등록하지 않고
`ST_EXPORT`의 모듈 콜백 안에서 연결부터 응답 확인까지 동기로 처리한다.

## 전송 시작 조건

카메라 모듈은 다음 조건을 모두 만족할 때만 업로드한다.

1. 새 데몬 상태가 `ST_EXPORT`다.
2. `result.valid == 1`이다.
3. `result.json_path`가 비어 있지 않다.
4. 현재 프로세스에서 직전에 성공한 JSON 경로와 다르다.
5. 설정에서 업로드가 비활성화되지 않았다.

중복 억제 키는 `point_count`가 아니라 성공한 `json_path`다. 서로 다른 고정 격자 스캔은
유효 셀 수가 같을 수 있으므로 점 수로 회차를 구분하지 않는다.

## 와이어 형식

TLS 연결이 성립한 뒤 다음 순서로 전송한다.

```text
offset  size     encoding              의미
0       2        uint16, big-endian    파일명 길이 N
2       N        ASCII                 basename
2+N     8        uint64, big-endian    파일 크기 B
10+N    B        bytes                 JSON 본문
```

| 항목 | 제한 |
|---|---|
| 파일 종류 | 정규 파일 |
| 파일 크기 | 1B 이상 64MiB 이하 |
| 파일명 길이 | 1~255B |
| 파일명 문자 | ASCII 영숫자, `.`, `_`, `-` |
| 금지 패턴 | `..`, 경로 구분자, 비ASCII |
| 본문 청크 | 최대 256KiB |

송신측과 수신측이 파일명을 각각 검증한다. 수신기는 인증된 데몬이 보낸 값이어도 저장
경로로 사용하기 전에 길이, 문자 집합, 경로 순회 패턴을 다시 검사한다.

### 수신 응답

수신기는 최대 2047B의 JSON 한 줄을 반환한다. 성공 응답은 최상위 객체의 첫 필드가
`result`이고 값이 문자열 `ok`여야 한다.

```json
{"result":"ok","file":"calib-20260824-120000_sweep-000001.json"}
```

키·콜론·값 사이의 JSON 공백은 허용한다. `"okay"`, 문자열 안에 포함된
`"result":"ok"`, 첫 필드가 다른 객체는 성공으로 판정하지 않는다.

응답 수신은 다음 조건 중 하나에서 끝난다.

- 개행을 받는다.
- 2047B를 채운다.
- 한 바이트 이상 받은 뒤 상대가 연결을 닫는다.

## mTLS 신원 계약

주소와 신원을 분리한다. 데몬은 설정의 `host`로 TCP 연결을 열지만 서버 신원은
`name`으로 검증한다. 기본 이름은 `adts-camera`다.

```text
RPi daemon                                         Camera app
daemon.crt + daemon.key                            adts-camera.crt + adts-camera.key
ca.crt                                             ca.crt

connect(host:2222)
  -> 서버 체인 검증
  -> SAN DNS name == adts-camera 검증
  -> SNI adts-camera
  <- 클라이언트 체인 검증
  <- client CN == adts-daemon 검증
```

데몬의 TLS 조건은 다음과 같다.

- `TLS_client_method()`를 사용한다.
- TLS 1.2 미만을 허용하지 않는다.
- `ca.crt`로 서버 인증서 체인을 검증한다.
- `SSL_set1_host()`로 SAN DNS 이름을 검증한다.
- partial wildcard를 허용하지 않는다.
- `name`을 SNI로 보낸다.
- `daemon.crt`와 `daemon.key`의 pair를 확인한다.

카메라 수신기는 `CERT_REQUIRED`로 클라이언트 인증서를 요구하고 CA 체인 검증 뒤 CN이
정확히 `adts-daemon`인지 확인한다. 같은 CA가 Qt 클라이언트 인증서도 발급하므로 CA
서명만으로 데몬 권한을 부여하지 않는다.

카메라 단에 배포하는 파일은 다음 세 개다.

```text
adts-camera.crt
adts-camera.key
ca.crt
```

`ca.key`는 발급 장비인 RPi 밖으로 내보내지 않는다. 서버 인증서는 다음 명령으로
발급한다.

```bash
sudo bash broker/gen-certs.sh --server adts-camera /etc/adts/certs
```

발급 결과에는 `serverAuth` EKU와 `DNS:adts-camera` SAN이 포함된다.

## 설정

설정 우선순위는 설정 파일, 환경변수, 내장 기본값 순이다. `ADTS_CAM_CONF`는 설정 파일
위치를 바꾸며 기본 경로는 `/etc/adts/camera.conf`다.

| 파일 키 | 환경변수 | 기본값 | 의미 |
|---|---|---|---|
| `host` | `ADTS_CAM_HOST` | `172.20.32.43` | 연결 주소 |
| `port` | `ADTS_CAM_PORT` | `2222` | 수신 포트 |
| `name` | `ADTS_CAM_NAME` | `adts-camera` | 서버 SAN 이름과 SNI |
| `timeout_s` | `ADTS_CAM_TIMEOUT_S` | `60` | 개별 connect/read/write 대기 한도 |
| `disable` | `ADTS_CAM_DISABLE` | `0` | 업로드 비활성화 |
| `ca` | `ADTS_CAM_CA` | `/etc/adts/certs/ca.crt` | 신뢰 CA |
| `cert` | `ADTS_CAM_CERT` | `/etc/adts/certs/daemon.crt` | 데몬 인증서 |
| `key` | `ADTS_CAM_KEY` | `/etc/adts/certs/daemon.key` | 데몬 개인키 |

설정 파일은 `key = value` 형식이다. `#`로 시작하는 줄과 알 수 없는 키를 무시한다.
파일 값이 systemd 환경변수보다 우선하므로 설정 파일을 바꾸면 데몬 재시작 없이 다음
업로드 시도에 반영된다.

각 시도는 설정을 다시 읽고 `SSL_CTX`도 다시 만든다. 인증서 경로 변경과 같은 경로의
인증서 교체를 모두 다음 시도에 반영한다.

`timeout_s`는 전체 전송 시간이 아니라 TCP connect 한 번과 socket read/write가 진행
없이 멈출 수 있는 개별 한도다. 호스트 이름을 사용할 때 `getaddrinfo()`는 connect
deadline을 적용하기 전에 동기로 실행된다.

## 송신 절차와 재시도

한 번의 `upload_once()`는 다음 순서로 실행된다.

```text
1. 현재 설정으로 SSL_CTX 생성
2. 정규 파일과 크기 확인
3. basename과 문자 제한 확인
4. 파일 open
5. 주소 해석과 deadline TCP connect
6. 서버 인증서·SAN 검증과 mTLS handshake
7. 파일명 길이·파일명·파일 크기 전송
8. 256KiB 청크로 본문 전송
9. 응답 수신
10. result 필드 판정
```

최대 세 번 시도하고 재시도 사이에는 2초를 기다린다.

| 분류 | 예 | 처리 |
|---|---|---|
| 성공 | `result`가 `ok` | 성공 경로 기억 |
| 재시도 | TCP 연결 실패, TLS transport 종료·timeout, 헤더·본문·응답 실패 | 최대 3회 |
| 즉시 중단 | CA·cert·key 오류, 파일 오류, SAN 불일치, TLS protocol 오류 | 현재 사유 보존 |

모든 시도가 실패하면 JSON은 로컬에 남기고 `NOTICE_UPLOAD_FAIL`을 `fatal = 0`으로
게시한다. 산출물 자체가 사라진 상황은 아니므로 데몬 상태를 강제로 바꾸지 않는다.

## 단일 스레드 실행

카메라 모듈의 `get_fd()`는 항상 `-1`이고 `on_event`, `on_tick`은 없다. 업로드는
`ST_EXPORT`의 `on_state`에서 동기 실행된다. 전송 중에는 코어 단일 스레드의 MQTT,
LED 입력, signal fd, turret fd, heartbeat 처리가 진행되지 않는다.

업로드 루프가 끝나면 `core_hb_reprime()`이 마지막 PONG 기준 시각을 현재로 옮긴다.
이는 동기 전송 시간을 링크 단절로 오판하지 않게 하며, 전송 중 놓친 이벤트를 다시
처리하는 기능은 아니다.

OpenSSL 없이 `ADTS_NO_TLS`로 빌드한 경우 모듈은 업로드를 비활성화한다. 평문 전송으로
전환하지 않는다.

## 참조 수신기

`fake_camera.py`는 다음 수신 계약을 실행 가능한 형태로 제공한다.

1. `adts-camera.crt`와 개인키로 TLS 서버를 연다.
2. TLS 1.2 이상과 `CERT_REQUIRED`를 적용한다.
3. 클라이언트 인증서 CN이 `adts-daemon`인지 확인한다.
4. 길이 선행 헤더를 읽고 파일명을 다시 검증한다.
5. 선언된 크기만큼 본문을 읽는다.
6. SHA-256을 계산해 로그에 남긴다.
7. `result` JSON을 한 줄로 반환한다.

기본 동작은 수신 내용을 저장하지 않고 검증 후 버린다. `--save`를 지정한 경우에만
검증된 basename으로 저장한다.

```bash
python3 daemon/tools/fake_camera.py \
  --certs /etc/adts/certs \
  --bind 0.0.0.0 \
  --port 2222 \
  --once
```

## 검증 기준선

2026-08-24 ARM64 Linux에서 다음을 검증했다.

| 항목 | 결과 |
|---|---|
| GNU 13.3, C11, `-Wall -Wextra -Werror` 전체 데몬 빌드 | 통과 |
| core·scan output·모듈 4종 cppcheck | 통과 |
| `ADTS_NO_TLS` GNU C11 단독 컴파일 | 통과 |
| Python bytecode compile과 안전 파일명 단위 검사 | 통과 |
| 응답 판정 공백·오탐 단위 검사 | 통과 |
| 실제 camera 모듈에서 참조 수신기로 mTLS 전송 | 성공 |
| 협상 결과 | TLS AES-256-GCM, client CN `adts-daemon` |
| 동일 JSON 경로 재호출 | 두 번째 업로드 억제 |
| 잘못된 서버 SAN | hostname mismatch로 거부 |
| 같은 cert/key 경로의 인증서 교체 | 재시작 없이 새 client CN 반영 |
