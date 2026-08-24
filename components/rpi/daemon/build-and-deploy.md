# RPi 데몬 빌드와 systemd 배포

RPi 통합 데몬을 빌드하고 커널 모듈·Device Tree overlay·systemd unit과 함께 배포하는
절차를 정리한다.

| 항목 | 값 |
|---|---|
| 문서 ID | `ADTS-DMN-33` |
| 기준 코드 | RPi `2f9b2c2` (2026-08-24) |
| 데몬 빌드 | `RPi/daemon/CMakeLists.txt` |
| 서비스 | `RPi/daemon/adts-daemon.service` |
| 설치 도구 | `RPi/daemon/tools/install-service.sh` |
| 배치 도구 | `RPi/daemon/tools/scan_batch.sh` |
| 드라이버 빌드 | `RPi/driver/Makefile` |

## 배포 경계

배포 경로는 런타임 코드, userspace 빌드, kernel build, boot 자산, 서비스 정책을 연결한다.

```mermaid
flowchart LR
  SRC[daemon source] --> CM[CMake]
  CM --> BIN[adts_daemon]
  KS[kernel source and config] --> KM[driver Makefile]
  KM --> KO[kernel modules]
  KM --> DTBO[Device Tree overlays]
  BIN --> INST[install-service.sh]
  KO --> INST
  DTBO --> INST
  INST --> OPT[/opt/adts/adts_daemon]
  INST --> MOD[/lib/modules/current/extra]
  INST --> BOOT[boot overlays and config.txt]
  INST --> UNIT[adts-daemon.service]
  UNIT --> DEV[/dev/turret]
  UNIT --> OUT[/var/lib/adts/scans]
```

이 문서는 다음 책임을 다룬다.

- `adts_daemon`의 compile·link 정책과 조건부 기능
- Raspberry Pi 대상 kernel module·test application·DTBO 빌드
- 실행 중 모듈과 부팅 overlay를 함께 갱신하는 설치 절차
- systemd의 장치 준비, 출력 디렉터리, 재시작, 권한 축소 정책
- 반복 스캔의 timeout·종료 코드·로그 수집 규칙
- RPi 저장소의 CI gate

Yocto recipe, STM32 firmware flash, broker 인증서 발급, Qt package 배포는 별도 수명주기를
가지므로 이 절차에서 생성하지 않는다.

## 데몬 CMake 빌드

### 컴파일 정책

| 구분 | 설정 |
|---|---|
| 언어 | C11 required |
| 경고 gate | `-Wall -Wextra -Werror` |
| 최적화 | `-O2` |
| compile hardening | `-fstack-protector-all`, `_FORTIFY_SOURCE=2`, `-fPIE` |
| link hardening | PIE, RELRO, NOW |
| 분석 입력 | `compile_commands.json` 항상 생성 |
| 기본 library | `libm` |

실행 파일은 다음 translation unit을 묶는다.

```text
daemon/core/main.c
daemon/core/scan_output.c
daemon/modules/mqtt/mqtt_module.c
daemon/modules/imu/imu_module.c
daemon/modules/led/led_module.c
daemon/modules/camera/camera_module.c
```

RPi 또는 Linux ARM64 build container에서 저장소 root를 기준으로 빌드한다.

```bash
cmake -S daemon -B daemon/build \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build daemon/build -j4
```

데몬은 `epoll`, `timerfd`, `signalfd`를 사용하므로 macOS에서 직접 빌드하지 않는다.
비Linux 개발 장비에서는 `RPi/docker/`의 `adts-build` image에 저장소를 `/work`로
mount한 뒤 같은 명령을 실행한다.

### 조건부 기능

| 탐색 결과 | build 결과 |
|---|---|
| OpenSSL 발견 | camera mTLS 송신 활성, `OpenSSL::SSL`·`OpenSSL::Crypto` link |
| OpenSSL 없음 | `ADTS_NO_TLS=1`, camera upload 비활성, 평문 전환 없음 |
| libmosquitto와 libcjson 발견 | MQTT module 활성 |
| 둘 중 하나라도 없음 | `ADTS_NO_MQTT=1`, MQTT module no-op |

