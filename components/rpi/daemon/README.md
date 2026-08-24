# Raspberry Pi 통합 데몬

`RPi/daemon/`의 이벤트 루프, 상태머신, 모듈 ABI와 배포 문서를 둔다.

| 문서 | 내용 | 담당 |
|---|---|---|
| [core.md](core.md) | 단일 스레드 epoll, heartbeat, 스캔 상태머신과 종료 정책 | 이현우 |
| [modules.md](modules.md) | 정적 모듈 계약 v5, 공유 상태 소유권과 콜백 순서 | 이현우 |
