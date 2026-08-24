# docs

A.D.T.S — 1D LiDAR Pan-Tilt 스캐너 기반 Edge AI CCTV 마커리스 자동 캘리브레이션 킷의
팀 문서 저장소입니다.

## 어디에 무엇을 두나

| 폴더 | 넣을 것 |
|---|---|
| [overview/](overview/) | 시스템 아키텍처, 요구사항 — 파트를 가리지 않는 문서 |
| [interfaces/](interfaces/) | 여러 파트가 함께 지키는 계약 (MQTT 토픽, 산출물 포맷, UART 프로토콜, mTLS) |
| [components/stm32/](components/stm32/) | STM32 펌웨어 |
| [components/rpi/](components/rpi/) | 커널 드라이버 · 통합 데몬 · 브로커 |
| [components/qt/](components/qt/) | Qt 관제 콘솔 |
| [components/calibration/](components/calibration/) | 자동 캘리브레이션 (알고리즘·논문 조사) |
| [components/yocto/](components/yocto/) | Yocto 이미지 빌드 — 레시피, 레이어 구성 |
| [components/opensdk/](components/opensdk/) | Edge AI 카메라 Open Platform SDK |
| [guides/](guides/) | 환경 설정, 빌드, 배포 절차 |
| [users/](users/) | 팀원별 담당 범위와 작성 문서 목록 |

## 작성 규칙

**한 문서는 그것만 읽고도 이해돼야 합니다.** 필요한 배경은 문서 안에 쓰고, 다른 문서나
외부 위키로 넘기지 마세요 — 읽는 사람이 그 링크를 못 열 수 있습니다.

- 문서끼리 링크로 엮지 않는다. 목차는 이 README 하나면 충분하다
- 파일명은 **소문자 + 하이픈**, 영문 (`stm32-rpi-uart.md`). 제목은 한글
- 값(CMD 번호, 구조체 크기, 핀 번호)을 적을 때는 **기준 커밋과 날짜**를 함께 남긴다
- 표·코드블록·mermaid 다이어그램을 적극적으로 쓴다. 줄글보다 읽기 쉽다
- 폴더를 새로 만들면 `README.md`도 같이 만든다 (git은 빈 폴더를 추적하지 않는다)

## 현재 있는 문서

### STM32 펌웨어

| 문서 | 내용 | 담당 |
|---|---|---|
| [sensors/driver-lidar.md](components/stm32/sensors/driver-lidar.md) | TOFSense-F2 P 수신 드라이버 — NLink 프레임 파싱, ISR 각도 래치, SPSC 링버퍼 | 송영빈 |
| [motor-ramp.md](components/stm32/motor-ramp.md) | 사다리꼴 속도 프로파일 — 램프 산수, 타이머 시간축, ISR 삽입점 | 송영빈 |
| [uart-rpi.md](components/stm32/uart-rpi.md) | RPi 링크 프로토콜 어댑터 — 링버퍼, 프레임 파서, 1Hz STATUS, 진단 카운터 | 이현우 |
| [scan.md](components/stm32/scan.md) | 2축 스캔 시퀀서 — 홈 확립, serpentine 스윕, 탈조 감시, 라이다 연계 | 이현우 / 강유근 |

### Raspberry Pi

| 문서 | 내용 | 담당 |
|---|---|---|
| [driver/imu.md](components/rpi/driver/imu.md) | ICM-20948 수평 기준 — DT 오버레이, 커널 드라이버, `/dev/imu` 계약 | 송영빈 |
| [broker-enroll.md](components/rpi/broker-enroll.md) | `/enroll` 발급 서비스 — 1회용 토큰, 인증서 서명, ACL 자동 등록, 스캔 조회 | 송영빈 |
| [driver/turret.md](components/rpi/driver/turret.md) | `/dev/turret` 커널 드라이버 — serdev, kfifo 스캔 스트림, ioctl ABI | 이현우 |
| [daemon/core.md](components/rpi/daemon/core.md) | 통합 데몬 코어 — epoll FSM, heartbeat, 스캔 생명주기, 수평 게이트 | 이현우 |

### 인터페이스 계약

| 문서 | 내용 | 담당 |
|---|---|---|
| [stm32-rpi-uart.md](interfaces/stm32-rpi-uart.md) | Protocol v6 — 프레임, 명령·오류 코드, payload 구조체, 각도 규약 | 이현우 |

### Qt 관제 콘솔

| 문서 | 내용 | 담당 |
|---|---|---|
| [overview.md](components/qt/overview.md) | 앱 구조, RTSP 4채널, MQTT, 화면·조작, 포인트클라우드, 트러블슈팅 | 송영빈 |
| [build-and-deploy.md](components/qt/build-and-deploy.md) | 의존성 설치, 빌드, 배포 패키징 | 송영빈 |