CMake configure 성공만으로 모든 제품 기능이 포함되었다고 판정하지 않는다. 배포용
binary는 configure log에서 `카메라 업로드: mTLS 활성`과 `MQTT: 활성`을 모두 확인한다.
의도적으로 기능 축소 build를 검사할 때만 다음 경로를 사용한다.

```bash
cmake -S daemon -B daemon/build-notls \
  -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON
cmake --build daemon/build-notls
```

## 드라이버와 overlay 빌드

`driver/Makefile`은 kernel space 산출물과 user space 검사 도구를 함께 관리한다.

| target | 산출물 |
|---|---|
| `modules` | `turret_driver.ko`, `imu_driver.ko`, `led_sw_driver.ko` |
| `dtbo` | `driver/overlays/*-overlay.dtbo` |
| `apps` | `turret_test`, `imu_test`, `led_sw_test`, `encoder_jitter_test` |
| `all` | `dtbo`, `modules`, `apps` 전체 |
| `rpi` | ARM64 cross variables를 적용한 `all` |

RPi 실기에서 실행 중인 kernel의 build tree를 사용할 때는 다음과 같이 빌드한다.

```bash
make -C driver
```

개발 container에서 Raspberry Pi kernel source를 사용할 때는 `RPI_KDIR`, architecture,
cross compiler가 대상과 일치해야 한다.

```bash
make -C driver rpi \
  RPI_KDIR=/usr/src/linux \
  RPI_ARCH=arm64 \
  RPI_CROSS=aarch64-linux-gnu-
```

Apple Silicon ARM64 container처럼 compiler target이 이미 ARM64이면 `RPI_CROSS=`로 둘 수
있다. `.ko`의 vermagic은 배포 대상 `uname -r`과 일치해야 한다.

```bash
modinfo -F vermagic driver/turret_driver.ko
uname -r
```

## systemd 서비스

### 시작 조건과 실행 계정

| unit 항목 | 값 | 의미 |
|---|---|---|
| `After` | `network-online.target mosquitto.service` | network·broker 뒤에 시작 순서 지정 |
| `Wants` | `network-online.target` | network online target 활성화 요청 |
| `User` / `Group` | `pi` / `pi` | 비특권 계정으로 실행 |
| `ExecStart` | `/opt/adts/adts_daemon` | 설치된 binary 실행 |
| `ExecStartPre` | `/dev/turret` 최대 30초 대기 | 장치가 없으면 service 시작 실패 |

데몬 자체는 `/dev/turret` 없이 degraded mode로 기동할 수 있다. 서비스 unit은 제품 부팅
경로에서 이를 허용하지 않고 device node가 나타날 때까지 1초 간격으로 확인한다.

### 산출물 디렉터리

```ini
StateDirectory=adts/scans
StateDirectoryMode=0750
WorkingDirectory=/var/lib/adts
ReadWritePaths=/var/lib/adts
```

systemd가 `/var/lib/adts/scans`를 service account 소유로 생성한다. 데몬의 기본 JSON·PCD
출력 경로와 unit의 쓰기 허용 범위가 이 디렉터리에서 일치한다.

### 런타임 환경

| 환경 변수 | unit 값 | 역할 |
|---|---|---|
| `ADTS_MQTT_HOST` | `127.0.0.1` | broker address |
| `ADTS_MQTT_PORT` | `8883` | MQTT over mTLS port |
| `ADTS_MQTT_CA` | `/etc/adts/certs/ca.crt` | broker trust anchor |
| `ADTS_MQTT_CERT` | `/etc/adts/certs/daemon.crt` | daemon client certificate |
| `ADTS_MQTT_KEY` | `/etc/adts/certs/daemon.key` | daemon private key |
| `ADTS_CAM_CONF` | `/etc/adts/camera.conf` | camera upload 설정 파일 |
| `ADTS_CAM_TIMEOUT_S` | `60` | 설정 파일에 값이 없을 때의 timeout |

