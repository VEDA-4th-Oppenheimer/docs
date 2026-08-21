# 발급 서비스 (`/enroll`) — Qt 콘솔 인증서·설정 배포

Qt 관제 콘솔이 킷에 붙는 데 필요한 것(mTLS 인증서, 브로커 주소, 카메라 설정)을
**1회용 토큰 하나와 맞바꿔** 내려주는 HTTPS 서비스입니다. RPi 에 상주하며 브로커
ACL 까지 같이 갱신합니다.

| 항목 | 값 |
|---|---|
| 저장소 | `VEDA-4th-Oppenheimer/RPi` — `broker/` |
| 기준 | `origin/main` `2a683ee` (2026-08-21) |
| 담당 | 송영빈 (발급 서비스·토큰 CLI·스캔 조회) / 이현우 (브로커 운영·CA 스크립트) |
| 바이너리 | `adts_enroll` — C11, OpenSSL + cJSON, 849줄 |
| 포트 | HTTPS **8443** (발급·스캔 조회) / MQTT **8883** (내려주는 값) |

## 1. 구성

| 파일 | 역할 |
|---|---|
| `broker/enroll_service.c` | 발급 서비스 본체. TLS 종단, 토큰 검증, 서명 위임, ACL 갱신, 스캔 조회 |
| `broker/CMakeLists.txt` | `adts_enroll` 빌드 (데몬과 별도 타깃) |
| `broker/adts-enroll.service` | systemd 유닛 |
| `broker/gen-certs.sh` | CA·서버·클라이언트 인증서 발급 + **관리자용 토큰 CLI** |
| `broker/enroll_tokens.example` | 토큰 파일 형식 예시 |
| `broker/mosquitto.conf.example` · `mosquitto.acl.example` | 브로커 설정·권한 예시 |

**데몬과 별도 타깃인 이유** — 발급은 사람이 가끔 하는 운영 작업이고 데몬은 상주
프로세스라 수명주기가 다릅니다. 같은 빌드에 묶으면 데몬을 고칠 때마다 발급 서비스가
재기동됩니다.

## 2. 왜 배포본에 인증서를 넣지 않는가

Qt 배포본에는 인증서도 카메라 설정도 담지 않습니다.

- 인증서에는 **`adts/cmd/#` 쓰기 권한**이 있습니다 — 받은 사람이 장비를 움직일 수 있습니다.
- 카메라 설정에는 **카메라 admin 비밀번호가 RTSP URL 에 박혀** 있습니다.

배포물에 넣으면 받은 사람 **전원**이 그 권한을 갖습니다. 그래서 사람마다 다른 CN 으로
따로 발급하고, 그 통로가 이 서비스입니다.

반대 방향의 신뢰는 Qt 실행파일에 박아둔 `ca.crt` 가 담당합니다. 발급 시점에는 클라이언트
인증서가 아직 없어서 서버를 검증할 근거가 그것뿐입니다. `ca.crt` 는 **공개** 인증서라
배포본에 들어가도 안전하고, CA 를 재발급하면 이 파일도 같이 갱신해야 합니다.

## 3. 발급 흐름

```mermaid
sequenceDiagram
    participant A as 관리자
    participant Q as Qt 콘솔
    participant E as adts_enroll
    participant G as gen-certs.sh
    participant M as mosquitto

    A->>A: gen-certs.sh --new-token youngbin
    A-->>Q: 토큰 + 서버주소 전달 (사람 손으로)
    Q->>E: POST /enroll {token, device_name}
    E->>E: 토큰 검증 (아직 소비하지 않음)
    E->>G: fork/exec --client qt-console-youngbin
    G-->>E: <CN>.crt / <CN>-trad.key
    E->>M: adts.acl 에 CN 블록 추가 + systemctl reload
    E->>E: 토큰 소비 (파일에서 삭제)
    E-->>Q: 200 {cn, ca_crt, client_crt, client_key, mqtt, cameras}
    Q->>M: mqtts://host:8883 mTLS 접속
```

**토큰 소비가 마지막인 것이 핵심입니다.** 3절의 순서를 지키지 않으면 사용자가 아무것도
못 받았는데 토큰만 사라집니다(5.2절).

