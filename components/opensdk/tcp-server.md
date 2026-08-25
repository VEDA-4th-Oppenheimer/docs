# LiDAR JSON mTLS 수신 서버

`tcp_server`는 RPi에서 보낸 organized LiDAR 측정 JSON을 CV5 카메라에서 수신하는
독립 OpenSDK CAP이다. 공개 기준은 OpenSDK `704fbd1`(2026-08-19), 로컬 통합
기준은 2026-08-24의 `tcp_server` 1.2 작업본이다. 두 버전은 파일 저장 경로와 세션
구조가 다르다.

| 항목 | 값 |
|---|---|
| 전송 | TCP 2222 위 mTLS |
| 최소 TLS 버전 | TLS 1.2 |
| 연결당 파일 | 1개 |
| 최대 파일 크기 | `64 MiB` |
| 최대 파일명 길이 | `255 B` |
| 본문 읽기 단위 | 최대 `256 KiB` |
| socket read/write timeout | `60초` |
| listen backlog | `4` |
| 동시 처리 | 한 번에 한 연결 |
| 로컬 1.2 저장 루트 | `/tmp/calibration` |

## 시스템 내 역할

```text
STM32 스캔
  -> RPi가 organized JSON 생성
  -> RPi camera module이 mTLS 연결
  -> tcp_server가 파일명 / 크기 / JSON 검사
  -> 임시 .part 파일 저장
  -> JSON 검증 후 원자적 rename
  -> calibration CAP이 완성된 JSON 검색
```

서버는 스캔 제어, MQTT 처리, 카메라 Snapshot, Core 계산을 수행하지 않는다. 정상
시작 시 별도 Start 버튼 없이 앱 초기화에서 포트 2222를 listen한다.

## TLS 컨텍스트와 인증서 배치

```text
RPi client                               CCTV server
daemon.crt + daemon.key                  server.crt + server.key
ca.crt                                   ca.crt

              TLS 1.2+ / 양방향 인증
```

서버 구현은 다음 순서로 TLS 컨텍스트를 설정한다.

```text
TLS_server_method()
  -> minimum TLS 1.2
  -> SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT
  -> verify depth 4
  -> server certificate chain load
  -> server private key load
  -> certificate/private key pair check
  -> CA trust store load
```

```text
storage/cert/
├── ca.crt
├── server.crt
└── server.key
```

서버 개인키와 CA 개인키를 Git 저장소 또는 CAP에 포함하지 않는다. `server.key`는
장치에서만 안전하게 provisioning하고 가능하면 `0600` 권한을 설정한다. 카메라에는
검증용 `ca.crt`만 배포하며 발급에 사용하는 `ca.key`는 복사하지 않는다.

### 현재 클라이언트 신원 검사의 제한

공유 인터페이스 계약은 CA 체인 검증 뒤 클라이언트 인증서의 CN이 `adts-daemon`인지
확인하도록 요구한다. 그러나 2026-08-24에 확인한 공개 코드와 로컬 1.2 코드는 다음
조건만 확인한다.

1. TLS handshake가 완료되었는지.
2. 인증서 chain 검증 결과가 `X509_V_OK`인지.
3. peer 인증서가 실제로 존재하는지.

인증서 CN 또는 SAN이 `adts-daemon`인지 검사하는 코드는 확인되지 않았다. 같은 CA가
다른 장치 인증서를 발급한다면 CA 검증만으로 송신 주체를 제한할 수 없으므로 운영
인수 전에 명시적 subject/SAN 검사와 거부 테스트가 필요하다.

## 와이어 프로토콜

TLS 연결 안에서 파일명 길이, 파일명, 파일 크기, JSON 본문을 아래 순서로 전송한다.

```text
offset     size       encoding              의미
0          2          uint16 big-endian     파일명 길이 N
2          N          ASCII                 JSON basename
2 + N      8          uint64 big-endian     파일 크기 B
10 + N     B          bytes                 JSON 본문
```

| 값 | 수신기 제한 |
|---|---|
| `N` | `1~255` |
| 파일명 문자 | ASCII 영문, 숫자, `.`, `_`, `-` |
| 금지 패턴 | `..`, `/`, `\\`, 비ASCII 문자 |
| 확장자 | `.json` 또는 `.JSON` |
| 로컬 1.2 세션 이름 | 파일명이 `calib-YYYYMMDD-HHMMSS`로 시작해야 함 |
| `B` | `1~67,108,864` bytes |

로컬 1.2는 파일명의 앞 21자를 세션 ID로 추출한다. 날짜와 시간 자리는 숫자여야 하고
날짜와 시간 사이에 `-`가 있어야 한다.

