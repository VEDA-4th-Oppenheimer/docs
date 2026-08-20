# RPi 커널 모듈 크로스컴파일 환경 설정 (Ubuntu → Raspberry Pi arm64)

> 출처: CrossCompile 환경세팅 (팀 위키 문서) · 2026-08-21 기준 스냅샷

**이 문서대로 하면 한 번에 됩니다.** Ubuntu(x86_64) 빌드머신에서 Raspberry Pi(arm64)
커널 모듈(`turret_driver.ko`)을 크로스컴파일해서, Pi에 `insmod`할 때 **vermagic / CRC
에러 없이** 로드되도록 환경을 맞추는 검증된 절차입니다. 아래 "자주 하는 실수"를 반드시
먼저 읽으세요.

## 0. 이 방식의 핵심 아이디어

Pi에 설치된 헤더 패키지(`linux-headers-*`)를 그대로 빌드에 쓰려고 하면 함정에 빠집니다.
그 패키지의 `scripts/`는 `/usr/lib/linux-kbuild-*/`를 가리키는 심링크이고, 그 안의 빌드
호스트 툴(`fixdep`, `modpost`, `genksyms` …)이 **전부 aarch64 ELF 바이너리**라 x86_64
Ubuntu에서 실행되지 않습니다.

그래서 **Raspberry Pi 커널 _소스 트리_(git)를 쓰고, Pi 실물에서 `.config`와
`Module.symvers` 두 파일만 가져와 덮어씁니다.** 소스 트리에는 호스트 툴 `.c` 소스가 들어
있어, 어떤 타깃(ARCH/CROSS_COMPILE)이든 호스트 툴은 항상 **로컬 네이티브 x86_64 gcc**로
컴파일됩니다. 정확성(vermagic/CRC)은 Pi의 authoritative한 `.config`·`Module.symvers`로
보장합니다.

**이 문서의 실행 예시 값** (환경에 맞게 바꾸세요)

- Pi 커널: `uname -r` = `6.12.75+rpt-rpi-v8`, 패키지 `1:6.12.75-1+rpt1`
- SUBLEVEL = `75`, `CONFIG_LOCALVERSION` = `-v8`, 중간 문자열 = `+rpt-rpi`
- 베이스 커밋: `8561d7d545fc` (SUBLEVEL=75, `stable/linux-6.12.y` 병합)
- 빌드머신: Ubuntu 24.04 x86_64, 툴체인 `aarch64-linux-gnu-gcc-13`

## 1. Pi 쪽 준비 (커널 버전 고정 + 버전 문자열 확인)

```sh
# === Raspberry Pi에서 실행 ===
uname -r                        # 예: 6.12.75+rpt-rpi-v8  ← 이 문자열이 KREL. 반드시 기록.
dpkg -l | grep linux-image      # 예: 1:6.12.75-1+rpt1

# apt 자동 업그레이드가 커널을 올려 vermagic을 깨뜨리지 않도록 hold
sudo apt-mark hold linux-image-rpi-v8 linux-headers-rpi-v8
apt-mark showhold               # 두 패키지가 보이면 OK
```

## 2. Ubuntu 빌드머신: 툴체인 & 빌드 의존성 설치

```sh
sudo apt update
sudo apt install -y gcc-aarch64-linux-gnu build-essential \
     git bc bison flex libssl-dev libelf-dev
```

`gcc-13`(기본)로 충분합니다. `gcc-14`를 설치하려고 삽질하지 마세요 — "자주 하는 실수 #4" 참고.

## 3. Pi 실물에서 `.config` / `Module.symvers` 두 파일만 가져오기

```sh
KREL=6.12.75+rpt-rpi-v8              # Pi의 uname -r
PI=pi@172.20.26.191                  # Pi 주소

mkdir -p ~/pi-kernel
scp $PI:/usr/src/linux-headers-$KREL/.config        ~/pi-kernel/.config
scp $PI:/usr/src/linux-headers-$KREL/Module.symvers ~/pi-kernel/Module.symvers
```

**Pi의 `linux-headers` 디렉토리 전체나 `linux-kbuild` 패키지를 복사하지 마세요.** 그 안의
`scripts/`·`tools/`는 aarch64 바이너리라 x86_64에서 못 씁니다. 필요한 건 `.config`와
`Module.symvers` **딱 두 파일**뿐입니다.