## 4. `POST /enroll` 계약

```
POST https://<host>:8443/enroll
Content-Type: application/json

    {"token": "...", "device_name": "..."}

200 {"cn":"qt-console-<라벨>",
     "ca_crt":"-----BEGIN CERTIFICATE-----\n...",
     "client_crt":"-----BEGIN CERTIFICATE-----\n...",
     "client_key":"-----BEGIN RSA PRIVATE KEY-----\n...",
     "mqtt":{"host":"...","port":8883},
     "cameras":{"channels":{"1":"rtsp://...", ...}}}
```

| 코드 | 사유 |
|---|---|
| 400 | `Content-Length` 없음 / 본문 크기 이상(8KB 초과) / JSON 파싱 실패 / `token` 없음 |
| 401 | **토큰이 유효하지 않거나 이미 사용됨** |
| 404 | 없는 경로 |
| 500 | 인증서 발급 실패 / ACL 갱신 실패 / 라벨이 CN 으로 쓸 수 없는 문자 |

> **401 은 "틀렸다"와 "이미 썼다"를 구분해 주지 않습니다.** 구분해 주면 공격자가 유효한
> 토큰 공간을 좁힐 수 있습니다. 로그에는 둘 다 남습니다.

**`mqtt.host` 의 기본값은 요청의 `Host` 헤더**입니다. 클라이언트가 IP 로 접속하면 그 IP 가
그대로 내려가므로 대개 설정할 필요가 없고, 브로커가 다른 호스트에 있을 때만
`ADTS_MQTT_HOST` 로 지정합니다.

**`cameras` 는 없어도 진행합니다.** 없으면 경고만 남기고 응답에서 뺍니다 — MQTT 는 되고
영상만 안 나오는 상태가 됩니다. 등록 자체를 실패시키면 카메라 설정이 준비되기 전에는
아무도 못 붙습니다.

## 5. 토큰

### 5.1 형식과 수명주기

파일은 `/etc/adts/enroll_tokens`, 권한 600. 한 줄에 하나입니다.

```
# 1회용 발급 토큰 — '<토큰> <라벨>' 한 줄에 하나. 사용되면 자동으로 지워진다.
3f9a1c…  youngbin
b70e42…  hyunwoo
```

**라벨이 CN 접미사가 됩니다** — `qt-console-<라벨>`. 관리자가 "누구에게 준 토큰인지"를
토큰 생성 시점에 정하게 하려는 것입니다.

토큰은 `openssl rand -hex 24`(24바이트 = 48자)로 만듭니다.

### 5.2 왜 검증과 소비를 나눴나

`token_take(token, label, commit)` 이 `commit` 플래그로 두 번 불립니다.

| 시점 | `commit` | 하는 일 |
|---|---|---|
| 요청 직후 | `false` | 토큰이 있는지 확인만. 파일은 그대로 |
| 발급 + ACL 성공 후 | `true` | 그 줄을 지우고 파일을 **원자적으로 교체** |

> 예전에는 **찾자마자 지우고** 인증서를 발급했습니다. 발급이나 ACL 갱신이 실패하면
> 사용자는 아무것도 못 받았는데 토큰은 사라져서, 관리자가 새 토큰을 만들어 주기 전까지
> 재시도할 방법이 없었습니다.

교체는 `<파일>.tmp` 에 쓴 뒤 `chmod 600` → `rename()` 입니다. `rename` 이 원자적이라
중간에 죽어도 반쪽짜리 토큰 파일이 남지 않습니다.

**소비 단계에서 실패하면 응답은 그대로 보냅니다.** 인증서는 이미 나갔으므로 사용자를
막을 이유가 없고, 대신 "같은 토큰이 다시 쓰일 수 있음" 경고를 로그에 남겨 관리자가 손으로
지우게 합니다.

> 검사-후-소비 사이에 다른 요청이 끼어들 수 없는 것은 **단일 스레드 accept 루프**이기
> 때문입니다(9절). 나중에 동시 처리를 넣으면 이 가정이 깨집니다.

### 5.3 비교는 상수 시간

