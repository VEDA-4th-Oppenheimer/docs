# Raspberry Pi

커널 드라이버(`/dev/turret`·`/dev/imu`·`/dev/led_sw`)와 통합 데몬(`adts_daemon`),
브로커·인증서 관련 문서를 둔다.

| 문서 | 담당 |
|---|---|
| [driver/](driver/) — `/dev/imu`·`/dev/turret` 커널 드라이버 | 송영빈 / 이현우 |
| [broker-enroll.md](broker-enroll.md) — `/enroll` 인증서·설정 발급 서비스 | 송영빈 |
| [daemon/](daemon/) — 데몬 코어 epoll FSM · 스캔 생명주기 | 이현우 |

소스 저장소의 주요 하위 계층과 같은 이름으로 문서 폴더를 구성한다.