## 4. RPi 커널 소스 클론 + 정확한 베이스 커밋 체크아웃

```sh
sudo git clone --branch rpi-6.12.y https://github.com/raspberrypi/linux.git /usr/src/linux
sudo chown -R $USER:$USER /usr/src/linux
cd /usr/src/linux

# Pi의 SUBLEVEL과 같은 값이 처음 도입된 커밋을 찾는다
SUB=$(echo $KREL | cut -d. -f3 | grep -oE '^[0-9]+')     # 예: 75
BASE=$(git log --reverse --oneline --first-parent -S"SUBLEVEL = $SUB" -- Makefile | head -1 | awk '{print $1}')
echo "BASE=$BASE"

# 확인: VERSION/PATCHLEVEL/SUBLEVEL 이 Pi와 일치해야 함 (예: 6 / 12 / 75)
git show $BASE:Makefile | grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) '

git checkout -b build-$KREL $BASE
```

**브랜치 tip(최신)을 그대로 쓰지 마세요.** `rpi-6.12.y`는 롤링 브랜치라 tip의 SUBLEVEL이
이미 `95` 등으로 이동해 있어 Pi의 `75`와 안 맞습니다. 반드시 SUBLEVEL 일치 커밋을 pin 하세요.

## 5. Pi의 `.config` 배치 + 버전 문자열(localversion) 맞추기

```sh
cp ~/pi-kernel/.config .config

# 커널 릴리스 문자열 = KERNELVERSION + [localversion파일] + CONFIG_LOCALVERSION + LOCALVERSION + scm
#   6.12.75      +      +rpt-rpi       +       -v8         +    (빈값)    + (빈값)
printf '+rpt-rpi' > localversion-rpt
```

중간 조각 구하는 법: `KREL`(`6.12.75+rpt-rpi-v8`)에서 앞의 `6.12.75`와 뒤의
`CONFIG_LOCALVERSION`(`-v8`)을 떼면 `+rpt-rpi`가 남습니다.
**`echo` 말고 `printf`로** — 개행이 들어가면 안 됩니다.

## 6. prepare (호스트 툴을 네이티브 x86_64로 빌드)

```sh
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make olddefconfig
make LOCALVERSION= modules_prepare
```

**`LOCALVERSION=`(빈값)를 빼먹지 마세요.** 빼면 git이 tag가 아닌 커밋에서 dirty로 판단해
릴리스 문자열 끝에 `+`를 붙여 `6.12.75+rpt-rpi-v8+`가 되고, vermagic이 어긋나 `insmod`가
거부됩니다.

## 7. ★ 체크포인트: `kernel.release`가 Pi의 `uname -r`과 정확히 일치하는지 확인

```sh
cat include/config/kernel.release
# 반드시  6.12.75+rpt-rpi-v8  (= Pi의 uname -r) 와 100% 동일해야 함.
# 다르면 여기서 멈추고 5~6단계를 다시 점검. (절대 그냥 진행하지 말 것)

# 호스트 툴이 네이티브인지도 확인 (x86-64 여야 정상)
file scripts/basic/fixdep scripts/mod/modpost
```

## 8. Pi의 `Module.symvers` 덮어쓰기 (CRC 정확성)

```sh
cp ~/pi-kernel/Module.symvers Module.symvers
```

`Module.symvers`는 `modules_prepare`로 재생성되지 않습니다(전체 vmlinux 빌드가 필요).
반드시 Pi 실물의 것을 써야 하며, `CONFIG_MODVERSIONS=y`라 CRC가 틀리면 `insmod`가 조용히
깨지지 않고 명확히 거부합니다(안전망).

## 9. 드라이버 빌드 + vermagic 검증

```sh
cd ~/lecture/turret_driver
make clean
make rpi RPI_KDIR=/usr/src/linux LOCALVERSION=

# 검증: 아래 두 vermagic이 완전히 같아야 함
modinfo -F vermagic turret_driver.ko
# 기대: 6.12.75+rpt-rpi-v8 SMP preempt mod_unload modversions aarch64
```

`turret_driver`의 `Makefile`은 `rpi` 타깃에서 `KDIR`이 아니라 `RPI_KDIR` 변수를 씁니다.
안전을 위해 `LOCALVERSION=`를 여기에도 넘깁니다.

## 10. Pi에 배포 & insmod

