# Yocto 이미지와 빌드 호스트

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-YOC-70` |
| 담당 | 이현우 (설계·문서). 빌드 실행은 사용자가 직접 한다 |
| 대상 소스 | `yocto/Dockerfile`, `yocto/ybuild.sh`, `yocto/conf/local.conf` |
| 기준 코드 | Yocto `8f4e897` (2026-08-20) + 미커밋 레시피 4종 |
| 타깃 | `raspberrypi4-64` / Poky 5.0.19 Scarthgap LTS / 커널 6.12.75 |

---

## 1. 개요

Raspberry Pi 4 에서 킷을 구동할 재현 가능한 커스텀 리눅스 이미지를 만든다. 커널·드라이버·
디바이스 트리를 소스에서 함께 빌드하고 검증한 커밋으로 고정해, 빌드 시점이나 작업자가
달라도 같은 결과를 얻는 것이 목표다.

```
Dockerfile -> ybuild.sh setup/init -> BitBake -> meta-adts 레시피
  -> 커널 모듈·DTBO·데몬·브로커 -> adts-image -> SD 카드 -> Raspberry Pi 4
```

| 항목 | 값 |
|---|---|
| Target | `raspberrypi4-64` |
| Yocto | Poky 5.0.19 / Scarthgap LTS |
| Kernel | `linux-raspberrypi 6.12.75` (SRCREV 고정) |
| Init | systemd |
| Build host | Apple Silicon Mac + arm64 Ubuntu 22.04 Docker |
| Custom layer | `meta-adts` |
| Output | `wic.bz2`, `wic.bmap`, `tar.bz2` |

레시피 내용은 [layers-and-recipes.md](layers-and-recipes.md), 커널·DT 연결은
[kernel-drivers-dt.md](kernel-drivers-dt.md), 빌드·플래시 절차는
`guides/yocto-build.md` 에 있다.

---

## 2. 시스템 경계

| 영역 | 역할 |
|---|---|
| macOS 저장소 | 사람이 수정하는 `conf/`, `meta-adts/`, 산출물 보관 |
| Docker image | BitBake 가 실행될 arm64 Ubuntu 22.04 환경 |
| Docker named volume `/work` | Poky, 외부 레이어, `build/tmp` — 대소문자 구분 필요 |
| bind mount `/mnt/mac` | `yocto/` 저장소를 컨테이너에 노출 |
| RPi boot partition | 펌웨어, 커널, `config.txt`, DTBO |
| RPi rootfs | systemd, 커널 모듈, 사용자 공간 패키지 |

---

## 3. 설계

### 3.1 Apple Silicon 네이티브 arm64 빌드

amd64 `crops/poky` 이미지를 QEMU 로 돌리지 않고 네이티브 arm64 호스트 빌드를 택했다.

| 얻는 것 | 대가 |
|---|---|
| QEMU 에뮬레이션 성능 손실 없음 | x86_64 native sstate 를 재사용할 수 없다 |

`run_in` 이 항상 `--platform linux/arm64` 를 지정한다.

### 3.2 빌드 트리는 named volume

macOS APFS 는 기본이 대소문자 비구분이다. Yocto 빌드 트리를 거기 직접 두면 BitBake
파싱 단계에서 문제가 생긴다.

```
Mac yocto/ ──bind mount──> /mnt/mac      편집·Git 관리·산출물 반출
Docker volume adts-yocto ─> /work        Linux ext4 — 대소문자 구분 보장
```

소스와 설정은 Git 저장소(`/mnt/mac`)에, 빌드 트리는 볼륨(`/work`)에 두므로 빌드 볼륨을
통째로 지워도 프로젝트 정의는 보존된다.

### 3.3 커널과 모듈을 한 BitBake 빌드에서 생성

`vermagic` 과 심볼 CRC 불일치 가능성을 구조적으로 제거한다. 같은 버전 번호라고 해서
다른 OS 빌드의 `.ko` 를 서로 적재할 수 있는 것은 아니다. 커널 config,
`CONFIG_LOCALVERSION`, `Module.symvers` 까지 맞아야 한다.

### 3.4 BitBake 는 root 실행을 거부한다

Dockerfile 이 UID 1000 의 `yocto` 사용자를 만든다. UTF-8 locale, git `safe.directory`,
빌드용 identity 도 함께 설정하고, 대화형 셸에서는 `/work/poky/oe-init-build-env` 를 자동
source 한다.

---

## 4. `ybuild.sh`

```bash
docker build --platform linux/arm64 -t adts-yocto:scarthgap .
./ybuild.sh setup
./ybuild.sh init
./ybuild.sh bitbake 'adts-image'
```

| 명령 | 하는 일 |
|---|---|
| `setup` | `/work` 에 poky, meta-raspberrypi, meta-openembedded clone |
| `init` | `/work/build` 에 Yocto 환경 생성 + 호스트 conf 2개 복사 + 레이어 검증 |
| `bitbake <target>` | 환경 source 후 타깃 실행 |
| `shell` | 대화형 셸 |
| `run '<cmd>'` | 컨테이너에서 한 줄 실행 |
| `df` | 볼륨 사용량 |

`init` 은 호스트의 `conf/local.conf`·`conf/bblayers.conf` 를 build conf 로 **복사**한다.
호스트 파일을 고친 뒤 `init` 을 다시 돌려야 반영된다.

### 4.1 자원 관리

| 설정 | 값 |
|---|---|
| `BB_NUMBER_THREADS` | 8 |
| `PARALLEL_MAKE` | `-j 8` |
| `rm_work` | 활성 — 성공한 작업 디렉터리 정리 |
| `RM_WORK_EXCLUDE` | `linux-raspberrypi`, `adts-daemon` |
| `BB_DISKMON_DIRS` | 디스크 여유가 임계 아래로 가면 빌드 중단 |

`adts-daemon` 을 `RM_WORK_EXCLUDE` 에 넣은 이유는 `log.do_configure` 를 남기기
위해서다. CMake 가 OpenSSL/MQTT 를 조용히 빼고 빌드했는지 확인하려면 그 로그가
필요하다([layers-and-recipes.md](layers-and-recipes.md) 4.3).

### 4.2 진단 명령

```bash
bitbake -n adts-image                 # dry run
bitbake -c cleansstate adts-drivers   # 특정 레시피만 재빌드
bitbake -e adts-drivers               # 변수 최종값 확인
bitbake-layers show-layers
bitbake-layers show-recipes | grep adts
```

`bitbake -e` 가 기준이다. 여러 레이어를 거친 뒤 변수가 실제로 어떤 값이 되었는지
확인하는 유일한 방법이고, 레시피 파일을 읽는 것만으로는 bbappend 와 우선순위의 결과를
알 수 없다.

---

## 5. 재현성

목표는 "빌드된다"가 아니라 "누가 언제 빌드해도 같은 것이 나온다"이다.

### 5.1 고정된 것

커널:

| 항목 | 값 |
|---|---|
| `LINUX_VERSION` | `6.12.75` |
| `SRCREV_machine` | `8561d7d545fc55308ff98161ef1819f181f53ca6` |
| `SRCREV_meta` | `e66f40994fc740818776a0f3af55e8b6d74bfbef` |

ADTS 소스:

| 항목 | 값 |
|---|---|
| Repository | `github.com/VEDA-4th-Oppenheimer/RPi.git` |
| Branch | `main` (fetch 경로일 뿐) |
| `SRCREV` | `7b347a4e41deeaf16da584aca48ca2c1420d319f` |

브랜치는 fetch 경로일 뿐이고 결과는 `SRCREV` 가 고정한다. 드라이버·오버레이·데몬·브로커
네 레시피가 모두 같은 커밋을 쓴다.

이 `SRCREV` 는 RPi `main` 보다 뒤처져 있다. 제품 이미지를 만들 때 갱신해야 한다.

### 5.2 고정되지 않은 것

`ybuild.sh setup` 이 외부 레이어 3종(poky, meta-raspberrypi, meta-openembedded)을
`git clone --depth 1 -b scarthgap` 으로 받는다. 브랜치 tip 이므로 날짜가 달라지면 다른
커밋을 받는다. 이 파트에 남은 유일한 재현성 구멍이다.

### 5.3 체크리스트

| | 항목 |
|---|---|
| 완료 | 머신·배포판 계열 명시 |
| 완료 | 커널 source revision 고정 |
| 완료 | 드라이버·오버레이 source revision 고정 |
| 완료 | Dockerfile 로 호스트 의존성 정의 |
| 완료 | 전용 제품 image recipe 작성 (`adts-image.bb`) |
| 미완 | Poky / meta-raspberrypi / meta-openembedded revision 고정 |
| 미완 | `.gitignore` 수정 후 image recipe 추적 |
| 미완 | 새 레시피 4개 커밋 |
| 미완 | 배포 라이선스와 `LIC_FILES_CHKSUM` 정리 |
| 미완 | 빌드별 commit/revision 자동 기록 |

---

## 6. 검증

| 항목 | 방법 | 등급 | 결과 |
|---|---|---|---|
| Docker arm64 이미지 빌드 | `docker build` | B | 성공 |
| `setup` / `init` | `bitbake-layers show-layers` | B | 7개 레이어 인식 |
| `core-image-minimal` 빌드 | 첫 빌드 약 50분 (M4 Pro 8코어) | B | 성공 |
| 단계별 이미지 산출 | `yocto/images/` 타임스탬프 | B | 2026-08-20 phase1b·phase2·phase3 생성 |
| `adts-image` 빌드 | — | D | 미실행 |
| 부팅 후 장치 확인 | — | D | 미실행. `guides/yocto-build.md` 체크리스트 |
| 레시피 4종 추적 | `git ls-files` | D | 2026-08-24 기준 `recipes-adts/`·`recipes-connectivity/` 미추적 |

---

## 7. 참고

- 소스: `yocto/Dockerfile`, `yocto/ybuild.sh`, `yocto/conf/local.conf`
- 레시피: [layers-and-recipes.md](layers-and-recipes.md)
- 커널·DT: [kernel-drivers-dt.md](kernel-drivers-dt.md)
- 절차: `guides/yocto-build.md`
