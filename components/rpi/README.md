# Raspberry Pi

커널 드라이버(`/dev/turret`·`/dev/imu`·`/dev/led_sw`)와 통합 데몬(`adts_daemon`),
브로커·인증서 관련 문서를 둔다.

| 문서 | 담당 |
|---|---|
| [**`driver/led-sw.md`**](driver/led-sw.md) — LED, SWITCH, BUZZER 커널 드라이버 (`/dev/led_sw`) | 강유근 |
| [**`driver/imu.md`**](driver/imu.md) — ICM-20948 수평 기준 | 송영빈 |
| [**`driver/turret.md`**](driver/turret.md) — serdev 통신 및 `/dev/turret` ioctl ABI | 이현우 |
| [broker-enroll.md](broker-enroll.md) — `/enroll` 인증서·설정 발급 서비스 | 송영빈 |
| [daemon/](daemon/) — 데몬 코어 epoll FSM · 스캔 생명주기 | 이현우 |

소스 저장소의 주요 하위 계층과 같은 이름으로 문서 폴더를 구성한다.
