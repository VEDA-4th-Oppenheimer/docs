# Calibration 실험 증적 목록

## 목적

이 문서는 세부 결과를 다시 계산하는 장부가 아니라, **어떤 주장에 어떤 커밋·문서·산출물이 근거가 되는지** 추적하는 증적 registry다. Core 검증, analyzer 실험, Manual 출력물, Jenkins 재현성, 개인 문서 산출물을 서로 다른 성격으로 구분한다.

기준일은 2026-08-25다. 대용량 결과 전체를 docs 저장소에 복사하지 않고, 원본 위치·핵심 파일·보존 이유만 기록한다.

## 증적 분류

| 분류 | 증명하려는 것 | 대표 근거 | 상태 |
|---|---|---|---|
| Core 구현 | 알고리즘·API·상태 수명주기 구현 | `f92626e`, `f684cd6`, `automatic_calibration/src/`, `include/` | committed |
| Core 검증 | gate·hold-out·fail-safe·재현성 | `automatic_calibration/docs/`, `generated/*calibration_result.json`, scene validation CSV | committed + local generated |
| Analyzer 구현 | T1/T2 runner·schema·후보 생성 코드 | `058ab97`~`afd277a`, analyzer branches | experiment branch |
| Analyzer 테스트 | unit·real input·결정성·baseline recall | T1/T2 result CSV/JSON, dual execution report | experiment evidence |
| Manual 출력 | ChArUco board와 K+D 입력 기준 | `output/pdf/*.pdf`, `*_config.json`, manual calibration docs | local output + committed docs |
| Jenkins 재현성 | capture·scan·pack과 후속 calibration test의 입력/실행 추적 | Jenkins docs, `jenkins_scene0_ch1_*`, manifest/scene CSV | committed + local generated |
| 문헌 근거 | targetless calibration 방법·전제·적용 범위의 조사 기록 | `components/calibration/paper-review.md`, `auto_calib/paper_review/` | committed summary + local originals |
| 문서 산출물 | 계획·논문 조사·제안서 작성 과정 | `project_plan/`, `paper_review/`, `artifacts/` | local non-Git workspace |
| Qt/RTSP 분석 | 공간 정합 구현과 RTSP/RTP 원인 분석 | QT `7935fc9`, `wireshark_log/docs/`, analysis scripts | committed/local analysis |
| OpenSDK Core 버전 업데이트 | 타 팀원이 작성한 calibration 앱에 포함된 낮은 버전 auto_calib Core를 최신 Core 변경·왜곡 보정 경로에 맞춰 동기화 | OpenSDK `d94b862` | committed version-sync patch |

## 핵심 증적 registry

| ID | 주장 | 최소 근거 | 기록 시 주의 |
|---|---|---|---|
| E-01 | fixed K+D와 staged Core를 구현했다 | `f92626e` (2026-08-20), `f684cd6` (2026-08-24) | K+RT 공동 추정은 제품 경로가 아님 |
| E-02 | Core가 실패 후보를 자동 활성화하지 않는다 | lifecycle fields, `PRODUCT_CALIBRATION_POLICY` / `f684cd6` (2026-08-24) | `CANDIDATE_RT/PASS`와 제품 승인을 분리 |
| E-03 | Jenkins dataset을 Core 입력으로 재현할 수 있다 | `JENKINS_SCENE0_CH1_REPRODUCIBILITY_20260821.md` (2026-08-21), manifest | build9/build10 camera 중복으로 limited hold-out임 |
| E-04 | T1/T2 runner가 실행되고 결과가 결정적이다 | analyzer unit/real tests, proposal hash / report (2026-08-25) | 실행 성공은 올바른 basin을 의미하지 않음 |
| E-05 | T1/T2가 현재 Core를 대체하지 못한다 | baseline-basin recall@3 각각 `0/1` / report (2026-08-25) | production branch에 merge하지 않음 |
| E-06 | Manual board 출력 조건을 고정했다 | board config/print spec/PDF / local output (2026-08-25) | fit-to-page 금지와 실측 필요 |
| E-07 | Qt 공간 정합 pipeline을 구현했다 | QT `7935fc9` (2026-08-24), spatial tests/replay tools | Core 알고리즘 자체와 구분 |
| E-08 | RTSP motion burst와 packet loss 원인을 분석했다 | pcap 분석 docs/scripts/results (2026-08-04 기준 자료) | IP, 계정, 로컬 절대 경로는 공개 문서에서 제거 |
| E-09 | OpenSDK용 앱을 새로 구현한 것이 아니라 기존 앱에 포함된 낮은 버전 auto_calib Core를 업데이트했다 | OpenSDK `d94b862` (2026-08-24) | MobileSAM·LSD·TCP server·앱 통합은 타 팀원 작업; 실제 CV5 E2E runtime PASS는 별도 증적 없음 |
| E-10 | 프로젝트 계획·논문 조사·제안서 산출물을 작성했다 | `project_plan/`, `paper_review/`, `artifacts/`, `components/calibration/paper-review.md` / 2026-08-25 | Git에 정리한 문헌 요약과 local 원문·리뷰 산출물을 구분 |