```sh
scp turret_driver.ko $PI:~/

# sudo 비밀번호 입력을 위해 -t (TTY) 필요
ssh -t $PI 'sudo insmod ~/turret_driver.ko && dmesg | tail -15 && lsmod | grep turret'
```

`sudo: a terminal is required…` 에러가 났다면 `ssh`에 `-t`가 빠졌기 때문입니다.

## 검증 체크포인트 요약

| 확인 지점 | 명령 | 기대값 |
|---|---|---|
| 커널 릴리스 | `cat include/config/kernel.release` | Pi의 `uname -r`과 완전 일치 |
| 호스트 툴 아키텍처 | `file scripts/mod/modpost` | `x86-64` (aarch64 아님) |
| 모듈 vermagic | `modinfo -F vermagic turret_driver.ko` | `<KREL> SMP preempt mod_unload modversions aarch64` |
| 최종 로드 | `sudo insmod` + `lsmod \| grep turret` | 에러 없이 로드, 목록에 표시 |

## ⚠️ 자주 하는 실수 (반드시 읽기)

| # | 실수 | 왜 문제인가 / 올바른 방법 |
|---|---|---|
| 1 | Pi의 `linux-headers`/`linux-kbuild` 패키지를 통째로 복사해서 빌드 | 그 안의 `fixdep`·`modpost` 등이 **aarch64 바이너리**라 x86_64에서 실행 불가. → **git 소스 트리**를 쓰면 호스트 툴이 네이티브로 컴파일됨 |
| 2 | `rpi-6.12.y` 브랜치 tip을 그대로 사용 | tip의 SUBLEVEL이 이미 이동(예: 95)해 Pi(75)와 불일치. → SUBLEVEL 일치 커밋을 **pin** |
| 3 | `LOCALVERSION=`를 안 넘김 | git dirty로 릴리스 끝에 `+`가 붙어 `…-v8+` → vermagic 불일치. → `prepare`와 모듈 빌드 **둘 다**에 `LOCALVERSION=` |
| 4 | `.config`의 `CONFIG_CC_VERSION_TEXT`가 gcc-14라서 gcc-14를 설치하려 함 | 컴파일러 버전은 vermagic/CRC에 **영향 없음**(CRC는 심볼 타입 시그니처 기반). gcc-13으로 충분 |
| 5 | `Module.symvers`를 `modules_prepare`로 만들려 함 | 전체 vmlinux 빌드가 필요해 재현 불가. → **Pi 실물**의 것을 복사 |
| 6 | Pi 커널을 `apt-mark hold` 안 함 | 자동 업그레이드로 커널이 올라가면 vermagic이 깨짐 |
| 7 | localversion 파일을 `echo`로 생성 | 개행이 붙어 문자열이 깨질 수 있음. → `printf` 사용 |
| 8 | 7단계(`kernel.release` 확인)를 건너뜀 | 여기서 안 맞으면 뒤 단계는 무조건 실패. **빌드 전에 매번 확인** |

## 원리: 릴리스 문자열은 어떻게 조립되는가

`scripts/setlocalversion`의 마지막 줄:

```sh
echo "${KERNELVERSION}${file_localversion}${config_localversion}${LOCALVERSION}${scm_version}"
```

각 조각을 예시에 대입하면:

- `KERNELVERSION` = `6.12.75` (소스 트리 Makefile의 VERSION/PATCHLEVEL/SUBLEVEL)
- `file_localversion` = `+rpt-rpi` (우리가 만든 `localversion-rpt` 파일 내용)
- `config_localversion` = `-v8` (`.config`의 `CONFIG_LOCALVERSION`)
- `LOCALVERSION` = 빈값 (make에 `LOCALVERSION=`로 넘김)
- `scm_version` = 빈값 (`LOCALVERSION`이 "set" 상태면 git `+` 억제됨)

→ 결과: `6.12.75+rpt-rpi-v8`. 이 문자열이 `utsrelease.h`의 `UTS_RELEASE`가 되고, 그게 곧
모듈 vermagic의 앞부분이 되어 Pi 실행 커널과 일치합니다.

**검증 완료 결과** — 위 절차로 빌드한 `turret_driver.ko`의 vermagic:

```
6.12.75+rpt-rpi-v8 SMP preempt mod_unload modversions aarch64
```

= Pi 실행 커널의 기대 vermagic과 완전 일치, `insmod` 성공.
