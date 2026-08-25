# 광진 — 담당 범위와 프로젝트 기록

## 기록 기준

이 문서는 Git author `lkj000619`로 확인되는 변경과, 개인 작업 폴더에서 확인한 문서·실험 산출물을 구분해 기록한다. 수치와 상태는 2026-08-25 기준이며, 실험 결과는 제품 승인 결과와 동일하게 해석하지 않는다.

| 구분 | 기준 |
|---|---|
| 개인 식별 | Git author `lkj000619` |
| 주 작업 공간 | `auto_calib/develop`, `auto_calib/QT` |
| OpenSDK 작업 공간 | `OpenSDK_repo`의 구버전 auto_calib Core 업데이트 |
| 별도 분석 자료 | `wireshark_log`의 RTSP 분석 문서와 분석 스크립트 |
| 기록 원칙 | 직접 작성·수정·검증한 범위만 개인 기여로 기록 |

## 담당 범위 요약

| 작업 영역 | 개인 기여로 기록하는 내용 | 근거 |
|---|---|---|
| Calibration Core | Core workspace 구성, 입력·좌표계 계약, staged 탐색 개선, 구조 특징·품질 gate·검증 코드 | `auto_calib/develop`의 `2c98554`, `f92626e`, `f684cd6` |
| Jenkins 및 재현성 | 현재 Freestyle 수집 Job 분석·운영 문서화, CH1/scene0 반복 실험, conformance 계획과 통합 helper script 작성 | `f684cd6`, `automatic_calibration/docs/JENKINS_*.md`, `scripts/jenkins-capture-and-scan.sh` |
| Calibration 실험 | Core 검증·Jenkins 재현성과 B0 기준선, T1 Structural/T2 Panorama analyzer 후보 실험을 목적별로 분리 기록 | `f684cd6`, T1 `79aeb0d`, T2 `afd277a` |
| Manual Calibration | ChArUco board 생성, intrinsic/왜곡 보정 입력, camera–marker 및 예비 LiDAR 기준 비교 | `2c98554`, `manual_calibration/`, `output/pdf/` |
| Qt 공간 정합 | CCTV–LiDAR 공간 좌표 정합, 2D/3D 시각화, metadata replay·테스트, proto v6 진단·축별 오류·IMU 수평 경고 | `auto_calib/QT`의 `7935fc9` |
| RTSP 분석 | Wireshark/RTSP/RTP 패킷 측정, 장애 원인, GStreamer/FFmpeg·GPU·크로스 플랫폼 검토 문서와 재현 스크립트 | `wireshark_log`의 분석 문서·스크립트, 사용자 확인 |
| 문서·실험 산출물 | 프로젝트 계획, 논문 조사, 제안서 템플릿·생성 산출물 정리 | `auto_calib/project_plan/`, `paper_review/`, `artifacts/` |
| OpenSDK Core 업데이트 | 타 팀원이 작성한 OpenSDK calibration 앱에 포함된 구버전 auto_calib Core를 최신 Core 변경에 맞춰 동기화하고 실행 옵션·K+D 프로파일을 갱신 | `OpenSDK_repo`의 `d94b862` |

## 작성 문서 구성

| 문서 경로 | 목적 |
|---|---|
| [Automatic Calibration Core](../../components/calibration/auto-core.md) | auto_calib 커밋 기준 Core 구조·입력 계약·목적함수·staged 탐색·상태 수명주기와 전체 검증 로그 |
| [Paper review](../../components/calibration/paper-review.md) | targetless LiDAR–camera calibration 논문 검토, 문헌·구현·실험 증거의 구분과 각주 기준 |
| [Analyzer 실험](../../components/calibration/analyzer-experiments.md) | T1/T2 analyzer의 구현·테스트 분리, 반복 실행·결정성·basin recall 로그 |
| [Calibration 실험 증적](../../components/calibration/experiment-evidence.md) | Core·Analyzer·Manual·Jenkins와 downstream 연계 증적의 실행 장부·산출물 보존 기준 |
| [Manual Calibration 기준](../../components/calibration/manual-reference.md) | ChArUco 출력물, intrinsic·pose·예비 RT와 세션별 검증 로그 |
| [Qt 공간 정합](../../components/qt/spatial-alignment.md) | Qt CCTV metadata·LiDAR 공간 정합, 2D/3D 시각화, 테스트·replay 검증 로그 |
| [RTSP 분석](../../components/qt/rtsp-analysis.md) | Wireshark 기반 RTSP/RTP/H.264 분석, motion burst·packet loss 측정 로그 |
| [Jenkins 재현성](../../guides/jenkins-calibration-reproducibility.md) | 현재 Jenkins capture·scan·pack과 후속 Calibration test의 실행·실패·hold-out 로그 |