```c
CRYPTO_memcmp(tok, token, tok_len) == 0
```

`strcmp` 는 첫 불일치에서 끊깁니다. 그 시간 차로 토큰을 앞에서부터 한 글자씩 맞춰 갈 수
있어서 OpenSSL 의 상수 시간 비교를 씁니다. 길이는 미리 비교합니다.

### 5.4 관리자 CLI

```bash
bash gen-certs.sh --new-token <라벨>    # 생성 + 등록 + 팀원 전달문 출력
bash gen-certs.sh --list-tokens         # 미사용 토큰 목록
bash gen-certs.sh --revoke <라벨>       # 해당 라벨의 미사용 토큰 회수
```

- **`--list-tokens` 는 토큰 전문을 찍지 않습니다** — 앞 6자와 뒤 4자만 보여줍니다. 화면이나
  터미널 로그에 남으면 그 자체가 접근 권한입니다.
- **라벨 검증은 토큰을 만들 때** 합니다(영숫자 + `.` `_` `-`). 발급 시점에 걸러면 "토큰은
  받았는데 발급이 500" 이 됩니다. CN 은 파일명과 ACL 한 줄에 그대로 들어가므로 문자 집합을
  좁혀야 경로 조작·ACL 구문 훼손을 막습니다. 서비스 쪽에도 `cn_is_safe()` 로 같은 검사가
  한 번 더 있습니다.
- 같은 라벨의 미사용 토큰이 이미 있으면 경고합니다. 여러 개 있어도 동작은 하지만(먼저 쓴
  것만 유효) 관리자가 헷갈립니다.

## 6. 인증서 서명

서명 로직을 서비스 안에 다시 구현하지 않고 **`gen-certs.sh --client <CN>` 을 `fork`/`exec`
로 호출**합니다. 여기서 다시 짜면 확장(`v3_client`)이나 키 포맷 같은 세부가 두 곳으로
갈라집니다.

```c
char *bash_argv[] = { "/bin/bash", g_gen_certs, "--client", cn, g_cert_dir, NULL };
```

**셸을 거치지 않습니다**(`execv`) — 인자에 무엇이 들어와도 명령 인젝션이 성립하지 않습니다.
`bash` 를 명시적으로 부르는 이유는 스크립트의 실행권한과 shebang 에 의존하지 않기 위해서고요.

서명 결과에서 세 가지가 중요합니다.

| 항목 | 이유 |
|---|---|
| `-extensions v3_client` | 빠지면 **mTLS 핸드셰이크에서 거부**됩니다 |
| 전통 RSA 포맷 `<CN>-trad.key` | Qt `QSslKey` 가 OpenSSL 3.x 기본인 PKCS#8 을 `QSsl::Rsa` 로 읽으면 **null 을 반환하고 조용히 실패**합니다. 그래서 변환본을 같이 만들어 이걸 내려줍니다 |
| CA 키는 장비 밖으로 안 나감 | 서명은 전부 이 프로세스 안에서 이뤄집니다. 그래서 서비스가 root 로 돕니다 |

**재발급**(로그아웃 후 재등록 등)이면 기존 파일을 지우고 새로 만듭니다.

> 주의: **파일을 지운다고 이전 인증서가 폐기되지 않습니다.** 암호학적으로 여전히
> 유효합니다. 실제로 무효화하려면 브로커에 `crlfile` 을 걸고 폐기 목록에 올려야 합니다.
> 지금은 CRL 이 없습니다(11절).

## 7. ACL 자동 등록 — 가장 놓치기 쉬운 곳

mosquitto 의 `user` 는 **정확 매칭이고 와일드카드가 없습니다.** 발급할 때마다 CN 블록을
직접 붙여야 합니다.

```
user qt-console-youngbin
topic write adts/cmd/#
topic read  adts/state/#
topic read  adts/event/#
```

> **빠뜨리면 TLS 핸드셰이크는 성공하는데 구독·발행만 조용히 막힙니다.** 인증서도 정상,
> 연결도 정상, 그런데 아무 메시지도 안 오갑니다. 원인을 찾기 가장 어려운 형태라
> 발급 서비스가 자동으로 붙이도록 만들었습니다.

