# Qt 관제 콘솔 — SPATIAL·VMS

**원본: [QT proto v2](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/40435717)** (Confluence) · 작성 송영빈
· 이전 버전 [QT v1](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31522817)

앱 구조, RTSP 4채널, MQTT 연동, 화면·조작, 포인트클라우드 렌더, 설치·설정,
배포 패키징, Demo Mode, 트러블슈팅, 소스 구조까지 있습니다.

## 알아둘 것 하나

**영상 경로와 제어 경로는 완전히 독립적입니다.** 카메라는 RPi를 거치지 않고 Qt가 직접
RTSP로 받습니다 — 카메라가 죽어도 스캔은 되고, 브로커가 죽어도 영상은 나옵니다.
"Qt가 왜 영상 토픽을 구독하지 않느냐"는 질문이 반복돼 왔는데, 애초에 MQTT를 타지 않는 설계입니다.

관련: [MQTT 토픽 계약 v1.4](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) — 토픽·페이로드·Qt 구현 체크리스트
· [빌드·배포](build-and-deploy.md)
