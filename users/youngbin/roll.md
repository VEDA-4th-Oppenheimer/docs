# 송영빈 — 담당 범위와 작성 문서

A.D.T.S 프로젝트에서 맡은 부분과, 그에 대해 쓴 문서 목록입니다.

## 담당 범위

| 파트 | 맡은 것 | 저장소 위치 |
|---|---|---|
| STM32 펌웨어 | TOFSense-F2 P 라이다 NLink 파서 | `STM32` — `App/lidar/` |
| RPi 드라이버 | ICM-20948 IMU 커널 드라이버 · DT 오버레이 | `RPi` — `driver/imu_driver.c`, `driver/overlays/` |
| RPi 브로커 | `/enroll` 인증서·설정 발급 서비스, 토큰 CLI, 스캔 조회 | `RPi` — `broker/` (이현우와 공동) |
| Qt 관제 콘솔 | 앱 전체 | `QT` |

## 작성 문서

| 문서 | 다루는 것 |
|---|---|
| [라이다 수신 드라이버](../../components/stm32/sensors/driver-lidar.md) | NLink 프레임 파싱, ISR 각도 래치, SPSC 링버퍼, UART 에러 복구, 상행 계약 `proto_scan_point` |
| [IMU 드라이버](../../components/rpi/driver-imu.md) | ICM-20948 레지스터 뱅크, MPU-6050 교체 이력, `/dev/imu` 계약, 브링업·진단 |
| [발급 서비스](../../components/rpi/broker-enroll.md) | 1회용 토큰 수명주기, 인증서 서명 위임, ACL 자동 등록, 스캔 조회 3중 방어 |
| [Qt 콘솔 개요](../../components/qt/overview.md) | 앱 구조, RTSP 4채널, MQTT 계약 구현, 화면·조작, 포인트클라우드, 트러블슈팅 |
| [Qt 빌드·배포](../../components/qt/build-and-deploy.md) | 의존성, 등록 마법사, 설정 파일 탐색 순서, macOS·Windows 패키징 |

## 참고

- 각 문서는 그것만 읽고도 이해되도록 썼습니다. 문서끼리 링크로 엮지 않았고, 이 페이지와
  저장소 최상위 `README.md` 가 유일한 목차입니다.
