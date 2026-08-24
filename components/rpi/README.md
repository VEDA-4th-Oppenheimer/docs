# Raspberry Pi

커널 드라이버(`/dev/turret`·`/dev/imu`·`/dev/led_sw`)와 통합 데몬(`adts_daemon`),
브로커·인증서 관련 문서를 둡니다.

| 문서 | 담당 |
|---|---|
| [driver-imu.md](driver-imu.md) — ICM-20948 수평 기준 | 송영빈 |
| [broker-enroll.md](broker-enroll.md) — `/enroll` 인증서·설정 발급 서비스 | 송영빈 |
| [turret-driver.md](turret-driver.md) — `/dev/turret` 커널 드라이버 | 이현우 |

문서가 늘어나면 `driver-*.md` / `daemon-*.md` 로 접두어를 붙이고,
각각 4~5개가 되면 그때 폴더로 나누세요.
