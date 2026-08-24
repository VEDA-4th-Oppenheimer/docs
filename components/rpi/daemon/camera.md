# 카메라 mTLS 송신 모듈

`RPi/daemon/modules/camera/camera_module.c`가 스캔 JSON을 카메라 애플리케이션으로
전송하는 방법을 정리한다. 기준 코드는 RPi `2f58d6e`(2026-08-24)다.

| 항목 | 값 |
|---|---|
| 모듈 이름 | `camera` |
| 실행 위치 | `adts_daemon` 단일 epoll 스레드 |
| 실행 시점 | `ST_EXPORT`의 `on_state` |
| 전송 대상 | `shared_ctx.result.json_path` |
| 전송 방식 | TCP 2222 위 mTLS |
| OpenSSL 미탑재 | 업로드 비활성, 평문 폴백 없음 |

## 모듈 경계

카메라 모듈은 코어가 JSON과 PCD를 모두 마감한 뒤 organized 측정 JSON만 전송한다.
좌표 변환, 격자 병합, 파일 생성과 캘리브레이션 계산은 담당하지 않는다.

```text
core_transition(ST_EXPORT)
  -> ctx.result.valid / json_path 확정
  -> mqtt on_state
  -> led on_state
  -> camera on_state
       -> 설정·인증서 로드
       -> mTLS 파일 전송
       -> 응답 확인
       -> heartbeat 기준 시각 재설정
```

## 콜백 생명주기

| 콜백 | 구현 |
|---|---|
| `init` | 설정 로드, `SIGPIPE` 무시, TLS 컨텍스트 사전 검증 |
| `get_fd` | 항상 `-1` |
| `on_event` | 없음 |
| `on_tick` | 없음 |
| `on_state` | `ST_EXPORT`에서 동기 업로드 |
| `deinit` | TLS 컨텍스트 해제 |

모듈 소켓은 코어 epoll에 등록되지 않는다. 연결부터 응답 확인까지 `on_state` 호출 안에서
끝난다.

TLS 자격 증명이나 카메라 장치가 준비되지 않아도 `init()`은 0을 반환한다. 데몬은
degraded 상태로 계속 실행하며 다음 업로드 시도에서 설정과 인증서를 다시 확인한다.

OpenSSL을 찾지 못한 빌드는 `ADTS_NO_TLS`를 정의한다. 이 경로의 `upload_once()`는
`UP_FATAL`을 반환하고 모듈은 비활성 상태가 된다. 암호화가 준비되지 않았을 때 TCP
평문으로 전환하지 않는다.

## 업로드 진입 조건

`cam_on_state()`는 다음 순서로 전송 여부를 판정한다.

1. `new_st == ST_EXPORT`인지 확인한다.
2. `ctx->result.valid == 1`인지 확인한다.
3. `ctx->result.json_path`가 비어 있지 않은지 확인한다.
4. 직전에 성공한 `s_last_uploaded`와 경로가 다른지 확인한다.
5. 현재 설정의 `disable`이 0인지 확인한다.

산출물 기록이 실패해도 코어는 EXPORT 상태를 거칠 수 있으므로 `result.valid`를 먼저
확인한다. 중복 억제 키는 `point_count`가 아니라 성공한 JSON 경로다. 고정 격자 스캔은
서로 다른 회차의 유효 셀 수가 같을 수 있기 때문이다.

`s_last_uploaded`는 현재 프로세스에서 성공한 마지막 경로만 보존한다. 업로드에 실패한
경로는 기록하지 않으므로 다음 EXPORT 진입에서 다시 시도할 수 있다.

## 설정 로드

설정 우선순위는 설정 파일, 환경변수, 내장 기본값 순이다. 환경변수는 설정 파일이 없거나
해당 키를 제공하지 않을 때의 기본값으로 동작한다.

