# IMU (ICM-20948) — 수평 기준

**원본: [IMU 센서 문서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44728356)** (Confluence) · 작성 송영빈

킷이 수평으로 거치됐는지 판정하는 경로 전체 — DT 오버레이 → 커널 드라이버(`/dev/imu`)
→ 테스트 앱 → 데몬 모듈(1Hz 폴링 → roll/pitch)입니다.

> **MPU-6050에서 ICM-20948로 교체된 이후 기준**입니다 (2026-08-13).
> 교체로 무엇이 바뀌고 무엇이 그대로인지는 원본 2절에 정리돼 있습니다.

## ⚠️ 지금 이 값을 신뢰하면 안 됩니다

설치각 오프셋을 **킷이 3.6° 기울어진 상태에서** 잡아서, 보정이 기울기를 줄이는 게 아니라
키우는 상태입니다. 그래서 데몬 게이트 임계가 10.0°로 열려 있고 사실상 아무것도 막지
않습니다. 킷을 바닥평면 기준으로 세운 뒤 오프셋을 재측정해야 합니다.
→ [MQTT 계약 v1.4 §3.3](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383)

관련: [03-3. IMU module — 6B decode·roll/pitch·offset·level gate](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42991656)