카메라 설정 파일은 upload 시도마다 다시 읽는다. IP나 인증서 경로 변경은 unit 수정과
`daemon-reload` 없이 다음 시도에 반영된다.

### 재시작과 권한 축소

| unit 항목 | 값 |
|---|---|
| `Restart` / `RestartSec` | `on-failure` / 5초 |
| `KillSignal` | `SIGTERM` |
| `TimeoutStopSec` | 60초 |
| `ProtectSystem` | `strict` |
| `ProtectHome` | `true` |
| `PrivateTmp` | `true` |
| `NoNewPrivileges` | `true` |

데몬은 `SIGTERM`을 `signalfd`로 받아 진행 중인 scan output을 마감하고 STM32에 DISARM을
전달한다. `PrivateDevices`는 적용하지 않는다. 이를 활성화하면 `/dev/turret`, `/dev/imu`,
`/dev/led_sw`까지 격리되기 때문이다.

## 설치 스크립트

### 입력과 option

`install-service.sh`는 root 권한으로 RPi에서 실행한다. 시작 전에 daemon binary와 필요한
`.ko`·`.dtbo`를 빌드한다.

```bash
sudo bash daemon/tools/install-service.sh [--daemon-only] [--no-start]
```

| option | 동작 |
|---|---|
| 기본 | daemon, 발견한 module, overlay, unit을 설치하고 service 시작 |
| `--daemon-only` | kernel module과 overlay 설치 생략 |
| `--no-start` | 설치와 `daemon-reload`까지만 수행 |

### 설치 순서

```text
1. 실행 중인 adts-daemon service 정지
2. adts_daemon을 /opt/adts/adts_daemon에 mode 0755로 설치
3. 발견한 .ko를 /lib/modules/<uname -r>/extra에 설치
4. depmod와 /etc/modules-load.d/adts.conf 갱신
5. 실행 중인 기존 module을 내리고 새 module을 modprobe
6. DTBO를 boot overlay 디렉터리에 설치하고 config.txt에 dtoverlay 등록
7. adts-daemon.service 설치와 systemctl daemon-reload
8. camera.conf가 없을 때만 example로 생성
9. 인증서 가독성과 device node 확인
10. enable --now 또는 --no-start 종료
```

boot 경로는 Raspberry Pi OS layout에 따라 다음 순서로 선택한다.

| config | overlay directory |
|---|---|
| `/boot/firmware/config.txt` | `/boot/firmware/overlays` |
| `/boot/config.txt` | `/boot/overlays` |

`modules-load.d`는 다음 부팅에 적용되므로 installer는 현재 kernel에도 `rmmod`와
`modprobe`를 실행한다. 사용 중인 module을 내리지 못했거나 새 module 적재가 실패하면
재부팅 필요 상태를 출력한다. 새 `dtoverlay=` 항목도 재부팅 후 적용된다.

`/etc/adts/camera.conf`는 현장 설정을 보존하기 위해 기존 파일을 덮어쓰지 않는다.

### 인증서 권한

service account가 세 파일을 읽을 수 있어야 한다.

```bash
sudo -u pi test -r /etc/adts/certs/ca.crt
sudo -u pi test -r /etc/adts/certs/daemon.crt
sudo -u pi test -r /etc/adts/certs/daemon.key
```

private key를 world-readable로 두지 않는다. `User=pi`, `Group=pi` 정책에서는 다음과 같이
group read만 부여할 수 있다.

```bash
sudo chgrp pi /etc/adts/certs/daemon.key
sudo chmod 640 /etc/adts/certs/daemon.key
```

## 반복 스캔

`scan_batch.sh`는 각 회차를 독립적인 `--once` process로 실행하고 log와 summary를
분리한다. 상주 service와 `/dev/turret`을 동시에 열지 않도록 먼저 service를 정지한다.

```bash
sudo systemctl stop adts-daemon
bash daemon/tools/scan_batch.sh -n 5
```

