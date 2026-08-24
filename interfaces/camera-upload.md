# 카메라 측정 JSON 업로드 계약

RPi 데몬이 스캔 완료 후 카메라 애플리케이션으로 organized 측정 JSON을 push할 때 양쪽이
공통으로 지켜야 하는 전송·신원 계약이다.

| 항목 | 값 |
|---|---|
| 기준 구현 | RPi `2f58d6e` (2026-08-24) |
| 전송 | TCP 2222 위 mTLS |
| 최소 TLS 버전 | TLS 1.2 |
| 연결당 파일 | 1개 |
| 송신 산출물 | organized 측정 JSON |

## 채널 경계

카메라 업로드는 제어·상태용 MQTT와 Qt의 PCD 조회 경로에서 분리된 전용 채널이다.

| 채널 | 포트 | 역할 |
|---|---:|---|
| MQTT over mTLS | 8883 | 명령·상태·이벤트 |
| HTTPS | 8443 | Qt가 PCD를 조회 |
| camera upload | 2222 | 카메라 단으로 측정 JSON을 push |

카메라 단은 PCD가 아니라 JSON을 받는다. JSON은 organized 격자의 대표 측정값,
병합 통계, 기구·센서 메타데이터를 포함하며 병합 전 UART frame 전체를 보존한 raw log는
아니다.

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

송신측과 수신측이 파일명을 각각 검증한다. 인증된 데몬이 보낸 값이어도 수신측은 저장 전에
길이, 문자 집합, 경로 순회 패턴을 다시 확인한다.

## 수신 응답

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

성공 응답을 받지 못하면 송신측은 파일 전달을 완료한 것으로 기록하지 않는다. 수신측은
오류 응답에 `result: "error"`와 사람이 식별할 수 있는 `reason`을 포함한다.

## mTLS 신원

주소와 신원을 분리한다. 데몬은 운영 설정의 `host`로 연결하지만 서버 인증서의 SAN은
고정 이름 `adts-camera`로 검증한다.

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

데몬은 다음 조건으로 카메라 신원을 검증한다.

- TLS 1.2 이상을 사용한다.
- `ca.crt`로 서버 인증서 체인을 검증한다.
- SAN DNS 이름이 `adts-camera`인지 확인한다.
- partial wildcard를 허용하지 않는다.
- 검증 이름을 SNI로 보낸다.
- `daemon.crt`와 `daemon.key`로 클라이언트 인증을 수행한다.

카메라 수신기는 `CERT_REQUIRED`로 클라이언트 인증서를 요구하고 CA 체인 검증 뒤 CN이
정확히 `adts-daemon`인지 확인한다. 같은 CA가 Qt 인증서도 발급하므로 CA 서명만으로
데몬 권한을 부여하지 않는다.

카메라 단에는 다음 세 파일만 배포한다.

```text
adts-camera.crt
adts-camera.key
ca.crt
```

`ca.key`는 발급 장비인 RPi 밖으로 내보내지 않는다. 카메라 서버 인증서는 `serverAuth`
EKU와 `DNS:adts-camera` SAN을 가져야 한다. 데몬 인증서는 `clientAuth` EKU와
`CN=adts-daemon`을 가져야 한다.

TLS는 전송 중 기밀성과 무결성을 제공한다. 수신 파일을 영구 저장한 뒤의 무결성까지
확인하려면 응답에 별도 digest를 추가해야 하며, 현재 응답 계약에는 포함되지 않는다.

## 재시도에 대한 수신측 요구

송신측은 실패한 파일을 최대 세 번 전송할 수 있으며 시도 사이에 2초를 둔다. 따라서
수신측은 동일 파일명으로 연결이 반복될 수 있음을 전제로 한다.

| 상황 | 송신측 처리 |
|---|---|
| TCP 연결·TLS transport·본문·응답 실패 | 최대 3회 시도 |
| CA·cert·key·파일 오류 | 즉시 중단 |
| 서버 SAN 불일치·TLS protocol 오류 | 즉시 중단 |
| `result: "ok"` | 성공으로 기록하고 동일 경로 재전송 억제 |

수신측이 본문을 저장했지만 성공 응답이 송신측에 도달하지 않은 경우 같은 파일이 다시 올
수 있다. 저장 구현은 임시 파일을 사용하고 성공 시 최종 이름으로 교체하거나, 동일 이름을
안전하게 덮어쓸 수 있어야 한다.

## 수신측 준수 목록

| 검사 | 요구사항 |
|---|---|
| TLS | TLS 1.2 이상, `CERT_REQUIRED` |
| 클라이언트 신원 | CA 체인 통과 후 CN이 `adts-daemon` |
| 파일명 | 1~255B ASCII, 영숫자와 `._-`만 허용, `..` 금지 |
| 파일 크기 | 1B 이상 64MiB 이하 |
| 본문 | 선언된 uint64 크기만큼 정확히 수신 |
| 응답 | 첫 필드가 `result`, 성공값은 문자열 `ok` |
| 반복 전송 | 같은 파일명을 안전하게 처리 |

## 검증 기준선

2026-08-24 ARM64 Linux에서 RPi 송신 구현의 build와 정적분석을 확인했다. 카메라 수신
애플리케이션 또는 개발용 수신기와의 E2E 전송은 이 기준선에 포함하지 않는다.

| 항목 | 결과 |
|---|---|
| GNU 13.3, C11, OpenSSL·MQTT 활성 build | 통과 |
| `ADTS_NO_TLS` build | 통과 |
| cppcheck 2.13, camera module 포함 daemon 6개 translation unit | 통과 |
| 와이어 형식·제한값과 송신 구현 대조 | 일치 |
