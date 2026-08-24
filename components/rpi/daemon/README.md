# Raspberry Pi 통합 데몬

`RPi/daemon/`의 이벤트 루프, 상태머신과 모듈 구현 문서를 둔다.

| 문서 | 내용 | 담당 |
|---|---|---|
| [core.md](core.md) | 단일 스레드 epoll, heartbeat, 스캔 상태머신과 종료 정책 | 이현우 |
| [scan-output.md](scan-output.md) | organized 격자 병합과 JSON·PCD writer 구현 | 이현우 |
| [modules.md](modules.md) | 정적 모듈 계약 v5, 공유 상태 소유권과 콜백 순서 | 이현우 |
| [camera.md](camera.md) | `ST_EXPORT` 카메라 mTLS 송신 모듈 | 이현우 |