이미 있으면 추가하지 않습니다(`\nuser <CN>\n` 로 탐색). 그 뒤 브로커를 갱신합니다.

```c
systemctl reload mosquitto      /* restart 가 아니다 */
```

**`reload`(SIGHUP)는 ACL 만 다시 읽습니다.** `restart` 를 쓰면 붙어 있던 클라이언트가 전부
끊깁니다 — 스캔 중이면 그대로 날아갑니다.

권한 판정은 **Client ID 가 아니라 인증서 CN** 으로 이뤄집니다(`use_identity_as_username
true`). Qt 는 동시 접속 시 서로 끊기지 않도록 `qt-console-<호스트명>-<난수>` 로 매번 다른
Client ID 를 쓰는데, 그래도 ACL 은 그대로 쓸 수 있는 이유가 이것입니다.

## 8. 스캔 파일 조회

Qt 가 `state/scan` 으로 파일 **경로**를 받아도 그 파일을 실제로 가져갈 수단이 없었습니다.
발급 서비스에 읽기 전용 경로를 얹어 **이미 있는 mTLS 신뢰를 재사용**합니다.

```
GET /scans              → {"scans":[{"name":..., "size":..., "mtime":...}, ...]}
GET /scan/<파일명>      → 파일 본문
GET /healthz            → {"ok":true}
```

인증서를 발급하는 서비스에 파일 경로를 여는 것이라 **세 겹으로 막습니다.**

| 겹 | 내용 |
|---|---|
| ① | **검증된 클라이언트 인증서를 요구.** 핸들러가 `SSL_get1_peer_certificate` + `SSL_get_verify_result == X509_V_OK` 를 직접 확인하고, 아니면 401 |
| ② | **파일명만 받는다.** `/` 나 `%` 가 하나라도 있으면 거부. `..` 포함 거부. 디렉터리는 `ADTS_SCAN_DIR` 로 고정이라 경로 탈출이 성립할 수 없다 |
| ③ | **`.pcd` 확장자만.** 길이 1~160, 영숫자와 `-` `_` `.` 만 |

> **`%` 를 디코드하지 않고 그냥 거부하는 이유** — 스캔 파일명은 영숫자와 `-_.` 뿐이라
> 인코딩이 필요 없습니다. 디코더를 두면 그 자체가 새로운 우회 표면이 됩니다.

`/scans` 는 **경로를 주지 않습니다.** 파일명·크기·수정시각만 줍니다 — 클라이언트는 파일명만
알면 되고 서버가 디렉터리를 고정하고 있어서 경로를 노출할 이유가 없습니다. 한 번에 최대
500건입니다.

## 9. TLS 설정과 동시성

### 9.1 인증서를 "받되 없어도 통과"

```c
SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);   /* FAIL_IF_NO_PEER_CERT 는 켜지 않는다 */
```

두 경로의 요구가 정반대라서 이렇게 됩니다.

- `/enroll` 은 **인증서를 발급받기 전에** 부르는 곳이라 인증서를 요구할 수 없습니다.
- `/scan`·`/scans` 는 파일을 내주므로 검증된 인증서를 요구합니다.

그래서 핸드셰이크는 누구나 되게 두고, **판정을 핸들러에서** 합니다. 최소 버전은 TLS 1.2.

클라이언트 CA 를 못 읽으면 경고만 남기고 계속 뜹니다 — `/enroll` 은 그래도 돌아야 하기
때문입니다. 대신 `/scan` 계열은 그 상태에서 항상 거부됩니다.

### 9.2 단일 스레드 + 소켓 마감시간

한 연결씩 처리합니다. 발급은 사람이 하루 몇 번 하는 작업이라 성능이 문제되지 않고, 토큰
파일과 ACL 파일을 동시에 건드릴 일이 없어 **잠금 없이 안전**합니다. 인증서를 다루는
코드에서는 그 단순함이 장점입니다.

대신 한 연결이 멈추면 **그동안 아무도 발급받지 못하고 스캔 다운로드도 막힙니다.**

```c
#define CLIENT_TIMEOUT_S 20        /* SO_RCVTIMEO / SO_SNDTIMEO */
```

