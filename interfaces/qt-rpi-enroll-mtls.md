# Qt ↔ RPi 발급 서버 계약 (mTLS)

**원본: [05. mTLS·Broker·Enrollment·배포](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844783)** (Confluence)

| 하위 문서 | 내용 |
|---|---|
| [05-1. TLS·mTLS·PKI·인증서 역할과 검증](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057218) | 개념·검증 흐름 |
| [05-2. Mosquitto mTLS·CN ACL·MQTT authorization](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42696728) | 브로커 설정 |
| [05-3. Enrollment service — token·certificate·ACL·PCD download](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42795053) | 발급 서비스 |
| [05-4. systemd·install-service·운영 설정·배포 runbook](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42532870) | 배포 |

클라이언트 쪽 요구사항과 Windows 함정은
[MQTT 토픽 계약 §6](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383)에 있습니다.

## 요점만

- **포트 8883(MQTT)과 8443(HTTPS)이 같은 mTLS 인증서를 씁니다.** Qt는 파일 3개
  (`ca.crt` / `qt-console.crt` / `qt-console.key`)로 둘 다 접속합니다.
- **개인키는 저장소에 커밋하지 마세요.** `ca.key`는 RPi에만 있고 배포되지 않습니다.
- 서버 인증서가 `CN=raspberrypi`로 발급되므로, IP로 접속할 때 TLS 호스트명 검증용
  이름을 따로 지정해야 합니다.

발급 담당: 이광진
