# 레이어와 레시피

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-YOC-71` |
| 담당 | 이현우 |
| 대상 소스 | `yocto/meta-adts/`, `yocto/conf/bblayers.conf`, `yocto/conf/local.conf` |
| 기준 코드 | Yocto `947f5b5` (2026-08-26) · RPi `SRCREV f199cf4` (미커밋) |

---

## 1. 개요

세 가지를 섞으면 안 된다.

1. 레시피가 parse 되는 것
2. 패키지가 build 되는 것
3. 패키지가 최종 image manifest 에 들어가는 것

셋은 서로 다른 증거다. 2026-08-27 에 세 단계가 모두 확인됐다 — `bitbake adts-image` 가
성공하고(2), manifest 에 우리 패키지 8종이 들어갔으며(3), 그 이미지를 부팅해 서비스가
떴다.

---

## 2. 레이어 구성

`conf/bblayers.conf` 는 7개 레이어를 쓴다.

```
/work/poky/meta
/work/poky/meta-poky
/work/meta-raspberrypi
/work/meta-openembedded/meta-oe          <- cJSON
/work/meta-openembedded/meta-python      <- meta-networking 의존
/work/meta-openembedded/meta-networking  <- Mosquitto
/mnt/mac/meta-adts                       <- 우리 레이어
```

Mosquitto 는 meta-networking, cJSON 은 meta-oe 에서 오고, meta-networking 의 의존 때문에
meta-python 과 meta-oe 가 함께 필요하다.

### 2.1 `meta-adts/conf/layer.conf`

```
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"
BBFILE_COLLECTIONS += "adts"
BBFILE_PRIORITY_adts = "10"        # <- meta-raspberrypi(9)보다 높다
LAYERDEPENDS_adts = "core raspberrypi"
LAYERSERIES_COMPAT_adts = "scarthgap"
```

우선순위 10 이 핵심이다. `meta-raspberrypi` 가 9 이므로 커널 버전 핀을 bbappend 로
덮어쓰려면 반드시 더 높아야 한다. 9 이하로 두면 `linux-raspberrypi_6.12.bbappend` 가
적용되지 않고 이유도 보이지 않는다.

`LAYERDEPENDS_adts` 는 `core raspberrypi` 만 선언하지만 실제 레시피는 mosquitto·cJSON 을
요구한다. `bblayers.conf` 에는 필요한 레이어가 있어 지금 빌드는 되지만, `meta-adts` 만
다른 빌드로 옮기면 이 차이가 드러난다.

---

## 3. `local.conf` — 빌드 머신 설정

제품 정의는 `adts-image.bb` 로 옮기고 `local.conf` 에는 이 빌드 머신의 설정만 남긴다.
그래야 `meta-adts` 를 클론한 사람이 같은 이미지를 얻는다.

| 설정 | 목적 |
|---|---|
| `MACHINE = raspberrypi4-64` | 타깃 |
| `PREFERRED_VERSION_linux-raspberrypi = 6.12.%` | 커널 레시피 선택 |
| `INIT_MANAGER = systemd` | systemd |
| `ENABLE_UART = 1` + `disable-bt` | UART0 를 turret serdev 에 할당 |
| `ENABLE_I2C = 1` | ICM-20948 용 I2C1 |
| `RPI_EXTRA_CONFIG` | `config.txt` 에 dtoverlay 3종 지시 |
| `KERNEL_MODULE_AUTOLOAD += i2c-dev` | I2C 사용자 공간 인터페이스 |
| `rm_work` + `RM_WORK_EXCLUDE` | 디스크 절약 + 로그 보존 |
| `LICENSE_FLAGS_ACCEPTED` | BCM43455 펌웨어 |

전부 이미지 레시피로 옮길 수는 없다. `ENABLE_UART`·`ENABLE_I2C`·`RPI_EXTRA_CONFIG`(rpi-config
가 config.txt 생성)·`KERNEL_MODULE_AUTOLOAD`(커널 패키지 분할)·`PREFERRED_VERSION_*`(레시피
선택)은 머신 설정이나 커널 레시피에 작용하므로 이미지 레시피에 적으면 효과가 없다.
제대로 분리하려면 `meta-adts` 에 머신 설정 조각을 두고 `local.conf` 가 그것을 `require`
해야 하는데 아직 거기까지 가지 않았다.

### 3.1 BitBake `:append` 문법

```bitbake
IMAGE_INSTALL:append = " wpa-supplicant"   # 올바름 — 선행 공백 필수
IMAGE_INSTALL:append = "wpa-supplicant"    # 앞 항목과 붙어버린다
```

`:append` 는 공백을 자동 삽입하지 않는다.

---

## 4. 레시피

`meta-adts` 는 레시피 8종을 제공한다.

| 레시피 | 역할 | 추적 |
|---|---|---|
| `linux-raspberrypi_6.12.bbappend` | 커널 버전·커밋 핀 | 커밋됨 |
| `adts-drivers_git.bb` | `.ko` 3종 | 커밋됨 |
| `adts-overlays_git.bb` | `.dtbo` 3종 | 커밋됨 |
| `adts-daemon_git.bb` | 데몬 + systemd unit + pi 계정 | 커밋됨 |
| `adts-broker_git.bb` | 인증서 발급 서비스 + mosquitto 설정 | 커밋됨 |
| `adts-kit-config_1.0.bb` | sudoers + PATH | 커밋됨 |
| `mosquitto_%.bbappend` | `include_dir` 활성화 | 커밋됨 |
| `adts-image.bb` | 제품 조립 | 커밋됨 |

### 4.1 `adts-drivers_git.bb` — 커널 모듈

```bitbake
inherit module
SRC_URI = "git://github.com/VEDA-4th-Oppenheimer/RPi.git;protocol=https;branch=main"
SRCREV  = "f199cf467276c0521e9976f2c91cece9767179f5"