| 파일 키 | 환경변수 | 기본값 |
|---|---|---|
| `host` | `ADTS_CAM_HOST` | `172.20.32.43` |
| `port` | `ADTS_CAM_PORT` | `2222` |
| `name` | `ADTS_CAM_NAME` | `adts-camera` |
| `timeout_s` | `ADTS_CAM_TIMEOUT_S` | `60` |
| `disable` | `ADTS_CAM_DISABLE` | `0` |
| `ca` | `ADTS_CAM_CA` | `/etc/adts/certs/ca.crt` |
| `cert` | `ADTS_CAM_CERT` | `/etc/adts/certs/daemon.crt` |
| `key` | `ADTS_CAM_KEY` | `/etc/adts/certs/daemon.key` |

`ADTS_CAM_CONF`가 설정 파일 위치를 정하며 기본값은 `/etc/adts/camera.conf`다. 파일은
`key = value` 형식이고 주석·빈 줄·알 수 없는 키를 무시한다. 포트는 1~65535 범위,
timeout은 양수만 반영한다.

각 전송 시도 직전에 `load_config()`를 다시 호출한다. 이어 기존 `SSL_CTX`를 해제하고
현재 CA·cert·key로 다시 만든다. 설정 경로를 바꾼 경우와 같은 경로의 인증서 파일을
교체한 경우가 모두 다음 시도에 반영된다.

## TLS 컨텍스트와 handshake

`tls_ctx_ready()`는 다음 순서로 클라이언트 컨텍스트를 만든다.

```text
SSL_CTX_new(TLS_client_method)
  -> 최소 TLS 1.2 설정
  -> CA trust store 로드
  -> daemon 인증서 chain 로드
  -> 개인키 로드
  -> 인증서·키 pair 검사
  -> SSL_VERIFY_PEER, verify depth 4
```

`tls_handshake()`는 연결마다 검증 이름을 설정한다.

```text
SSL_new
  -> partial wildcard 금지
  -> SSL_set1_host(s_name)
  -> SNI s_name
  -> SSL_set_fd
  -> SSL_connect
```

인증서 검증 결과가 `X509_V_OK`가 아니면 SAN·체인 문제로 기록하고 즉시 중단한다.
인증서 검증은 통과했지만 `SSL_ERROR_SYSCALL`, `ZERO_RETURN`, `WANT_READ`,
`WANT_WRITE`가 발생한 경우에는 transport 장애로 분류해 다음 시도를 허용한다.

## TCP 연결과 timeout

`connect_camera()`는 `getaddrinfo()` 결과를 순서대로 시도한다. 각 socket은 임시로
non-blocking 상태에서 connect하고 `select()`와 `SO_ERROR`로 완료 여부를 확인한 뒤 다시
blocking 상태로 돌린다.

연결 후 `SO_SNDTIMEO`와 `SO_RCVTIMEO`를 설정한다. `timeout_s`는 다음 경계에 적용된다.

- TCP connect 한 번의 대기
- 진행이 멈춘 socket write 한 번의 대기
- 진행이 멈춘 socket read 한 번의 대기

전체 업로드 시간에 대한 단일 deadline은 아니다. `getaddrinfo()`도 connect deadline을
적용하기 전에 동기로 실행된다.

OpenSSL은 내부에서 `write(2)`를 호출하므로 `MSG_NOSIGNAL`을 전달할 수 없다. `init()`이
프로세스의 `SIGPIPE`를 무시하도록 설정해 상대가 먼저 연결을 닫아도 데몬이 종료되지
않게 한다.

## 파일 송신

`upload_once()`는 다음 순서로 한 번의 전송을 수행한다.

```text
1. SSL_CTX 재생성
2. stat으로 정규 파일·1B..64MiB 확인
3. basename 추출과 허용 문자 확인
4. 파일 open
5. TCP connect
6. mTLS handshake와 서버 이름 검증
7. 파일명 길이·파일명·파일 크기 전송
8. 256KiB 청크로 본문 전송
9. 최대 2047B 응답 수신
10. 첫 result 필드가 정확히 "ok"인지 판정
```