> 이게 없으면 **접속만 하고 아무것도 안 보내는 클라이언트 하나로 서비스 전체가 정지**합니다
> (`SSL_accept` 의 첫 read 에서 무한정 기다림). 단일 스레드라 이 값이 그대로 "서비스 전체가
> 멈출 수 있는 시간" 입니다.

`SIGPIPE` 는 무시합니다 — 클라이언트가 먼저 끊어도 프로세스가 죽지 않게.

### 9.3 크기 상한

| 상수 | 값 | 대상 |
|---|---|---|
| `MAX_HEADER` | 8 KB | HTTP 헤더 |
| `MAX_BODY` | 8 KB | 요청 본문 |
| `MAX_PEM` | 64 KB | 읽어들이는 PEM·JSON 파일 |
| `MAX_CN` | 128 B | CN |
| `MAX_LABEL` | 64 B | 토큰 라벨 |

## 10. 배치

### 10.1 빌드

```bash
sudo apt install libssl-dev libcjson-dev
cmake -S broker -B broker/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build broker/build
```

컴파일 게이트는 데몬과 같습니다 — **경고를 에러로** 봅니다.

```
-Wall -Wextra -Werror -O2 -fstack-protector-all -D_FORTIFY_SOURCE=2 -fPIE
-pie -z relro -z now
```

### 10.2 설치

```bash
sudo mkdir -p /var/lib/adts/scans && sudo chown pi:pi /var/lib/adts/scans
sudo cp broker/build/adts_enroll /opt/adts/
sudo cp broker/gen-certs.sh      /opt/adts/
sudo cp broker/adts-enroll.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now adts-enroll
```

> 실행 중인 바이너리를 덮어쓰면 `Text file busy` 가 납니다. **stop → cp → start** 순서로
> 하십시오.

### 10.3 유닛에서 눈여겨볼 것

| 지시자 | 값 | 이유 |
|---|---|---|
| `User` | `root` | CA 개인키를 읽고 `systemctl reload mosquitto` 를 해야 함 |
| `After` | `mosquitto.service` | 브로커가 떠 있어야 발급 직후 ACL reload 가 의미를 가짐 |
| `ProtectSystem` | `full` | root 로 도는 만큼 범위를 좁힘 |
| `ReadWritePaths` | `/etc/adts` `/etc/mosquitto/conf.d` | 쓰기가 필요한 곳만 |
| `ProtectHome` | `true` | **`/home` 아래는 경로가 맞아도 열리지 않음** — 12.2절 |
| `Restart` | `on-failure` (5초) | |

설정은 전부 환경변수로 덮습니다.

```
ADTS_CERT_DIR=/etc/adts/certs          ADTS_TOKEN_FILE=/etc/adts/enroll_tokens
ADTS_CAMERA_FILE=/etc/adts/cameras.json ADTS_ACL_FILE=/etc/mosquitto/conf.d/adts.acl
ADTS_GEN_CERTS=/opt/adts/gen-certs.sh   ADTS_SYSTEMCTL=/bin/systemctl
ADTS_SCAN_DIR=/var/lib/adts/scans       ADTS_BIND_PORT=8443
ADTS_MQTT_PORT=8883                     ADTS_MQTT_HOST=  (비면 Host 헤더)
```

`ADTS_SYSTEMCTL` 을 굳이 빼둔 이유는 배포판마다 위치가 다르고, 테스트에서 대체할 수 있어야
하기 때문입니다.

## 11. 되돌린 결정 · 겪은 문제

### 11.1 카메라 설정 retained 배포 — 넣었다가 뺐다

**넣은 이유** (`012830d`, 2026-08-05): `/enroll` 응답의 `cameras` 는 **등록 시점에 한 번 박히고
끝**이라, 카메라 IP 가 바뀌면 이미 등록한 사람에게 전달할 방법이 없었습니다. 등록 시점에
서버에 `cameras.json` 이 없었던 사람은 영구히 영상 없이 남기도 했습니다(실제로 겪음).
그래서 `publish-config.sh` 로 `adts/config/cameras` 에 **retained** 발행하도록 만들었습니다.
나중에 켜는 콘솔도 접속 즉시 현재 값을 받아야 해서 retained 였습니다.