# 저장소 전체를 받고 그 안의 driver/ 에서 빌드한다.
# driver/ 만 받으면 안 된다 — Makefile 이 -I../shared 로 protocol.h 마스터를
# 참조하므로 상위 디렉터리가 같이 있어야 한다.
S = "${WORKDIR}/git/driver"

EXTRA_OEMAKE = "KDIR=${STAGING_KERNEL_DIR}"
MAKE_TARGETS = "modules"
```

두 줄이 이 레시피의 핵심이다.

| 줄 | 없으면 |
|---|---|
| `KDIR=${STAGING_KERNEL_DIR}` | `module.bbclass` 는 `KERNEL_SRC`/`KERNEL_PATH` 만 넘긴다. 우리 Makefile 은 `KDIR ?= /lib/modules/$(uname -r)/build` 라 빌드 컨테이너의 커널을 보려다 실패한다 |
| `MAKE_TARGETS = "modules"` | `module.bbclass` 에 기본값이 없어 Makefile 의 `all:` 이 돈다. 그건 `dtc` 로 dtbo 를 만들고 테스트 앱까지 크로스컴파일하려다 깨진다 |

```bitbake
# Makefile 에 modules_install 타겟이 없어서 module.bbclass 의 기본
# do_install(= oe_runmake modules_install)이 실패한다. 직접 설치한다.
do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra
    install -m 0644 ${S}/turret_driver.ko ${S}/imu_driver.ko ${S}/led_sw_driver.ko \
                    ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/
}

KERNEL_MODULE_AUTOLOAD += "turret_driver imu_driver led_sw_driver"
```

라이선스는 `CLOSED` 로 두었다. 저장소에 라이선스 파일이 없어 그래야 `LIC_FILES_CHKSUM`
이 면제된다. 소스는 `MODULE_LICENSE("GPL")` 을 선언하므로 실제로는 GPL 이고, 배포
라이선스를 정하면 `GPL-2.0-only` + `LIC_FILES_CHKSUM` 으로 바꿔야 한다.

### 4.2 `adts-overlays_git.bb` — 디바이스 트리

```bitbake
DEPENDS = "dtc-native"
SRCREV  = "f199cf467276c0521e9976f2c91cece9767179f5"   # 드라이버와 동일
S = "${WORKDIR}/git/driver/overlays"
inherit deploy