## 원본 위치 registry

| 대상 | 대표 원본 위치 | 핵심 확인 파일 | 보존 상태 |
|---|---|---|---|
| B0 Core | `auto_calib/develop/automatic_calibration/generated/jenkins_scene0_ch1_primary_build22_24/` | `calibration_result.json`, training/hold-out CSV, finalist CSV | local generated |
| Core 회귀 문서 | `auto_calib/develop/automatic_calibration/docs/` | Core architecture, product policy, final evaluation, Jenkins reproducibility 문서 | committed at `f684cd6` |
| T1 | `auto_calib/analyzer_experiments/t1_structural/automatic_calibration/generated/analyzer_eval/` | build22·23·24 `analyzer_result.json`, `orientation_proposals.csv` | experiment worktree/local generated |
| T2 | `auto_calib/analyzer_experiments/t2_panorama/automatic_calibration/generated/analyzer_eval/` | build22·23·24 result/proposal과 panorama debug PNG | experiment worktree/local generated |
| T1/T2 종합 | `auto_calib/analyzer_experiments/reports/DUAL_ANALYZER_EXECUTION_REPORT_20260825.md` | B0/T1/T2 실행·결정성·recall 비교 | local report |
| Manual 출력 | `auto_calib/develop/output/pdf/` | ChArUco PDF, board config, print spec | Git 미추적 local output |
| Jenkins | `auto_calib/develop/automatic_calibration/docs/JENKINS_*.md` | 현재 Freestyle Job, package 계약, build별 재현 기록 | committed at `f684cd6` |
| Qt 공간 정합 | `auto_calib/QT` | `7935fc9`, spatial/metadata tests, replay/probe tools | committed |
| RTSP 분석 | `wireshark_log/docs/`, `wireshark_log/scripts/` | 분석 결과 문서와 6개 packet 분석 스크립트 | local analysis |
| OpenSDK Core 업데이트 | `OpenSDK_repo` | `d94b862`의 Core source/header, 실행기, adapter, K+D profile 동기화 | committed |
| 개인 문서 | `auto_calib/project_plan/`, `paper_review/`, `artifacts/` | 계획서, 논문 리뷰, 제안서·생성 스크립트 | local non-Git |

## 실행 로그 장부

아래 표는 원본 보고서에서 확인한 실행 단위별 결과를 요약한 것이다. 같은 데이터라도 알고리즘 버전·pair 분할·hold-out 정책이 다르면 별도 로그로 남기며, 최신 결과가 과거 PASS를 소급해 지우지 않도록 한다.

| 날짜 | 로그 ID | 입력·조건 | 결과 | 핵심 수치·실패 원인 |
|---|---|---|---|---|
| 2026-08-14 | MANUAL-SESSION-001 | `session-const-env`, clean ChArUco 18장 | camera-side PASS / RT 예비 추정 | RMS `0.647 px`, marker pose RMSE `0.335255 px`, LiDAR plane 213 points, mean residual `0.009081525 m`, max `0.074652560 m`; `ESTIMATED_GEOMETRY_CORRECTED` |
| 2026-08-18 | MANUAL-CH1-PROBE | A4 board 단일 image + 고정환경 진단 scan | board PASS / auto `FAIL` | marker `16/17`, corners `22`, RMSE `1.2826 px`; auto yaw `160°`, down `20°`, NID improvement `3.07%`; `SINGLE_OBSERVATION_DIAGNOSTIC_ONLY` |
| 2026-08-18 | CORE-CH1-3PAIR | CH1 image–LiDAR 3 pair, train only | `PASS` | train `3/3`, yaw `170°`, refined down `19.9989°`, objective improvement `15.53%`, NID improvement `1.08%`, mean edge `19.92 px`, projected ratio `0.7794`, structural matches `71` |
| 2026-08-21 | JENKINS-SCENE0-3T1H | build5·8·9 training, build10 limited hold-out | `CANDIDATE_RT / PASS` | yaw `170°` circular equivalent, down `29°`, roll `-1°`, confidence `0.585022`, train `3/3`, hold-out `1/1`, mean edge `18.506 px`; build9/build10 CH1 image duplicate |
| 2026-08-21 | JENKINS-SCENE0-SINGLE | build5·8·9 단독 실행 | 내부 PASS지만 반복성 실패 | pair0 yaw `-128°`, pair1·2 yaw `-190°`; pair0↔pair2 rotation 차이 `68.564°`, translation 차이 `65.001 mm`; 단일 장면 false positive 증거 |
| 2026-08-24 | JENKINS-CASE-A | build5·8·9 training, build10 hold-out | exit `3`, `FAIL / FINALIST_AMBIGUOUS` | train `3/3`, hold-out `1/1`, margin `1.8209%` < `2%`; fail-closed 정상 동작 |
| 2026-08-24 | JENKINS-CASE-B | build17·18·19 training, build20·21 hold-out | `CANDIDATE_RT / PASS` | train `3/3`, hold-out `2/2`, objective `0.7637627`, margin `6.4912%`; stress 조건 결과라 제품 정답 아님 |
| 2026-08-24 | JENKINS-CASE-C | build22·23 training, build24 hold-out | `CANDIDATE_RT / PASS` | train `2/2`, hold-out `1/1`, objective `0.8006294`, margin `2.9436%`; 제품 상태는 `NOT_PRODUCT_APPROVED_RT` |
| 2026-08-24 | JENKINS-FIXED-CROSS | Case C RT를 Case A/B에 재추정 없이 적용 | 내부 gate PASS | Case A 4/4 scene, Case B 5/5 scene; fixed validation은 RT 정답 검증이 아님 |
| 2026-08-24 | FINALIST-HOLDOUT | finalist별 동일 hold-out 비교 | 중간 expected rejection 포함 | 기본 회귀 `9/9 PASS`, 전체 `9/11`은 데이터·expected rejection 포함; `FINALIST_HOLDOUT_AMBIGUOUS`는 후보를 억지로 승격하지 않도록 차단 |
| 2026-08-25 | ANALYZER-B0 | B0 Case C, 11 CTest cases | `9 PASS / 2 FAIL` | 2 FAIL은 데이터 경로 미mount; Case C `CANDIDATE_RT/PASS`, hold-out objective `0.8006294005` |
| 2026-08-25 | ANALYZER-T1 | structural analyzer, build22 5회 | 실행·결정성 PASS / basin FAIL | wall `2666,2711,2924,3009,3087 ms`, median `2924 ms`, internal `0.68 s`, recall@3 `0/1`, proposal `2.71563°,-27.2882°,-73.3458°` |
| 2026-08-25 | ANALYZER-T2 | panorama analyzer, build22 5회 | 실행·결정성 PASS / basin FAIL | coverage `0.994752`, wall median `4526 ms`, proposal `-15.3°,-16.2°,-14.4°`, Top-K distinct basin 실패, recall@3 `0/1` |