**뺀 이유** (`af1adf9`, 2026-08-05): 카메라는 RPi 와 **물리적으로 떨어져 있고 데몬은 카메라를
건드리지 않습니다.** RTSP 는 Qt 가 카메라로 직접 연결하므로 RPi 를 배포처로 삼을 이유가
없었습니다. 오히려 서버에 `cameras.json` 이 없으면 "등록은 성공했는데 영상만 없음" 이 되어
원인을 찾기 어려웠습니다(두 번 발생). Qt 가 등록 화면에서 카메라 정보를 직접 받도록
바뀌면서 이쪽을 지웠습니다 — `publish-config.sh` 삭제, ACL 에서 `adts/config/#` 권한 제거,
발급 서비스가 새 CN 블록에 붙이던 config 읽기 줄 제거.

> 남은 절충: 지금도 서버에 `cameras.json` 이 있으면 `/enroll` 응답에 실어 보냅니다. 다만
> **폴백**이고, 사용자가 등록 화면에서 넣은 값이 우선입니다.

### 11.2 `GET /scans` 가 배포 직후 404

두 값이 저장소 안에서 어긋나 있었습니다(`9ae2f9f`, 2026-08-07).

- `DEF_SCAN_DIR` 이 `/home/pi/final_project/scans` 인데 유닛에 **`ProtectHome=true`** 가
  걸려 있었습니다. 홈 아래는 경로가 맞아도 열리지 않으므로 그 기본값은 성립할 수 없습니다.
- 데몬(`SCAN_OUT_DIR`)은 `/var/lib/adts/scans` 를 1순위로 쓰지만, 그 디렉터리가 없으면
  **작업 디렉터리의 `./scans` 로 조용히 폴백**합니다. 데몬을 홈에서 띄우면 파일은 홈 아래
  쌓이고 서비스는 하나도 못 보는 상태가 됩니다.

기본값을 데몬과 같은 `/var/lib/adts/scans` 로 맞추고 유닛에도 명시했습니다. **값을 바꾼 게
아니라 원래 의도였던 곳으로 되돌린 것**입니다.

### 11.3 `pipefail` 에 토큰만 날아감

`--new-token` 이 전달문에 넣을 서버 IP 를 `hostname -I` 로 추정하는데, 이건 리눅스
전용이라 없는 환경이 있습니다. `set -o pipefail` 이 켜져 있어서 그 실패가 그대로 올라오면
**토큰은 이미 파일에 쓰인 뒤라 안내문 없이 죽습니다.** 실제로 겪었고,
`{ hostname -I 2>/dev/null || true; }` 로 감싸 해결했습니다.

## 12. 알려진 한계

**① CRL 이 없습니다.** ACL 블록을 지우면 그 CN 으로 아무것도 못 하게 되지만, **인증서 자체는
여전히 유효해서 브로커 연결(TLS 핸드셰이크)은 됩니다.** 기기 분실 대응이 필요하면
`mosquitto.conf` 에 `crlfile` 을 걸고 인증서를 폐기 목록에 올려야 합니다.

**② 실장비 왕복 검증이 안 된 구간이 있습니다.** `GET /scans`·`GET /scan/<파일명>` 은
실장비에서 재빌드·재기동해 끝까지 왕복 확인한 적이 없습니다(`84251db` 커밋 메모).

**③ 동시 처리를 넣으면 토큰 로직이 깨집니다.** 5.2절의 검사-후-소비가 단일 스레드 가정 위에
서 있습니다. 잠금 없이 스레드를 붙이면 같은 토큰으로 두 장이 발급될 수 있습니다.

**④ 공용 CN `qt-console` 이 아직 ACL 에 남아 있습니다.** `gen-certs.sh` 전체 발급이 만드는
개발용 인증서입니다. 사람별 발급으로 완전히 전환하면 지워야 합니다.

**⑤ 토큰 만료가 없습니다.** 1회용이지만 시간 제한은 없어서, 나눠주고 안 쓴 토큰은 회수하기
전까지 계속 유효합니다.
