# Yocto 이미지 빌드와 배포

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-YOC-73` |
| 담당 | 이현우 (문서). 빌드·플래시 실행은 사용자가 직접 한다 |
| 대상 소스 | `yocto/ybuild.sh` |
| 기준 코드 | Yocto `947f5b5` (2026-08-26) |

빌드 호스트 구성과 설계 근거는 [../components/yocto/image.md](../components/yocto/image.md)
에 있다.

---

## 1. 빌드

```bash
./ybuild.sh bitbake 'adts-image'
```

첫 빌드는 M4 Pro 8코어 기준 약 50분, 이후 증분 빌드는 수 분이다.

`core-image-minimal` 만 빌드하면 ADTS 패키지가 들어가지 않는다. `yocto/README.md` 의
quick start 가 아직 그쪽을 가리킨다.

---

## 2. 굽기 전 확인

레시피가 빌드된 것과 이미지에 들어간 것은 다르다. 세 단계를 구분한다.

```bash
# 1. 레시피가 parse 되는가
bitbake-layers show-recipes | grep -E "adts-(drivers|overlays|daemon|broker|image)"

# 2. 패키지가 build 되는가
bitbake -p                       # 전체 parse
bitbake adts-daemon              # 개별 빌드

# 3. 이미지 manifest 에 들어갔는가   <- 최종 증거
grep adts /work/build/tmp/deploy/images/raspberrypi4-64/*.manifest
```

DTBO 는 deploy 디렉터리와 최종 부트 파티션 포함 여부를 함께 확인한다.

### 2.1 데몬 기능 축소 확인 (필수)

```bash
grep -iE "mTLS 활성|비활성으로" \
  /work/build/tmp/work/*/adts-daemon/*/temp/log.do_configure
```

이 확인을 빠뜨리면 mTLS 도 MQTT 도 없는 데몬이 조용히 실린다. `local.conf` 에
`RM_WORK_EXCLUDE += "adts-daemon"` 이 있어야 이 로그가 남는다.

---

## 3. 산출물 반출

```bash
./ybuild.sh run '
  D=/work/build/tmp/deploy/images/raspberrypi4-64
  cp -L $D/adts-image-raspberrypi4-64.rootfs.wic.bz2 /mnt/mac/images/adts.wic.bz2'
```

`-L` 은 심볼릭 링크를 따라간다. Yocto 산출물은 대개 타임스탬프 붙은 실파일에 대한
링크다.

---

## 4. SD 카드 기록

```bash
diskutil list
diskutil unmountDisk /dev/diskN
bunzip2 -c images/adts.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
```

`diskN` 을 잘못 고르면 다른 디스크를 덮어쓴다. 반드시 `diskutil list` 로 장치를 식별한
뒤 실행할 것. `/dev/rdiskN`(raw)이 `/dev/diskN` 보다 훨씬 빠르다.

---

## 5. 부팅 후 체크리스트

```sh
uname -r                          # 6.12.75 로 시작
cat /proc/1/comm                  # systemd
ls /dev/ttyAMA0                   # UART0 (PL011)
ls /sys/bus/i2c/devices/          # 1-0069 노드
grep -rl adts /proc/device-tree/  # 오버레이 3종 노드
lsmod | grep -E "turret|imu|led_sw"
ls /dev/turret /dev/imu /dev/led_sw

systemctl status adts-daemon adts-enroll mosquitto
```

| 항목 | 기대값 |
|---|---|
| `uname -r` | `6.12.75` 로 시작 |
| PID 1 | `systemd` |
| UART0 | `/dev/ttyAMA0` 존재 |
| I2C1 | 활성 + `1-0069` 노드 |
| DT | 오버레이 3종 노드가 `/proc/device-tree` 에 존재 |
| `/dev` | `turret`, `imu`, `led_sw` (probe 성공분) |

### 5.1 인증서 부트스트랩 (첫 부팅 1회)

```sh
sudo /opt/adts/gen-certs.sh <RPi_IP> /etc/adts/certs
```

그 전까지 mosquitto 와 adts-daemon 은 인증서가 없어 실패한다. 의도된 동작이다.
조용히 degraded 로 도는 것보다 시끄럽게 실패하는 편이 낫다.

출력 디렉터리를 반드시 적는다. `gen-certs.sh` 는 모드마다 기본값이 다르다.

| 모드 | 출력 기본값 |
|---|---|
| 전체 발급 `<IP> [디렉터리]` | `./certs` — 현재 디렉터리 기준 |
| `--client <CN>` | `/etc/adts/certs` |
| `--server <CN>` | `/etc/adts/certs` |

전체 발급만 상대 경로다. 홈에서 인자 없이 실행하면 `~/certs` 에 만들어지고, mosquitto
는 계속 `Unable to load CA certificates` 로 실패한다. 그 디렉터리에는 `ca.key` 가 들어
있으므로 잘못 만들었으면 지운다.

발급 뒤 데몬 계정이 개인키를 읽을 수 있는지 확인한다.

```sh
ls -l /etc/adts/certs/daemon.key
sudo chgrp pi /etc/adts/certs/daemon.key && sudo chmod 640 /etc/adts/certs/daemon.key
```

`gen-certs.sh` 는 모든 키를 `600 root` 로 만들고, mosquitto 용 `server.key` 만 따로
읽기 권한을 조정한다. 데몬용 `daemon.key` 에는 같은 처리가 없어서 `User=pi` 로 도는
데몬이 읽지 못한다. 증상이 권한 문제로 보이지 않는 것이 함정이다.

```
[MQTT]   TLS 설정 실패 (Invalid arguments provided.)
[camera] TLS 준비 실패: 키 읽기 실패(권한 확인): /etc/adts/certs/daemon.key
```

`mosquitto_tls_set()` 이 `MOSQ_ERR_INVAL` 을 돌려주므로 설정 오류처럼 읽힌다. camera
모듈이 같은 키에 대해 권한이라고 말해주는 쪽이 정확하다. Raspberry Pi OS 배포에서는
`install-service.sh` 가 이 상태를 검사해 알려주지만 Yocto 경로에는 그 검사가 없다.

---

## 6. 실패 로그 읽기

화면의 BitBake 오류는 요약일 수 있으므로 태스크 로그 원문을 본다.

```bash
ls /work/build/tmp/work/*/<recipe>/*/temp/log.do_*
```

성공한 레시피는 `rm_work` 로 작업 디렉터리가 지워진다. 분석이 필요한 레시피는 빌드
전에 `RM_WORK_EXCLUDE` 에 넣어야 한다.

---

## 7. BusyBox 차이

`core-image-minimal` 계열의 기본 도구는 BusyBox 이므로 GNU 축약 옵션이 없을 수 있다.

```sh
head -5 file      # 실패할 수 있다
head -n 5 file    # 이렇게 쓴다
```

---

## 8. 릴리스 수용 기준

- clean 이미지 부팅 후 `/dev/turret` 이 올바른 group/mode 로 생성
- 서비스가 non-root 로 시작하고 HOME/scan 을 수행
- protocol 해시와 build manifest 가 양쪽과 일치
- 네트워크가 없어도 스캔 안전성과 로컬 산출물이 동작
- 네트워크 복구 후 pending result/upload 정책이 수행
- 이전 이미지로 rollback 해도 artifact schema 와 firmware 호환성이 설명됨

---

## 9. 플래시 경계

STM32 펌웨어 플래시는 사용자만 수행한다. RPi 배포가 firmware flash 를 암묵적으로
실행해서는 안 된다. 배포 도구는 필요한 firmware version 을 표시하고, 사용자가
flash·verify 한 뒤 호환성 확인을 통과해야 데몬 스캔을 허용하는 방향이 맞다.

플래시 뒤 반드시 기록할 것:

- firmware git commit
- protocol 해시 또는 reported version
- build timestamp / toolchain
- OpenOCD program/verify 로그
- cold boot 후 STATUS payload
- HOME 과 표준 스캔 결과

---

## 10. 검증 현황

| 항목 | 등급 | 결과 |
|---|---|---|
| `core-image-minimal` 빌드 | B | 성공 (약 50분) |
| 단계별 이미지 산출 | B | 2026-08-20 phase1b·phase2·phase3 생성 |
| `adts-image` 빌드 | B | 2026-08-27 성공 |
| manifest 확인 | B | 우리 패키지 8종 + mosquitto·bash·openssl-bin 확인 |
| SD 기록 + 부팅 | A | 2026-08-27 부팅 |
| 부팅 체크리스트 | A | 커널·systemd·UART·I2C·WiFi·오버레이 3종·`/dev/turret` 확인 |
| 브로커·발급 서비스 기동 | A | `gen-certs.sh` 후 8883·8443 LISTEN |
| 데몬 MQTT 접속 | D | `daemon.key` 권한 때문에 실패. 아래 참조 |

---

## 11. 참고

- 빌드 호스트: [../components/yocto/image.md](../components/yocto/image.md)
- 레시피: [../components/yocto/layers-and-recipes.md](../components/yocto/layers-and-recipes.md)
- 커널·DT: [../components/yocto/kernel-drivers-dt.md](../components/yocto/kernel-drivers-dt.md)
