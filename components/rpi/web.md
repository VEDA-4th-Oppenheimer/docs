# adts-web — 폰 브라우저용 관제 서비스

Qt 콘솔의 부분집합을 웹으로 낸다. 데스크톱 콘솔을 대체하는 것이 아니라 현장에서
폰으로 스캔을 걸고 결과를 훑어보는 **보조 리모컨**이다.

- 상태: STATE / 브로커 링크 / STM32 링크 / homed / IMU roll·pitch
- 명령: SCAN · STOP · HOME · DISARM · REARM (상태에 따라 활성 — `TopBar.cpp` 와 동일)
- 진행률: `event/progress`
- TOP-VIEW: 완료된 스캔의 2D 조감도 (한 손가락 이동, 두 손가락 확대, 더블탭 맞춤)

3D 뷰와 RTSP 영상은 넣지 않았다. 전자는 WebGL 로 다시 짜야 하고, 후자는 FFmpeg
모바일 경로가 나머지 전부보다 크다. 둘 다 데스크톱 콘솔에서 보면 된다.

## 왜 브라우저가 브로커에 직접 붙지 않는가

mosquitto 는 `listener 8883` 하나만 열려 있고 `require_certificate true` 다.
브라우저를 붙이려면 WebSocket 리스너를 새로 열고 클라이언트 인증서를 폰 키체인에
심어야 하는데 모바일에서 쓸 만한 UX 가 아니다. 인증서를 빼면
`use_identity_as_username` 기반 ACL 이 통째로 무너진다.

그래서 이 서비스가 Pi 안에서 mTLS 로 브로커에 붙고, 폰과는 평범한 HTTP 로
이야기한다. 브로커 설정은 **손대지 않는다.**

```
폰 브라우저 ──HTTP(8080)──▶ adts_web.py ──mTLS(8883)──▶ mosquitto ──▶ adts_daemon
                             └─ /var/lib/adts/scans 를 직접 읽어 .pcd 제공
```

## ⚠️ 인증이 없다

도달할 수 있는 사람은 누구나 SCAN/DISARM 을 누를 수 있고, 그 명령은 **실제로
모터를 움직인다.** 단일 사용자·신뢰된 네트워크를 전제로 의도적으로 뺐다.

**인터넷에 직접 노출하지 말 것.** 포트포워딩으로 8080 을 열면 전 세계 누구나
스캐너를 조작할 수 있다. 밖에서 쓰려면 아래 VPN 방식을 쓴다.

인증을 붙일 자리는 `Handler._authorized()` 하나로 모아 두었다.

## 밖에서 쓰기 — Tailscale

포트포워딩 대신 VPN 을 쓴다. **네트워크 계층에서 인증되므로 앱에 인증이 없어도
안전하다** — 내 기기만 그 주소에 도달할 수 있다. 공유기 설정도, 고정 IP 도,
인증서도 필요 없다.

```bash
# Pi 에서
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4          # 100.x.y.z — 이 주소를 폰에서 쓴다
```

폰에 Tailscale 앱을 깔고 같은 계정으로 로그인하면 끝이다. 이동 중에도
`http://100.x.y.z:8080` 으로 붙는다.

한 걸음 더 좁히려면 서비스를 tailscale 인터페이스에만 바인드한다 — 이러면 LAN
에서조차 VPN 을 거쳐야 한다:

```
ExecStart=... --bind 100.x.y.z ...
```

WireGuard 를 직접 굴려도 되지만 공유기에 UDP 포트를 열어야 한다. Tailscale 은
그게 필요 없어서 이동 중 사용에는 이쪽이 편하다.

## 설치

```bash
# 1) 의존성 (paho-mqtt 하나뿐. HTTP 는 표준 라이브러리)
sudo apt install python3-paho-mqtt

# 2) 브로커에 붙을 인증서 발급 (CN=adts-web)
sudo bash broker/gen-certs.sh --client adts-web /etc/adts/certs

# 3) ACL 에 블록 추가 — mosquitto 의 `user` 는 정확 매칭이라 빠뜨리면
#    핸드셰이크는 되는데 발행·구독만 조용히 막힌다.
sudo tee -a /etc/mosquitto/conf.d/adts.acl >/dev/null <<'EOF'

# 폰 웹 관제 (adts_web.py)
user adts-web
topic write adts/cmd/#
topic read  adts/state/#
topic read  adts/event/#
EOF
sudo systemctl reload mosquitto

# 4) 배치 + 기동
sudo mkdir -p /opt/adts/web
sudo cp -r web/adts_web.py web/static /opt/adts/web/
sudo cp web/adts-web.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now adts-web
```