## 작업 흐름

```text
Calibration Core 기반 구성
  -> 수동 기준(ChArUco)과 입력 계약 정리
  -> CH1/Jenkins 반복 실험 및 실패 원인 기록
  -> staged Core 기준선 고정
  -> T1/T2 analyzer 후보 실험
  -> hold-out·재현성·activation gate로 production 승격 여부 판정
  -> Qt/RTSP/OpenSDK downstream 경로에 필요한 변경만 반영
```

## 주요 이력

| 날짜 | 변경 | 개인 기여의 의미 |
|---|---|---|
| 2026-07-30 | `eaa4787` | 저장소 최초 README와 프로젝트 초기 문서 기준 구성 |
| 2026-07-30 | `c3461f7` | Calibration Core 초기 작업 기반과 synthetic/문서 구조 구성 |
| 2026-08-13 | `2c98554` | workspace·Ubuntu native flow, real calibration 실행기, Manual Calibration·Top View 경로 구성 |
| 2026-08-13 | `88758b6` | CH1 sample data와 재현 가능한 진단 경로 추가 |
| 2026-08-20 | `f92626e` | staged calibration 개선과 Core·실행기·테스트 보강 |
| 2026-08-20 | `c001d04` | OpenSDK 연계 경계와 handoff 문서화 |
| 2026-08-24 | `f684cd6` | Calibration analyzer 실험 기준선, Jenkins/Manual/검증 문서와 스크립트 고정 |
| 2026-08-24 | `7935fc9` | Qt CCTV–LiDAR 공간 정합 및 2D/3D 시각화 파이프라인 통합 |
| 2026-08-24 | `d94b862` | 다른 팀원이 작성한 OpenSDK calibration 앱의 구버전 auto_calib Core를 최신 Core 변경·왜곡 보정 경로에 맞춰 업데이트 |
| 2026-08-24~25 | T1 `79aeb0d`, T2 `afd277a` | 구조 방향·파노라마 analyzer 실험과 결과 schema 보강; production에는 미병합 |

## 문서·실험 산출물

개인 작업 폴더의 다음 자료는 Git 커밋 여부와 별도로 프로젝트 진행 과정의 산출물로 분류한다.

| 위치 | 산출물 성격 | 기록 방식 |
|---|---|---|
| `auto_calib/project_plan/` | 센서 인계, Calibration 상세 계획, 방향 논의, 멘토 피드백 대응 | 문제 정의·범위 조정·인계 기준을 요약 |
| `auto_calib/paper_review/` | LiDAR–Camera 자동 Calibration 논문 원문·한국어 리뷰 | 알고리즘 선택 근거와 한계만 요약 |
| `auto_calib/artifacts/` | 프로젝트 제안서, 템플릿 버전, 생성 스크립트, 아키텍처 이미지 | 문서 작성·템플릿 개선 산출물로 기록 |

생성된 바이너리·이미지·PLY·PCD 전체를 문서 저장소에 복사하지 않고, `components/calibration/experiment-evidence.md`와 analyzer 실험 문서에 목적별 핵심 지표와 재현 경로만 남긴다.

## 기여 범위 경계

- OpenSDK의 MobileSAM, LSD, TCP server 및 앱 구성·포트·패키징은 다른 팀원의 작업이며, 광진의 개인 기여로 기록하지 않는다.
- OpenSDK 쪽 `d94b862`는 다른 팀원이 작성한 calibration 앱 내부의 낮은 버전 auto_calib Core를 최신 Core 변경에 맞춰 업데이트한 작업이다. OpenSDK 앱 구조나 알고리즘을 새로 개발한 작업으로 기록하지 않는다.
- Manual Calibration의 LiDAR display-plane 기반 `T_camera_lidar`는 예비 추정값이며 ground truth나 제품 conformance 기준으로 기록하지 않는다.
- analyzer T1/T2는 후보 생성 실험이다. B0 basin recall 실패와 production 미병합 상태를 함께 기록한다.
- `wireshark_log`에서는 RTSP/RTP 분석 문서와 분석 스크립트만 개인 기여로 기록한다. 전체 Qt 애플리케이션 구현의 소유권은 별도로 주장하지 않는다.

## 기록 시 제외하는 자료

빌드 디렉터리, IDE·CRLF 변경, 공식 OpenSDK 참고 문서, 로그인 화면 등 민감 가능 자료, 실험 결과 전체 바이너리는 개인 기여 목록에 추가하지 않는다.