## 실패·거절 로그 분류

| 상태/코드 | 발생 맥락 | 보고서에서의 의미 |
|---|---|---|
| `SINGLE_OBSERVATION_DIAGNOSTIC_ONLY` | CH1 단일 pair 자동 실행 | 입력 부족으로 운영 RT를 만들지 않음 |
| `COARSE_OVERLAP_INSUFFICIENT` | 2026-08-19 remediation | 절대 support가 부족한 후보를 Ceres 이전에 제거 |
| `FINALIST_AMBIGUOUS` | Case A, 일부 finalist hold-out 실행 | 후보 간 margin/support가 부족해 fail-closed |
| `FINALIST_HOLDOUT_AMBIGUOUS` | separated finalist가 같은 hold-out을 통과 | 후보를 하나로 확정할 식별성 부족 |
| 데이터 path 미mount | 2026-08-25 B0 11-case 실행 | 알고리즘 실패가 아닌 실행 환경 실패. PASS로 합산하지 않음 |
| ChArUco expected fail | build17 monitor, build18 chair | corner 최소치 미달. threshold를 낮춰 통과시키지 않음 |
| `activation_allowed=false` | 모든 automatic·Manual 연계 결과 | 내부 PASS와 제품 RT 승인을 분리하는 정상 보호 상태 |

## 로그 원본과 공개 기록의 관계

원본 실행 로그와 생성물은 다음 작업 공간에 보존한다.

```text
auto_calib/develop/automatic_calibration/docs/
auto_calib/develop/automatic_calibration/generated/
auto_calib/develop/manual_calibration/output/
auto_calib/analyzer_experiments/reports/
auto_calib/analyzer_experiments/t1_structural/automatic_calibration/generated/
auto_calib/analyzer_experiments/t2_panorama/automatic_calibration/generated/
wireshark_log/docs/
wireshark_log/scripts/
```

docs 저장소에는 원본 PCAP, PCD, PLY, PNG 전체를 복제하지 않고 실행 조건·상태·reason·runtime·hash·핵심 metric과 보존 위치만 기록한다. 원본 보고서에 포함된 파일 URI·IP·계정 정보는 공개 문서에 재기록하지 않는다.

## 증적 보존 규칙

1. 커밋 hash와 날짜를 먼저 기록한다.
2. 입력 데이터의 channel, build, train/hold-out 역할을 기록한다.
3. 결과 JSON/CSV는 상태·reason·runtime·hash·핵심 metric만 추출한다.
4. PNG, PLY, PCD, PCAP 원본은 작업 공간에 보존하고 공개 docs에는 전체를 복사하지 않는다.
5. 수집 실패, 테스트 실패, 제품 승인 실패를 서로 다른 상태로 기록한다.
6. IP, 사용자명, 비밀번호, token, 로컬 절대 경로는 제거·일반화한다.

## 현재 보존 결론

현재 문서의 역할은 결과를 과장하지 않고 재현 가능한 근거를 찾게 하는 것이다. 특히 Core는 제품 후보 경로, analyzer는 테스트·구현 중인 실험 경로, Manual은 독립 기준·진단 경로, Jenkins는 데이터 수집·실행 자동화 경로로 분리한다.