파일명 길이는 uint16 big-endian, 파일 크기는 uint64 big-endian으로 직접 인코딩한다.
본문 버퍼는 256KiB 정적 배열로 두어 큰 스택 프레임을 피한다. `ssl_send_all()`은 각
구간을 끝까지 보낼 때까지 `SSL_write()`를 반복한다.

응답 판정기는 JSON 공백을 허용하지만 최상위 객체의 첫 키가 `result`인지 확인한다.
문자열 내부의 우연한 substring이나 `"okay"`를 성공으로 처리하지 않는다. cJSON은 데몬의
선택 의존성이므로 카메라 모듈이 별도로 요구하지 않는다.

## 재시도와 실패 전달

최대 세 번 시도하고 시도 사이에는 2초를 기다린다. 각 시도는 설정과 TLS 컨텍스트를
새로 읽는다.

| 반환 | 분류 | 예 |
|---|---|---|
| `UP_OK` | 성공 | 수신측 `result: "ok"` |
| `UP_RETRY` | 일시 장애 | connect, TLS transport, header·body·reply 실패 |
| `UP_FATAL` | 동일 조건에서 반복되는 오류 | 자격 증명, 파일, SAN, TLS protocol 오류 |

성공하면 `s_last_uploaded`를 갱신한다. 모든 시도가 실패하면 로컬 JSON 경로와 원인을
로그에 남기고 `NOTICE_UPLOAD_FAIL`을 `fatal = 0`으로 게시한다. 측정 파일은 로컬에
남으므로 산출물 유실로 분류하지 않는다.

## 단일 스레드와 heartbeat

동기 업로드 중에는 코어 단일 스레드의 MQTT, LED switch, signal fd, turret fd,
heartbeat 처리가 진행되지 않는다. 업로드 루프가 끝나면 `core_hb_reprime()`이 마지막
PONG 기준 시각을 현재로 옮겨 동기 전송 시간을 링크 단절로 오판하지 않게 한다.

산출물이 없거나 업로드가 비활성인 경우, 이미 성공한 동일 경로인 경우에는 네트워크
작업 없이 반환하므로 heartbeat 기준 시각도 바꾸지 않는다.

## 참조 수신기

`RPi/daemon/tools/fake_camera.py`는 카메라 없이 송신 경로를 검증하는 TLS 서버다.

- TLS 1.2 이상과 `CERT_REQUIRED`를 적용한다.
- 클라이언트 CN이 `adts-daemon`인지 확인한다.
- 파일명 길이와 허용 문자를 송신측과 독립적으로 검사한다.
- 선언된 크기만큼 읽으며 SHA-256을 로그에 남긴다.
- 기본값은 수신 데이터를 버리고 `--save`일 때만 저장한다.
- 성공 시 `result` JSON 한 줄을 반환한다.

```bash
python3 daemon/tools/fake_camera.py \
  --certs /etc/adts/certs \
  --bind 0.0.0.0 \
  --port 2222 \
  --once
```

## 검증

2026-08-24 ARM64 Linux에서 다음을 확인했다.

| 항목 | 결과 |
|---|---|
| GNU 13.3, C11, `-Wall -Wextra -Werror` 전체 빌드 | 통과 |
| core·scan output·모듈 4종 cppcheck | 통과 |
| `ADTS_NO_TLS` GNU C11 단독 컴파일 | 통과 |
| Python bytecode compile·안전 파일명 검사 | 통과 |
| 응답 판정 공백·오탐 검사 | 통과 |
| camera 모듈 → 참조 수신기 mTLS 전송 | 성공 |
| 동일 경로 재호출 | 두 번째 업로드 억제 |
| 잘못된 서버 SAN | hostname mismatch로 거부 |
| 같은 경로의 클라이언트 인증서 교체 | 재시작 없이 새 CN 반영 |
