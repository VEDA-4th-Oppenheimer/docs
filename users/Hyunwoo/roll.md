# 이현우 — 담당 범위와 작성 문서

## 담당 범위

| 파트 | 맡은 것 | 저장소 위치 |
|---|---|---|
| 시스템·인터페이스 | Device 계층 아키텍처, Protocol v6, 스캔 산출물·MQTT·카메라 업로드 계약 | `docs` — `overview/`, `interfaces/` |
| STM32 펌웨어 | RPi UART 프로토콜 어댑터, 2축 스캔 시퀀서 계층 분리·프로토콜 연계 | `STM32` — `App/uart_rpi/`, `App/scan/` (스캔 원 구현은 강유근) |
| RPi 커널 드라이버 | STM32 serdev 연결, `/dev/turret` 스트림·ioctl ABI | `RPi` — `driver/turret_driver.c`, `shared/protocol.h` |
| RPi 통합 데몬 | epoll FSM, heartbeat, `scan_output`, module ABI, MQTT module, 카메라 송신 client | `RPi` — `daemon/`, `shared/daemon_module.h` |
| RPi 브로커 | Mosquitto 운영 설정과 CA·인증서 발급 script | `RPi` — `broker/` (송영빈과 공동) |
| 카메라 연동 | organized JSON mTLS 송신과 wire contract의 RPi 측 | `RPi` — `daemon/modules/camera/` (카메라 app TCP server는 이영민) |
| 빌드·배포 | 데몬 CMake, systemd unit, 커널 module·overlay 설치, 반복 스캔 운영 | `RPi` — `daemon/CMakeLists.txt`, `daemon/tools/`, `driver/Makefile` |
| Yocto | 이미지·레이어·레시피·커널 module·DT 연결 설계와 문서화 | `yocto` — `meta-adts/`, `conf/` (빌드·flash 실행은 사용자 수행) |

## 작성 문서

| 문서 | 다루는 것 |
|---|---|
| [시스템 아키텍처](../../overview/architecture.md) | Device 노드 구성, 계층 책임, UART·MQTT·JSON·PCD 전달 경계 |
| [Protocol v6 통신 계약](../../interfaces/stm32-rpi-uart.md) | frame, command·error code, payload 구조체, 각도·시간 규약 |
| [스캔 산출물 계약](../../interfaces/scan-artifacts.md) | `lidar_scan` 좌표계, organized 격자, JSON schema 1.2와 PCD v0.7 |
| [MQTT 토픽 계약](../../interfaces/mqtt-topics.md) | command·state·event topic, payload, `req_id`, QoS·retained 정책 |
| [카메라 업로드 계약](../../interfaces/camera-upload.md) | mTLS 신원, 파일 framing, 응답·재시도 계약 (이영민과 공동) |
| [STM32 UART 어댑터](../../components/stm32/uart-rpi.md) | ISR ring buffer, frame parser, command dispatch, status·diagnostic 전송 |
| [STM32 스캔 시퀀서](../../components/stm32/scan.md) | HOME, serpentine scan, stall 감시, LiDAR 연계 (강유근과 공동) |
| [turret 커널 드라이버](../../components/rpi/driver/turret.md) | serdev parser, kfifo scan stream, poll·ioctl ABI, device lifetime |
| [브로커 발급 서비스](../../components/rpi/broker-enroll.md) | Mosquitto 운영·CA script와 `/enroll` 발급·스캔 조회 경계 (송영빈과 공동) |
| [데몬 코어](../../components/rpi/daemon/core.md) | 단일 epoll loop, FSM, heartbeat, scan lifetime과 shutdown 정책 |
| [데몬 module ABI](../../components/rpi/daemon/modules.md) | 정적 module contract, callback 순서와 shared state ownership |
| [스캔 산출물 생성기](../../components/rpi/daemon/scan-output.md) | 기구각 변환, 격자 indexing·병합, JSON·PCD writer 구현 |
| [카메라 송신 module](../../components/rpi/daemon/camera.md) | `ST_EXPORT` mTLS upload, 설정 재로드, timeout·retry와 heartbeat 경계 |
| [RPi 데몬 빌드·배포](../../guides/rpi-daemon-build-and-deploy.md) | CMake, kernel build, systemd, installer와 반복 scan 절차 |
| [Yocto 이미지](../../components/yocto/image.md) | build host, target image 구성과 재현성 기준 |
| [Yocto 레이어와 레시피](../../components/yocto/layers-and-recipes.md) | layer 구성, `local.conf`, recipe·package 포함 관계 |
| [Yocto 커널·DT 연결](../../components/yocto/kernel-drivers-dt.md) | out-of-tree module, DT overlay, `compatible`과 device node 생성 |
| [Yocto 빌드 가이드](../../guides/yocto-build.md) | image build, SD 기록과 boot 확인 절차 |
