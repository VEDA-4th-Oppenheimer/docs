# 센서

**1인 1파일.** 자기 담당 센서 파일만 고치면 서로 충돌하지 않습니다.
새 센서는 [TEMPLATE.md](TEMPLATE.md)를 복사해서 만들고, 아래 표에 한 줄 추가하세요.

| 센서 | 부품 | 인터페이스 | 상행 CMD | 담당 | 문서 |
|---|---|---|---|---|---|
| IMU | ICM-20948 | | | | [imu.md](imu.md) |
| 라이다 | NLink F2P (1D) | UART | `CMD_SCAN_DATA` (0x22) | | [lidar.md](lidar.md) |

> 새 CMD 번호가 필요하면 `shared/protocol.h`의 `enum proto_cmd`에 추가하고
> 사본을 동기화하세요. 대역은 이미 정해져 있습니다 —
> [프로토콜 문서](../../../interfaces/stm32-rpi-uart.md) 참고.
