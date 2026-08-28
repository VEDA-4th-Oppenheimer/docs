# CV5 OpenSDK 애플리케이션 빌드 및 CAP 배포

Hanwha Vision CV5용 `tcp_server`, `calibration`과 추가 검증용
`lsd_line_detection`, `sam_segmentation` 앱의 Docker/CMake 빌드와 카메라 배포
절차를 정리한다. 현재 자동 캘리브레이션 구조는 두 검증용 앱을 사용하지 않는다. 공개 기준은
OpenSDK `704fbd1`, `a0832b6`, `d94b862`(2026-08-19~2026-08-24), 통합 및 성능
설정은 2026-08-24 로컬 `tcp_server`·`calibration` 1.2 작업본이다.

| 준비물 | 확인 내용 |
|---|---|
| 빌드 환경 | Linux 또는 Linux VM / Docker Engine / Docker Compose |
| SDK 이미지 | CV5 toolchain과 AppSupportPackage가 들어 있는 `opensdk:<tag>` |
| 대상 architecture | `aarch64`, SoC `cv5` |
| 공통 프로젝트 파일 | `docker-compose.yml`, `config/app_manifest.json`, `app/` |
| 앱별 OpenCV | CV5/AArch64용 헤더와 같은 버전의 `.so` |
| 카메라 설치 권한 | CAP 업로드 및 시작/정지 가능한 관리자 권한 |
| mTLS 운영 파일 | 전용 CA 인증서, 카메라 서버 인증서 및 서버 개인키 |

## 1. 소스 버전과 앱 구성을 확인한다

```bash
git clone https://github.com/VEDA-4th-Oppenheimer/OpenSDK.git
cd OpenSDK
git log -3 --oneline
```

```text
OpenSDK/
├── tcp_server/
├── calibration/
├── lsd_line_detection/     # 현재 구조와 분리된 추가 검증용 CAP
└── sam_segmentation/       # 현재 구조와 분리된 추가 검증용 CAP
```

2026-08-24 공개 Git의 `tcp_server`, `calibration` manifest 버전은 `1.0`이다. 별도
로컬 작업본은 두 앱 모두 `1.2`이며 `/tmp/calibration` 공유 경로, CPU 최적화와 시간
계측 차이가 있다. 원하는 기능이 실제 checkout에 포함되어 있는지 먼저 확인한다.

```bash
git log --oneline -- tcp_server calibration
```

CAP 설치 버전은 `config/app_manifest.json`의 `AppVersion`이 기준이다. `CHANGELOG`,
Git tag 또는 파일 생성 시각만 보고 설치 버전을 판단하지 않는다.

## 2. OpenSDK Docker 이미지와 환경변수를 준비한다

```bash
docker image ls opensdk
docker compose version

export SDK_VER=<설치된-opensdk-이미지-태그>
export SOC=cv5
```

`SDK_VER`는 실제 `docker image ls opensdk` 출력과 같아야 한다. SDK 이미지에는
`/opt/opensdk`, CV5 AArch64 compiler, `app_dispatcher`, `life_cycle_manager`가
포함되어 있어야 한다.

```bash
docker run --rm opensdk:${SDK_VER} \
  sh -c 'test -d /opt/opensdk && echo "OpenSDK image ready"'
```

컴파일러가 기본 위치가 아닌 경우 `OPENSDK_TOOLCHAIN_PREFIX`에 실제 AArch64
toolchain prefix를 지정한다. 일반 Ubuntu/WSL의 x86-64 compiler와 라이브러리로
빌드하면 CV5에서 실행할 수 없다.

## 3. 공통 CAP을 빌드한다

현재 구조에서 사용하는 각 앱 디렉터리에서 앱 이름을 지정하고 Docker Compose를
실행한다.

```bash
cd tcp_server
export APP_NAME=tcp_server
docker compose up --build
```

위 `cd` 예시는 각각 `OpenSDK/` 루트에서 시작한다. 다른 앱을 빌드할 때는 먼저
OpenSDK 루트로 돌아간다. 내부 실행 흐름은 다음과 같다.

```text
docker compose
  -> OpenSDK 이미지 실행
  -> 프로젝트를 /opt/<APP_NAME>에 mount
  -> CV5 toolchain으로 CMake configure/build/install
  -> SDK dispatcher 및 runtime library 배치
  -> opensdk_packager -s cv5
  -> CAP 산출물 생성
```

빌드가 끝나면 프로젝트 내 생성된 `.cap` 파일, manifest 앱 이름·버전과 수정 시각을
확인한다. CAP, `app/build`, 모델·개인키 및 runtime storage를 Git에 무분별하게
커밋하지 않는다.

## 4. 추가 검증 CAP을 별도로 빌드한다