| 항목 | 기본값 |
|---|---|
| 반복 횟수 | 5 |
| 회차 간격 | 15초 |
| 회차 timeout | 2400초 |
| scan request | `--scan 0 1791 -900 900 9 --height 1805` |
| 실패 정책 | 첫 실패에서 중단 |
| 출력 디렉터리 | `./batch-YYYYMMDD-HHMMSS` |

| option | 역할 |
|---|---|
| `-n N` | 반복 횟수 |
| `-i SEC` | 회차 간 대기 |
| `-t SEC` | 회차 timeout |
| `-d PATH` | daemon binary 직접 지정 |
| `-o DIR` | log directory 지정 |
| `-k` | 실패 후에도 다음 회차 진행 |
| `-- ...` | 기본 scan argument 전체 교체 |

script는 `daemon/build/adts_daemon`, `daemon/adts_daemon`, 현재 디렉터리,
`/opt/adts/adts_daemon` 순서로 실행 파일을 찾고 `--once`가 없으면 자동으로 추가한다.

### 종료 판정

pipeline의 `tee`가 아니라 `${PIPESTATUS[0]}`으로 daemon 종료 코드를 읽는다.

| 결과 | 판정 |
|---|---|
| 0 | scan output 기록 완료 |
| 1 등 일반 오류 | home·수평 gate·산출물 기록 등의 실패 |
| 124 또는 137 | timeout 또는 timeout 뒤 강제 종료 |
| Ctrl-C | 종료 코드보다 `ABORT` flag를 우선해 중단 처리 |

현재 코어는 `--once`에서 JSON 또는 PCD 기록이 실패하면 `scan_failed`를 설정한다. 따라서
`scan_batch.sh`의 성공 집계와 `result.valid`가 같은 산출 완료 조건을 사용한다.

GNU `timeout`이 있으면 먼저 SIGINT를 보내고 20초 뒤에도 종료하지 않은 process를
강제 종료한다. `STOP` 파일은 진행 중인 회차를 마친 뒤 다음 회차 전에 중단한다.

## CI gate

`.github/workflows/static_analysis.yml`은 `main` push와 `main` 대상 pull request에서 세
job을 실행한다. Markdown·`docs/`만 바뀐 main push는 건너뛰지만 pull request에는 path
제외를 적용하지 않는다.

| job | 검사 |
|---|---|
| `driver-analysis` | driver·shared cppcheck, `turret_test` GCC warning gate |
| `daemon-analysis` | OpenSSL 포함 CMake build, cppcheck, `ADTS_NO_TLS` build |
| `broker-analysis` | broker CMake build와 cppcheck |

kernel module compile은 CI runner의 대상 kernel header·configuration과 결합하지 않는다.
`.ko` 변경은 대상 RPi 또는 준비된 kernel tree에서 별도로 빌드하고 vermagic을 확인한다.

## 운영 확인

설치 후 다음 순서로 service와 자산을 확인한다.

```bash
ls -l /dev/turret /dev/imu /dev/led_sw
systemctl status adts-daemon
journalctl -u adts-daemon -f
ls -ld /var/lib/adts/scans
lsmod | grep -E 'turret_driver|imu_driver|led_sw_driver'
```

camera host를 바꿀 때는 `/etc/adts/camera.conf`를 수정한다. unit의 환경 변수나 service
binary를 바꾼 경우에만 각각 `daemon-reload` 또는 재설치를 수행한다.

## 검증 기준선

2026-08-24 ARM64 Linux build container에서 RPi `2f9b2c2`를 검증했다.

| 항목 | 결과 |
|---|---|
| GNU 13.3, C11, OpenSSL·MQTT 활성 build | 통과 |
| `ADTS_NO_TLS` build | 통과 |
| cppcheck 2.13, daemon 6개 translation unit | 통과 |
| `install-service.sh`, `scan_batch.sh` `bash -n` | 통과 |
| unit 환경·경로와 module 설정의 source 대조 | 일치 |
| `--once` 산출 실패와 batch 종료 코드 연결 | `scan_failed` 경로 확인 |

실기 배포에서는 여기에 device node, module vermagic, boot overlay, service account 인증서
가독성, JSON·PCD 생성까지 확인해야 배포 완료로 판정한다.
