# 스캔 산출물 좌표계 · 포맷

**원본: [스캔 산출물 포맷 상세 — .json / .pcd 전 필드 레퍼런스](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/38240259)** (Confluence)

스캔 1회가 내놓는 두 파일(`.json` / `.pcd`)의 전 필드 레퍼런스입니다.
소비자(카메라 캘리브레이션 · Qt 뷰어)가 그 문서만 보고 파싱할 수 있게 쓰여 있습니다.

구현은 `RPi/daemon/core/scan_output.c` — 좌표 변환식은 그 파일 하나에만 있습니다.

> 여기에 필드 표를 복사해두지 않는 이유는 [작성 규칙 0번](../CONTRIBUTING.md)과 같습니다.
> Confluence 쪽이 계속 갱신되므로 사본은 만든 순간부터 낡습니다.

## 처음 읽는다면 이것만

세 가지가 반복해서 사고를 냅니다. 나머지는 원본을 보세요.

1. **`r = distance_m + sensor.range_offset_m`** — 빼먹으면 장면 전체가 84mm 수축합니다.
   평면 잔차로는 안 잡히고 곡률로 나타나서, 캘리브가 미묘하게 안 맞는데 원인을 못 찾는 형태가 됩니다.
2. **각도가 두 종류입니다.** `measurements[].tilt_rad`는 **계약각**(0 = 수평),
   `mechanism.tilt_zero = "nadir"`는 **기구각**의 영점입니다. 후자를 φ 정의로 읽으면 전체가 90° 틀어집니다.
3. **`sensor_height_m`은 좌표에 안 들어가 있습니다.** frame이 `lidar_scan`이라 원점이 라이다 자신입니다.

## 관련

- [MQTT 토픽 계약](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/31162383) — 파일 경로가 실려 오는 `state/scan`
- [02-4. 기구각→계약각·organized grid·셀 병합](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/43057196)
- [components/stm32/sensors/lidar.md](../components/stm32/sensors/lidar.md) — STM32 쪽 상행 계약