# -@ 가 핵심이다. __symbols__ 노드를 넣어 실행 중에 phandle 을 풀 수 있게 한다.
# 없으면 &uart0 / &i2c1 참조가 해석되지 않아 오버레이가 적용되지 않는다.
do_compile() {
    for f in ${S}/*-overlay.dts; do
        dtc -@ -I dts -O dtb -o ${B}/$(basename $f .dts).dtbo $f
    done
}

# DEPLOYDIR 에 놓아야 IMAGE_BOOT_FILES 가 부트 파티션으로 복사할 수 있다.
do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/*.dtbo ${DEPLOYDIR}/
}
addtask deploy after do_compile before do_build

# 타겟 rootfs 에 아무것도 설치하지 않는다(부트 파티션 전용).
ALLOW_EMPTY:${PN} = "1"
```

드라이버와 같은 `SRCREV` 를 쓰는 것이 계약이다. 오버레이의 `compatible` 과 드라이버의
`of_match_table` 은 한 쌍이라 어긋나면 빌드 오류 없이 바인딩이 되지 않는다.

### 4.3 `adts-daemon_git.bb`

```bitbake
# DEPENDS 를 빠뜨리면 조용히 반쪽짜리가 구워진다 — 이 레시피 최대 함정.
#   daemon/CMakeLists.txt 는 OpenSSL / libmosquitto / cjson 을 REQUIRED 없이
#   찾는다. 못 찾으면 경고만 내고 그 기능을 끈 채 빌드가 성공한다.
#   즉 mTLS 도 MQTT 도 없는 데몬이 아무 에러 없이 이미지에 실린다.
DEPENDS = "openssl mosquitto cjson"

inherit cmake systemd useradd
S = "${WORKDIR}/git/daemon"
```

확인 방법:

```bash
grep -iE "mTLS 활성|비활성으로" tmp/work/*/adts-daemon/*/temp/log.do_configure
# RM_WORK_EXCLUDE += "adts-daemon" 이 있어야 이 로그가 남는다
```

```bitbake
do_install() {
    install -d ${D}/opt/adts
    install -m 0755 ${B}/adts_daemon ${D}/opt/adts/adts_daemon
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/adts-daemon.service ${D}${systemd_unitdir}/system/

    # 인증서와 camera.conf 는 런타임에 만들어진다. 이미지에 굽지 않고 자리만 만든다.
    install -d ${D}${sysconfdir}/adts/certs
    install -m 0644 ${S}/camera.conf.example ${D}${sysconfdir}/adts/camera.conf.example
}

SYSTEMD_SERVICE:${PN} = "adts-daemon.service"
SYSTEMD_AUTO_ENABLE = "enable"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--create-home --shell /bin/sh --user-group pi"
```

설계 판단 셋:

| 판단 | 근거 |
|---|---|
| 인증서를 이미지에 안 굽는다 | 구우면 모든 킷이 같은 개인키를 갖고, 그 이미지는 git 과 발표 자료를 오간다 |
| `/opt/adts` 경로 | 유닛의 `ExecStart` 가 거기를 가리킨다. `${bindir}` 로 옮기려면 유닛도 고쳐야 하는데 그 유닛은 Raspberry Pi OS 쪽 `install-service.sh` 도 쓰는 파일이라 진실이 갈라진다 |
| `pi` 계정 생성 | 유닛이 `User=pi` 로 돈다. Yocto 이미지에는 그 계정이 없어 만들지 않으면 서비스가 시작조차 못 한다 |

비밀번호는 여기서 정하지 않는다. 패키지가 비밀번호를 가지면 그 패키지를 쓰는 모든
이미지가 같은 비밀번호를 물려받는다. 이미지 레벨(`EXTRA_USERS_PARAMS`)에서 준다.

### 4.4 `adts-broker_git.bb`

```bitbake
DEPENDS = "openssl cjson"
inherit cmake systemd
S = "${WORKDIR}/git/broker"
```

`adts_enroll`(토큰 기반 클라이언트 인증서 발급 서비스), `gen-certs.sh`, enrollment unit,
mosquitto config/ACL 을 설치한다. `/etc/adts/certs` 는 0700 디렉터리만 만들고 CA·개인키를
굽지 않는다.

첫 부팅 후 운영자가 한 번 실행해야 한다.

```sh
/opt/adts/gen-certs.sh <RPi_IP>
```

그 전까지 mosquitto 와 adts-daemon 은 인증서가 없어 실패한다. 조용히 degraded 로 도는
것보다 시끄럽게 실패하는 편이 낫다는 이 프로젝트 전반의 원칙에 따른 것이다.

ACL 파일 권한에도 실측 근거가 있다.

```bitbake
# ACL 은 0700 + mosquitto 소유여야 한다. 0644 로 두면 mosquitto 가
# "world readable / owner is not mosquitto — 앞으로는 거부한다" 고 경고한다(실측).
install -m 0700 ${S}/mosquitto.acl.example ${D}${sysconfdir}/mosquitto/conf.d/adts.acl
```

소유자 변경은 mosquitto 계정이 있어야 하므로 `postinst` 에서 한다.

### 4.5 `mosquitto_%.bbappend`

```bitbake
# 레시피 자체는 그대로 쓴다. PACKAGECONFIG 가 이미 "ssl websockets systemd" 라서
# 8883 mTLS 리스너에 필요한 것이 다 켜져 있다.
#
# 단 하나 문제는 기본 mosquitto.conf 의 include_dir 가 주석 처리돼 있다는 것이다.
# 그래서 /etc/mosquitto/conf.d/ 에 파일을 넣어도 읽히지 않는다.
do_install:append() {
    echo "include_dir /etc/mosquitto/conf.d" >> ${D}${sysconfdir}/mosquitto/mosquitto.conf
}
FILES:${PN} += "${sysconfdir}/mosquitto/conf.d"
```

이 한 줄이 없으면 broker 레시피가 설치한 설정과 enrollment 서비스가 갱신하는 ACL 을
Mosquitto 가 읽지 못한다.

### 4.6 `adts-kit-config_1.0.bb`

sudoers 드롭인으로 `pi` 에게 무암호 sudo 를 주고(Raspberry Pi OS 와 같은 동작),
profile.d 드롭인으로 `/usr/sbin` 을 일반 사용자 PATH 에 추가한다. 둘 다 없으면 `pi` 로
로그인해도 `ifconfig` 가 `not found` 로 보인다. 명령이 없는 것이 아니라 PATH 밖에 있는
상태다.

```bitbake
# scarthgap 에는 UNPACKDIR 이 없다(더 나중 릴리스에서 도입됐다).
# file:// 소스는 ${WORKDIR} 에 그대로 풀리므로 S 를 거기로 맞춘다.
S = "${WORKDIR}"

do_install() {
    # sudoers 는 0440 root:root 여야 한다. 권한이 느슨하면 sudo 가 그 파일을
    # 무시하고, 그러면 "왜 sudo 가 안 먹지" 가 된다.
    install -d -m 0750 ${D}${sysconfdir}/sudoers.d
    install -m 0440 ${WORKDIR}/adts-pi ${D}${sysconfdir}/sudoers.d/adts-pi
}
```

계정 생성은 `adts-daemon` 이, 비밀번호는 `adts-image` 가, "로그인한 뒤 쓸 수 있는가"만
이 레시피가 담당한다.

### 4.7 `adts-image.bb` — 제품 조립

```bitbake
require recipes-core/images/core-image-minimal.bb

# adts-broker 가 mosquitto / bash / openssl-bin 을 RDEPENDS 로 끌어오므로
# 여기에 따로 적지 않는다.
IMAGE_INSTALL:append = " adts-drivers adts-daemon adts-broker adts-kit-config "

# core-image-minimal 은 packagegroup-core-boot 만 담는다. 무선에 필요한 것들은
# packagegroup-base 소속이라 따라오지 않으므로 직접 적는다.
IMAGE_INSTALL:append = " kernel-modules wpa-supplicant iw linux-firmware-rpidistro-bcm43455 "

IMAGE_FEATURES += "debug-tweaks ssh-server-openssh"
IMAGE_FSTYPES = "wic.bz2 wic.bmap tar.bz2"

IMAGE_BOOT_FILES:append = " \
    turret-overlay.dtbo;overlays/turret-overlay.dtbo \
    imu-overlay.dtbo;overlays/imu-overlay.dtbo \
    led-sw-overlay.dtbo;overlays/led-sw-overlay.dtbo "

# wic 이 이미지를 조립할 때 우리 dtbo 가 이미 DEPLOYDIR 에 있어야 한다.
do_image_wic[depends] += "adts-overlays:do_deploy"
```

`do_image_wic[depends]` 가 없으면 "파일 없음"으로 실패하거나, 운 나쁘면 지난 빌드의
낡은 dtbo 가 조용히 실린다. 가장 찾기 어려운 종류의 버그다.

`IMAGE_BOOT_FILES` 형식은 `DEPLOYDIR의소스;부트파티션내목적지` 다. RPi 펌웨어가
`overlays/` 아래에서 찾으므로 목적지를 그렇게 준다. 파일을 넣는 것과 `config.txt` 에
적는 것은 별개이고, 후자는 `RPI_EXTRA_CONFIG` 라 `local.conf` 에 남아 있다.

비밀번호 설정:

```bitbake
IMAGE_CLASSES += "extrausers"
# -P <평문> 은 쓸 수 없다. shadow 4.14 부터 -P 가 upstream 의 prefix 옵션이라
# "prefix must be an absolute path" 로 실패한다. 해시를 만들어 -p 로 준다:
#   openssl passwd -6 <평문>
#
# $ 를 반드시 \$ 로 이스케이프할 것. 이 값은 셸을 거치므로 $6 / $7 같은 조각이
# 위치 파라미터로 확장되어 조용히 사라진다(실제로 겪었다 — 해시 앞의 $6$salt$ 가
# 통째로 없어져 로그인이 안 됐다).
EXTRA_USERS_PARAMS = "usermod -p '\$6\$...' pi;"
```

`debug-tweaks` 와 이 줄은 최종 제출본에서 함께 제거한다. `debug-tweaks` 는 root 무암호
로그인·SSH 를 허용하고, 비밀번호 해시가 이미지에 박힌다.

---

## 5. 검증

| 항목 | 방법 | 등급 | 결과 |
|---|---|---|---|
| 레이어 인식 | `bitbake-layers show-layers` | B | 7개 |
| 커널 핀 적용 | `bitbake -e linux-raspberrypi \| grep LINUX_VERSION` | B | 6.12.75 |
| 드라이버·오버레이 빌드 | 단계별 이미지 phase2 | B | 성공 |
| `SRCREV` 4개 레시피 일치 | 2026-08-28 `grep SRCREV meta-adts` | B | 전부 `f199cf4` |
| 새 runtime 레시피 4종 | 개별 `bitbake` | B | 2026-08-27 전부 성공 |
| `bitbake adts-image` | — | B | 2026-08-27 성공 |
| manifest 포함 확인 | `*.manifest` | B | 우리 패키지 8종 + mosquitto·bash·openssl-bin |
| 데몬 조건부 컴파일 | `objdump -p \| grep NEEDED` | B | `libssl`·`libcrypto`·`libmosquitto`·`libcjson` 링크 확인 |
| 브로커 실기 기동 | `netstat -tln` | A | 8883·8443 LISTEN |

---

## 6. 참고

- 레이어: `yocto/meta-adts/conf/layer.conf`, `yocto/conf/bblayers.conf`
- 빌드 머신 설정: `yocto/conf/local.conf`
- 빌드 호스트: [image.md](image.md)
- 커널·DT 연결: [kernel-drivers-dt.md](kernel-drivers-dt.md)
