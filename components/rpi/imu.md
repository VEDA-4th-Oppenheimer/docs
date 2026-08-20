# IMU (ICM-20948) — 수평 기준

**원본: [IMU 센서 문서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44728356)** (Confluence) · 작성 송영빈

킷이 수평으로 거치됐는지 판정하는 경로 전체입니다.

| 계층 | 파일 |
|---|---|
| DT 오버레이 | `driver/overlays/imu-overlay.dts` — I2C1에 `imu@69` 노드 |
| 커널 드라이버 | `driver/imu_driver.c` — ICM-20948 초기화 + `/dev/imu` |
| 테스트 앱 | `driver/imu_test.c` — 실시간 roll/pitch, 영점 캘리브 |
| 데몬 모듈 | `daemon/modules/imu/imu_module.c` — 1Hz 폴링 → roll/pitch |

> **전부 RPi 쪽입니다.** STM32 펌웨어에는 IMU 코드가 없습니다 —
> STM32의 I2C 센서는 MT6701 엔코더(`App/hallEffectSensor/`)뿐입니다.
>
> MPU-6050에서 **ICM-20948로 교체된 이후 기준**입니다 (2026-08-13).

## ⚠️ 지금 이 값을 신뢰하면 안 됩니다

설치각 오프셋을 **킷이 3.6° 기울어진 상태에서** 잡아서, 보정이 기울기를 줄이는 게 아니라
키우는 상태입니다. 그래서 데몬 게이트 임계가 10.0°로 열려 있고 사실상 아무것도 막지
않습니다. 킷을 바닥평면 기준으로 세운 뒤 오프셋을 재측정해야 합니다.

Qt 경고 임계(1.5°)와 데몬 거부 임계(10.0°)가 다른 것은 **의도된 것**입니다 —
화면에 배너가 뜨는데 스캔이 그냥 도는 건 현재 정상입니다.

## 관련

- [03-3. IMU module — 6B decode·roll/pitch·offset·level gate](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42991656)
- [04-3. imu_driver — I2C·ICM-20948 bank·6B read ABI](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42795032)
- [MQTT 계약 v1.4 §3.3](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) — `state/daemon`의 `level` 객체
