# 송영빈 — 담당 범위와 작성 문서

## 담당 범위

| 파트 | 맡은 것 | 저장소 위치 |
|---|---|---|
| STM32 펌웨어 | TOFSense-F2 P 라이다 NLink 파서, 모터 가감속과 런타임 타이머 결선 | `STM32` — `App/lidar/`, `App/motor/`, `Core/Src/main.c` |
| RPi 드라이버 | ICM-20948 IMU 커널 드라이버 · DT 오버레이 | `RPi` — `driver/imu_driver.c`, `driver/overlays/` |
| RPi 브로커 | `/enroll` 인증서·설정 발급 서비스, 토큰 CLI, 스캔 조회 | `RPi` — `broker/` (이현우와 공동) |
| Qt 관제 콘솔 | 앱 전체 — RTSP 4채널, MQTT 브리지, 포인트클라우드 뷰, 등록 마법사 | `QT` |
| 인터페이스 계약 | Qt↔RPi 등록·발급 계약 (HTTPS 8443) | `docs` — `interfaces/qt-rpi-enroll.md` |

## 작성 문서

| 문서 | 다루는 것 |
|---|---|
| [라이다 수신 드라이버](../../components/stm32/lidar.md) | NLink 프레임 파싱, ISR 각도 래치, SPSC 링버퍼, UART 에러 복구, 상행 계약 `proto_scan_point` |
| [2축 스텝모터 구동 및 가감속](../../components/stm32/motor.md) | 1차 사다리꼴 가감속 램프 도입 및 타이머 시간축 설계 (강유근과 공동) |
| [STM32 펌웨어 런타임](../../components/stm32/runtime.md) | 가감속 타이머 초기화 순서와 실행 제약 (이현우·강유근과 공동) |
| [IMU 드라이버](../../components/rpi/driver/imu.md) | ICM-20948 레지스터 뱅크, MPU-6050 교체 이력, `/dev/imu` 계약, 브링업·진단 |
| [발급 서비스](../../components/rpi/broker-enroll.md) | 1회용 토큰 수명주기, 인증서 서명 위임, ACL 자동 등록, 스캔 조회 3중 방어 |
| [Qt 콘솔 개요](../../components/qt/overview.md) | 앱 구조, RTSP 4채널, MQTT 계약 구현, 화면·조작, 포인트클라우드, 트러블슈팅 |
| [Qt 빌드·배포](../../guides/qt-build-and-deploy.md) | 의존성, 등록 마법사, 설정 파일 탐색 순서, macOS·Windows 패키징 |
| [등록·발급 계약](../../interfaces/qt-rpi-enroll.md) | `POST /enroll`, 스캔 조회, TLS 요구사항, 인증서 형식, ACL 등록 의무 |
| [발급 토큰 운영](../../guides/broker-token-runbook.md) | 토큰 생성·회수, ACL 확인, 접속 끊기, 증상별 진단 |