`lsd_line_detection`과 `sam_segmentation`은 현재 자동 캘리브레이션의 필수 빌드·배포
대상이 아니다. LSD 동작을 추가로 검증할 때만 다음 독립 CAP을 빌드한다.

```bash
cd lsd_line_detection
export APP_NAME=lsd_line_detection
docker compose up --build
```

이 CAP의 선분 결과는 `calibration` 앱이나 `run_real_calibration`에 전달되지 않는다.

### MobileSAM 추가 검증

`sam_segmentation`은 현재 자동 캘리브레이션의 필수 빌드·배포 대상이 아니다.
MobileSAM ONNX와 4채널 마스크를 추가로 검증할 때만 독립 CAP으로 빌드한다.

```bash
cd sam_segmentation
export APP_NAME=sam_segmentation
docker compose up --build
```

`sam_segmentation`에는 다음 CV5용 OpenCV 4.12 모듈이 필요하다.

```text
app/includes/opencv4/
app/libs/libopencv_core.so*
app/libs/libopencv_imgproc.so*
app/libs/libopencv_imgcodecs.so*
app/libs/libopencv_dnn.so*
```

다음 모델 리소스도 실제 CAP에 포함되어야 한다.

```text
app/res/models/mobile_sam_image_encoder.onnx
app/res/models/mobile_sam_mask_decoder.onnx
app/res/models/mobile_sam_grid_prompts.bin
```

`mobile_sam.pt`는 ONNX 재변환에만 사용한다. OpenCV 4.12에서 동적
`Shape/Slice/Gather`가 남은 decoder는 로드에 실패할 수 있으므로 프로젝트의 고정
shape export 결과를 사용한다.

이 CAP의 마스크 결과는 `calibration` 앱이나 `run_real_calibration`에 전달되지 않는다.
현재 구조만 배포하는 경우 이 절 전체를 생략한다.

## 5. Calibration 의존성을 교차 컴파일한다

`calibration` 앱은 OpenSDK 앱 본체 외에 `run_real_calibration` Core와 아래 의존성을
같이 빌드한다.

| 의존성 | 기준 버전 | 목적 |
|---|---|---|
| Eigen | `3.4.0` | 행렬, 회전, 벡터 계산 |
| nlohmann-json | `3.11.3` | LiDAR·결과 JSON 처리 |
| yaml-cpp | `0.8.0` | upstream helper 및 설정 연결 |
| Ceres Solver | `2.2.0` | 비선형 6-DoF refinement |
| OpenCV | `4.12.0` | 영상, 선분, 렌즈 보정 및 feature 처리 |

```bash
cd calibration
export APP_NAME=calibration
export SOC=cv5
export SDK_VER=<설치된-opensdk-이미지-태그>
docker compose up --build
```

이 Compose 실행은 SDK 컨테이너 안에서 아래 순서로 처리한다.

```text
dependencies/build_cv5_dependencies.sh
  -> Eigen / nlohmann-json / yaml-cpp / Ceres / OpenCV 준비
  -> app/third_party/include, app/third_party/lib 구성
  -> app CMake 및 imported automatic_calibration Core 빌드
  -> app/bin/run_real_calibration 설치
  -> app/libs에 AArch64 runtime library 복사
  -> opensdk_packager -s cv5
```

`dependencies/build_cv5_dependencies.sh`는 OpenSDK Docker 컨테이너 전용이다.
일반 Windows PowerShell, Ubuntu host 또는 WSL에서 직접 실행하면 CV5 compiler와
`/opt/opensdk`를 찾지 못한다.

로컬 1.2는 Release 빌드, Cortex-A76 CPU tuning 및 OpenCV `CPU_BASELINE=NEON`을
활성화한다.

```bash
cmake -S app -B app/build \
  -DSOC=cv5 \
  -DCMAKE_BUILD_TYPE=Release
```

Ceres는 `MINIGLOG=ON`으로 빌드하며 별도 glog/gflags 공유 라이브러리에 의존하지
않는다. OpenCV 소스는 최초 빌드에서 다운로드될 수 있으므로 네트워크와 디스크 공간을
확인한다.

## 6. 산출물과 architecture를 검증한다

SDK 컨테이너 또는 Linux 빌드 환경에서 실행 파일과 라이브러리의 architecture를
확인한다.

```bash
file app/bin/run_real_calibration
file app/third_party/lib/libceres.so*
file app/libs/libopencv_core.so*
```

정상적인 CV5 산출물은 `aarch64` 또는 `ARM aarch64`로 표시되어야 한다. `x86-64`이면
호스트 라이브러리를 잘못 넣은 것이다.

```bash
readelf -d app/bin/run_real_calibration
```

`NEEDED` 목록의 OpenCV, Ceres, yaml-cpp 공유 라이브러리가 CAP의 `app/libs`에서
해결되는지 확인한다. 누락된 의존성이 있으면 앱은 설치되더라도
`core_not_available` 또는 loader 오류가 발생할 수 있다.

