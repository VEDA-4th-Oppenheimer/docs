# 발급 토큰 운영 (관리자용)

팀원에게 Qt 관제 콘솔 접속 권한을 주고, 회수하고, 문제가 생겼을 때 확인하는 절차를
정리한다. 전부 **RPi 에서** 실행한다.

| 항목 | 값 |
|---|---|
| 문서 ID | `ADTS-ENR-51` |
| 담당 | 송영빈 |
| 기준 코드 | RPi `2a683ee` (2026-08-21) |
| 도구 | `RPi/broker/gen-certs.sh` |
| 서비스 | `adts-enroll.service` (`/opt/adts/adts_enroll`) |
| 토큰 파일 | `/etc/adts/enroll_tokens` (권한 600) |
| ACL 파일 | `/etc/mosquitto/conf.d/adts.acl` |

---

## 1. 팀원 한 명에게 권한 주기

```bash
sudo bash /opt/adts/gen-certs.sh --new-token Youngbin
```

라벨(`Youngbin`)이 **CN 접미사**가 된다 — 발급되면 `qt-console-Youngbin` 이다. 영숫자와
`.` `_` `-` 만 쓸 수 있고, 라벨 검사는 이 시점에 한다.

출력에 그대로 전달하면 되는 안내문이 나온다.

```
    발급 서버 주소 : 172.20.32.110
    포트           : 8443
    토큰           : 3f9a1c…
```

이걸 팀원에게 주면 끝이다. 팀원은 SPATIAL·VMS 를 처음 실행할 때 뜨는 등록 창에 넣고
`발급받기` 를 누른다. 인증서·브로커 주소·카메라 설정이 한 번에 들어가고, **ACL 등록까지
서비스가 자동으로** 한다.

> 서버 주소는 `hostname -I` 의 첫 IPv4 를 추정한 값이다. RPi 에 인터페이스가 여럿이면
> 틀릴 수 있으니 **팀원이 실제로 접속할 주소인지 확인하고 전달**한다.

같은 라벨로 아직 안 쓴 토큰이 있으면 경고가 뜬다. 여러 개 있어도 동작은 하지만(먼저 쓴
것만 유효) 헷갈리므로 회수하고 새로 만드는 편이 낫다.

## 2. 나눠준 토큰 확인

```bash
sudo bash /opt/adts/gen-certs.sh --list-tokens
```

```
미사용 토큰 (/etc/adts/enroll_tokens)
─────────────────────────────────────────────
  Youngbin             3f9a1c…8b2e
  Hyunwoo              b70e42…c015
```

**토큰 전문은 안 찍는다** — 앞 6자와 뒤 4자만 나온다. 화면이나 터미널 로그에 남으면 그
자체가 접근 권한이기 때문이다. 여기 안 보이면 **이미 쓰였거나 회수된 것**이다.

## 3. 회수

```bash
sudo bash /opt/adts/gen-certs.sh --revoke Youngbin
```

해당 라벨의 **미사용** 토큰만 지운다. 이미 발급이 끝난 사람에게는 아무 영향이 없다 —
그건 5절이다.

## 4. 발급이 잘 됐는지 확인

```bash
# 인증서가 생겼나
sudo ls -l /etc/adts/certs/qt-console-Youngbin.*

# ACL 에 블록이 붙었나
sudo grep -A3 'user qt-console-Youngbin' /etc/mosquitto/conf.d/adts.acl

# 서비스 로그
sudo journalctl -u adts-enroll -n 30 --no-pager
```

정상이면 로그에 이렇게 남는다.

```
INFO  ACL 에 qt-console-Youngbin 추가
INFO  발급 완료: CN=qt-console-Youngbin device=youngbin-macbook from=172.20.32.55
```

## 5. 접속 끊기 (사람이 나갔을 때)

ACL 에서 해당 블록을 지우고 브로커를 다시 읽힌다.

```bash
sudo nano /etc/mosquitto/conf.d/adts.acl      # user qt-console-Youngbin 블록 4줄 삭제
sudo systemctl reload mosquitto
```

`reload`(SIGHUP)는 ACL 만 다시 읽는다. **`restart` 를 쓰면 붙어 있던 클라이언트가 전부
끊긴다** — 스캔 중이면 그대로 날아간다.

> **주의: ACL 삭제는 "그 CN 으로 아무것도 못 하게" 만들 뿐이다.** 인증서 자체는 여전히
> 유효해서 브로커 연결(TLS 핸드셰이크)까지는 된다. 연결 자체를 막으려면
> `mosquitto.conf` 에 `crlfile` 을 걸고 인증서를 폐기 목록에 올려야 하는데, **지금은
> CRL 이 없다.** 기기 분실 대응이 필요하면 그때 붙여야 한다.

같은 사람이 다시 들어오면 1절을 그대로 반복하면 된다. 같은 CN 으로 재발급하면 서비스가
기존 파일을 지우고 새로 만들고, 로그에 재발급 경고를 남긴다.

## 6. 서비스 갱신·재기동

```bash
sudo systemctl stop adts-enroll
sudo cp broker/build/adts_enroll /opt/adts/
sudo systemctl start adts-enroll
```

> **실행 중인 바이너리를 덮어쓰면 `Text file busy` 가 난다.** 반드시 stop → cp → start
> 순서로 한다.

스캔 디렉터리는 배포 전에 미리 만들어 둔다.

```bash
sudo mkdir -p /var/lib/adts/scans && sudo chown pi:pi /var/lib/adts/scans
```

## 7. 증상별 확인 순서

| 증상 | 먼저 볼 것 |
|---|---|
| 등록 창에서 "토큰이 유효하지 않거나 이미 사용되었다" | `--list-tokens` 에 있나. 없으면 이미 쓰인 것 |
| 등록은 됐는데 **영상만 안 나온다** | `/etc/adts/cameras.json` 유무. 없어도 발급은 성공한다(설계) |
| 등록은 됐는데 **MQTT 만 안 붙는다** | ACL 에 CN 블록이 붙었나(4절). 가장 흔한 원인 |
| 인증서는 다 받았는데 mTLS 만 실패 | 키가 전통 RSA 인가. PKCS#8 이면 Qt 가 조용히 실패한다 |
| **스캔만** 안 받아진다 (등록은 됨) | 서비스가 클라이언트 CA 를 못 읽은 상태. 기동 로그의 `클라이언트 CA … 읽지 못했습니다` 경고 |
| `GET /scans` 가 404 | `ADTS_SCAN_DIR` 이 실제 디렉터리인가. 유닛에 `ProtectHome=true` 라 `/home` 아래는 안 열린다 |
| 발급이 아예 안 걸린다 | `systemctl status adts-enroll`, 8443 포트, 방화벽 |

## 8. 알아둘 것

- **토큰은 만료가 없다.** 1회용이지만 시간 제한이 없어서, 나눠주고 안 쓴 토큰은 회수 전까지
  계속 유효하다. 오래된 것은 주기적으로 `--revoke` 한다.
- **CA 개인키는 RPi 밖으로 내보내지 않는다.** 서명은 전부 발급 서비스 안에서 이뤄지고,
  그래서 서비스가 root 로 돈다.
- **발급 서비스는 한 번에 한 연결만 처리한다.** 여러 명이 동시에 등록을 누르면 순서대로
  처리되고, 한 연결이 멈춰도 최대 20초 뒤에는 풀린다.
- 공용 CN `qt-console` 이 아직 ACL 에 남아 있다. `gen-certs.sh` 전체 발급이 만드는
  개발용이며, 사람별 발급으로 완전히 전환하면 지운다.
