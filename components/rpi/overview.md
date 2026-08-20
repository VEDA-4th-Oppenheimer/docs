# Raspberry Pi — 드라이버 · 통합 데몬

**원본: [RPi 저장소 README](https://github.com/VEDA-4th-Oppenheimer/RPi/blob/main/README.md)**

디렉토리 구조, 빌드(커널 드라이버 / 통합 데몬), MQTT 브로커·인증서 구축,
발급 서비스 운영, 정적분석, CODEOWNERS가 전부 거기 있습니다.

> 코드와 같은 저장소에 있어야 같은 PR에서 리뷰되고 안 썩습니다.
> 여기로 복사해오지 마세요.

## 더 자세한 것은 Confluence

| 문서 |
|---|
| [RPi 코드 기반 완전 개발 보고서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/41844741) — 01~06 시리즈 24페이지 |
| [RPi 통합 데몬 — adts_daemon](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/35848195) |
| [RPi 커널 드라이버 — /dev/turret · /dev/imu · /dev/led_sw](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/36012034) |

## ⚠️ README가 코드보다 뒤처져 있습니다 (2026-08-20 확인)

`origin/main` 기준으로 대조한 결과입니다. 저장소 README를 고칠 때 참고하세요.

| 항목 | README | 실제 코드 |
|---|---|---|
| `daemon/modules/camera/` | 디렉토리 구조에 **없음** | `camera_module.c` 865줄 구현됨 |
| `daemon/modules/led/` | "⏳ STUB — `/dev/led` 미구현" | `led_module.c` 231줄 구현됨 |

camera 모듈은 스캔 JSON을 **mTLS TCP 2222로 카메라에 직접 업로드**합니다 —
MQTT나 8443을 경유하지 않는 별도 경로라 아키텍처를 파악할 때 놓치기 쉽습니다.
→ [03-5. Camera module](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42729475)
· [03-4. LED module](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/42598413)