## 7. 카메라에 CAP을 설치한다

1. 대상 카메라의 관리자 화면에서 기존 앱 이름과 `AppVersion`을 확인한다.
2. 새 `.cap` 파일을 업로드하고 `tcp_server`, `calibration`을 각각 설치한다.
3. 앱 이름, 실제 설치 버전과 앱 웹 페이지 접근 가능 여부를 확인한다.
4. LSD 추가 검증을 수행할 때만 `lsd_line_detection` CAP을 별도로 설치한다.
5. MobileSAM 추가 검증을 수행할 때만 `sam_segmentation` CAP을 별도로 설치한다.
6. 앱별 로그에서 LifeCycleManager, AppDispatcher와 필수 `.so`가 정상적으로
   초기화되는지 확인한다.

`tcp_server`와 `calibration`은 하나의 CAP이 아니다. 두 앱을 함께 설치해도 공개
`tcp_server` 1.0이 `storage/uploads`를 사용하면 `calibration`이 JSON을 찾지 못한다.
통합에는 `/tmp/calibration` 저장 기능이 포함된 작업본 또는 동등한 수정이 필요하다.

## 8. mTLS 인증서를 안전하게 배포한다

카메라에는 아래 세 파일만 설치한다.

```text
storage/cert/ca.crt
storage/cert/server.crt
storage/cert/server.key
```

```bash
chmod 644 storage/cert/ca.crt storage/cert/server.crt
chmod 600 storage/cert/server.key
```

RPi에는 별도의 daemon client 인증서와 개인키를 둔다. 카메라 서버 인증서는 송신측이
검증하는 서버 SAN을 포함해야 하고 client 인증서는 전용 CA에서 발급해야 한다.

- `ca.key`, `server.key`, `daemon.key`를 Git 또는 공개 CAP에 넣지 않는다.
- manifest에 SSH 비밀번호를 하드코딩하지 않는다.
- 시험용 SSH를 열었다면 provisioning 후 다시 비활성화한다.
- 현재 서버 구현은 client CA 체인은 확인하지만 `CN=adts-daemon` 강제 검사는
  확인되지 않았으므로 운영 전에 보완한다.

## 9. 운영 동작을 점검한다

```text
1. tcp_server 시작
   -> 2222 listen / 인증서 준비 / tls_listening 확인

2. RPi scan 실행
   -> organized JSON 생성
   -> mTLS 업로드
   -> /tmp/calibration/<session>/<file>.json 게시 확인

3. calibration 웹 화면 실행
   -> GET /files에서 세션 확인
   -> 파일 선택 / 시작
   -> CH1~CH4 Snapshot 생성
   -> CH1 staging 및 Core 실행

4. 결과 확인
   -> /status의 상태와 request_elapsed_ms 확인
   -> output/core.log 및 calibration_result.json 확인
   -> candidate_ready 또는 rejected 확인
```

`candidate_ready`는 후보 생성이지 제품 승인이나 RT 자동 활성화가 아니다. 실제
`activation_allowed`는 `false`여야 한다.

## 흔한 빌드·배포 문제

| 증상 | 원인과 확인 내용 |
|---|---|
| OpenSDK 이미지가 없음 | `SDK_VER`와 `docker image ls opensdk` 결과가 다름 |
| `AppSupportPackage is missing` | CV5 dispatcher/LCM이 빠진 불완전한 SDK 이미지 |
| `.so` symlink `Operation not permitted` | Windows/VirtualBox 공유 폴더 제한; Linux 로컬 파일시스템에서 빌드 |
| `opencv2/opencv.hpp`를 못 찾음 | `app/includes/opencv4` 또는 third-party include 누락 |
| DNN `Slice`/`Gather` 오류 | OpenCV 4.12 비호환 decoder ONNX |
| `core_not_available` | AArch64 Core 실행 파일, Ceres/OpenCV `.so`, execute 권한 누락 |
| `calibration` 파일 목록이 비어 있음 | `tcp_server` 1.0의 `storage/uploads`와 `/tmp/calibration` 불일치 |
| Snapshot 채널이 다르게 보임 | UI `1~4`와 SDK `0~3` 혼동 또는 manifest CH3 표기 오류 |
| 장치 재부팅 후 결과가 없음 | `/tmp/calibration`이 휘발성 저장소 |
| 성능이 기대보다 느림 | Debug 빌드, staged 옵션 누락, 과다 thread, 열 제한 또는 잘못된 intrinsic |

정상 배포 여부는 Git push나 CAP 생성만으로 판정하지 않는다. 실제 카메라에서 앱
버전, architecture, 인증서, RPi 업로드, 4채널 Snapshot, Core 결과와 오류 경로를 모두
검증한다.