`adts-web.key` 를 `pi` 가 읽을 수 있어야 한다:

```bash
sudo setfacl -m u:pi:r /etc/adts/certs/adts-web.key
```

## 개발 중 실행

```bash
# 인증서 없이 평문 브로커로 (테스트용 mosquitto 를 1883 에 띄운 경우)
python3 web/adts_web.py --no-tls --mqtt-port 1883 --scan-dir ./scans --port 8080
```

## HTTP API

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/` | 폰 UI |
| GET | `/api/state` | 최신 상태 스냅샷 (토픽별 마지막 페이로드) |
| GET | `/api/events` | SSE — 접속 즉시 스냅샷, 이후 변경분 |
| POST | `/api/cmd/{scan,stop,home,disarm,rearm}` | 명령 발행, `{req_id}` 반환 |
| GET | `/api/scans` | `.pcd` 목록 |
| GET | `/api/scan/<파일명>` | `.pcd` 원본 |
| GET | `/healthz` | 생존 + 브로커 접속 여부 |

`POST /api/cmd/scan` 은 본문 없이 부르면 Qt 콘솔과 같은 기본값
(`pan[0,1791] tilt[-900,900] step=9`)을 쓴다. 본문으로 `pan_ddeg` / `tilt_ddeg` /
`step_ddeg` / `sensor_height_mm` 를 덮어쓸 수 있다. 값 검증은 데몬
(`scan_request_valid`)이 하므로 여기서는 흉내내지 않는다 — 두 곳에 두면 갈라진다.

## 브라우저

iOS Safari / Android Chrome 둘 다 대상이다. 쓰는 기능은 `EventSource`(SSE),
Canvas 2D, Touch Events, `fetch` 뿐이라 두 쪽 모두 오래전부터 지원한다.

iOS 쪽만 따로 손본 것들 — Android 에는 무해하다:

- `user-scalable=no` 가 iOS 10+ 에서 **무시된다.** 캔버스 핀치가 페이지 확대로
  새지 않도록 `touch-action:none` 과 Safari 전용 `gesture*` 이벤트 차단을 함께
  건다. 다른 브라우저엔 그 이벤트가 없어 리스너가 놀 뿐이다.
- 더블탭 맞춤은 탭 간격을 직접 잰다. iOS 의 `dblclick` 은 지연이 크고 확대
  제스처와 겹친다.
- `viewport-fit=cover` + `env(safe-area-inset-*)` 로 노치·홈 인디케이터를 피한다.
- `apple-mobile-web-app-*` 로 홈 화면에 추가하면 Safari UI 없이 전체화면으로
  뜬다. Android 는 같은 동작을 브라우저 메뉴의 "홈 화면에 추가"로 한다.

**화면이 꺼지면 SSE 연결이 끊긴다.** iOS 는 백그라운드 탭을 적극적으로
재우기 때문이다. `EventSource` 가 스스로 재접속하고 서버가 접속 즉시 스냅샷을
보내므로 화면을 켜면 현재 상태로 복구된다 — 다만 잠긴 동안의 진행률 갱신은
건너뛴다.

## 알아둘 것

- **스캔 후 자동 DISARM.** 데몬이 되감기 유예(15초) 뒤 스스로 DISARM 으로
  내려간다. 다음 스캔 전에 REARM 을 눌러야 한다 — 폰 UI 에서도 HOME 버튼이
  REARM 으로 바뀐다.
- **수평 게이트.** roll/pitch 가 임계(3.0도)를 넘으면 데몬이 스캔을 거부한다.
  UI 의 ROLL/PITCH 가 빨갛게 뜨면 거치대부터 잡아야 한다.
- **점군은 스캔이 끝나야 나온다.** 데몬이 격자를 다 채운 뒤 파일을 쓰므로
  스캔 중에는 진행률만 보인다. Qt 콘솔도 같다.
- **ASCII PCD 만 파싱한다.** 데몬(`write_pcd`)이 `DATA ascii` 로 쓰므로 지금은
  충분하다. 바이너리로 바꾸면 `parsePCD()` 도 같이 고쳐야 한다.