```text
calib-20260824-120000_sweep-000001.json
└────── session id ──────┘
```

## 임시 파일과 JSON 검증

수신 파일은 바로 최종 `.json` 이름으로 노출하지 않는다.

```text
<session>/<file>.json.<connection_id>.part
  -> 256 KiB 단위 TLS 읽기
  -> 선언된 크기까지 정확히 기록
  -> JSON parse 및 필수 필드 확인
  -> rename(<temporary>, <session>/<file>.json)
  -> 성공 JSON 응답
```

필수 필드는 다음과 같다.

```json
{
  "interface_version": "1.2",
  "scan": {},
  "measurements": [
    {}
  ]
}
```

`interface_version`은 문자열, `scan`은 객체, `measurements`는 비어 있지 않은
배열이어야 한다. 예시는 타입 설명용이며 전체 스캔 schema를 대체하지 않는다. 읽기
중단, 파일 오류 또는 JSON 검증 실패 시 `.part` 파일을 삭제하고 최종 이름을 생성하지
않는다.

## 세션 저장 경로와 버전 차이

| 기준 | 실제 저장 경로 | `calibration` 앱과 연결 |
|---|---|---|
| 공개 OpenSDK `704fbd1` / 1.0 | `../storage/uploads/<원본 파일명>` | 직접 연결되지 않음 |
| 로컬 2026-08-24 작업본 / 1.2 | `/tmp/calibration/calib-YYYYMMDD-HHMMSS/<원본 파일명>` | 공유 세션 경로로 연결 |

로컬 1.2는 `/tmp/calibration`과 세션 디렉터리를 sticky bit 포함 `01777`로 준비해
서로 다른 CAP 사용자가 같은 세션에서 JSON·Snapshot·결과를 읽고 쓸 수 있게 한다.

```text
/tmp/calibration/
└── calib-20260824-120000/
    └── calib-20260824-120000_sweep-000001.json
```

`/tmp`는 휘발성 저장소다. 장치 재부팅 전에 필요한 JSON과 결과를 외부 저장소로
복사해야 하며 디스크 사용량과 오래된 세션 정리 정책도 운영 환경에서 확인해야 한다.

## 응답과 계약 차이

성공 응답은 `result`를 첫 필드로 두며 파일명, 크기, 측정 개수와 저장 경로를 포함한다.

```json
{
  "result": "ok",
  "file_name": "calib-20260824-120000_sweep-000001.json",
  "bytes": 2097152,
  "measurements": 31200,
  "path": "/tmp/calibration/calib-20260824-120000/calib-20260824-120000_sweep-000001.json"
}
```

실제 전송은 개행으로 끝나는 JSON 한 줄이다. 오류 응답 구현은 `result: "error"`와
`message`를 반환한다. 팀 인터페이스 문서는 오류 설명 필드를 `reason`으로 요구하므로
송수신 측 계약을 통일하거나 호환 필드를 추가해야 한다.

```json
{"result":"error","message":"invalid json file name"}
```

RPi 송신측은 연결 또는 응답 실패 시 같은 파일을 재전송할 수 있다. 서버는 연결별
`.part` 이름과 최종 rename을 사용해 같은 파일명의 반복 수신을 처리한다.

## 상태와 장애 대응

```text
initializing
  -> tls_server_starting
  -> tls_listening
  -> tls_handshake
  -> client_authenticated
  -> receiving
  -> upload_completed
```

| 증상 | 확인 항목 |
|---|---|
| 서버가 listen하지 않음 | `ca.crt`, `server.crt`, `server.key`, 인증서·키 pair, 포트 점유 |
| handshake 실패 | TLS 1.2+, 공통 CA, peer 인증서와 유효기간 |
| RPi가 서버를 거부 | 서버 인증서 SAN과 송신측 검증 이름 일치 여부 |
| 파일명 거부 | ASCII basename, `.json`, `calib-YYYYMMDD-HHMMSS` 접두어 |
| JSON 거부 | 실제 파일 크기와 `interface_version`, `scan`, `measurements` |
| Calibration 목록에 파일 없음 | 공개 1.0의 `storage/uploads`와 공유 `/tmp/calibration` 경로 불일치 |
| 인증서는 통과하지만 권한 분리가 불명확 | 클라이언트 CN `adts-daemon` 검사 미구현 |

2026-08-24 기준으로 코드와 송신 계약의 정적 대조는 가능하지만, 실제 CA 발급·장치
배포·RPi 송신·카메라 수신을 포함한 E2E PASS 증적은 별도로 확보해야 한다.
