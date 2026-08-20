# 센서 (STM32)

**1인 1파일.** 자기 담당 센서 파일만 고치면 서로 충돌하지 않습니다.
새 센서는 [TEMPLATE.md](TEMPLATE.md)를 복사해서 만들고, 아래 표에 한 줄 추가하세요.

| 센서 | 부품 | 인터페이스 | 상행 CMD | 담당 | 문서 |
|---|---|---|---|---|---|
| 라이다 | NLink F2P (1D) | USART6 | `CMD_SCAN_DATA` (0x22) | 송영빈 | [lidar.md](lidar.md) |
| 엔코더 | MT6701 ×2 | I2C1 / I2C3 | `CMD_HOMED` (0x20) | | [명세 v2.2](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/20283415) |

> **IMU는 여기 없습니다.** ICM-20948은 RPi I2C1에 붙어 있고 STM32 펌웨어에는
> IMU 코드가 없습니다 → [components/rpi/imu.md](../../rpi/imu.md)

> 새 CMD 번호가 필요하면 `shared/protocol.h`의 `enum proto_cmd`에 추가하고
> 사본을 동기화하세요 → [프로토콜 문서](../../../interfaces/stm32-rpi-uart.md)
