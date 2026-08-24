# Raspberry Pi 커널 드라이버

`RPi/driver/`의 커널 드라이버와 디바이스별 유저 공간 계약 문서를 둔다.

| 문서 | 내용 | 담당 |
|---|---|---|
| [imu.md](imu.md) | ICM-20948 초기화, DT 오버레이, `/dev/imu` 계약 | 송영빈 |
| [turret.md](turret.md) | serdev 프레임 파서, kfifo 스캔 스트림, `/dev/turret` ioctl ABI | 이현우 |
| [led-sw.md](led-sw.md) | LED, SWITCH, BUZZER 커널 드라이버 (`/dev/led_sw`) | 강유근 |
