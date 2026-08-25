# Calibration 실험 이력 로그

기준일은 2026-08-25다. 이 문서는 Core·Manual·Jenkins·Analyzer 실험을 시간순으로
분리해 기록한다. 서로 다른 커밋·데이터 분할·hold-out 정책의 결과를 하나의 누적
성공률로 합산하지 않는다.

## Manual Calibration

| 날짜 | 입력 | 결과 | 핵심 수치 | 해석 |
|---|---|---|---|---|
| 2026-08-14 | clean ChArUco 18장, `session-const-env` | camera-side PASS / RT 예비 추정 | RMS `0.647 px`, marker pose RMSE `0.335255 px`, LiDAR plane 213 points, mean residual `0.009081525 m`, max `0.074652560 m` | K+D와 예비 geometry 기준; 제품 ground truth 아님 |
| 2026-08-18 | A4 board 단일 image + 진단 scan | board PASS / automatic calibration 제한 | marker `16/17`, corners `22`, RMSE `1.2826 px`, auto yaw `160°`, down `20°`, NID improvement `3.07%` | `SINGLE_OBSERVATION_DIAGNOSTIC_ONLY` |

## Automatic Calibration Core

| 날짜 | 로그 ID | 입력·분할 | 결과 | 핵심 수치 |
|---|---|---|---|---|
| 2026-08-18 | CORE-CH1-3PAIR | CH1 image–LiDAR 3 pair, train only | `PASS` | yaw `170°`, refined down `19.9989°`, objective improvement `15.53%`, NID improvement `1.08%`, mean edge `19.92 px`, projected ratio `0.7794`, structural matches `71` |
| 2026-08-19 | CORE-REMEDIATION | sparse candidate support | `FAIL / COARSE_OVERLAP_INSUFFICIENT` | Ceres 이전에 절대 support 부족 후보를 제거 |
| 2026-08-21 | JENKINS-SCENE0-SINGLE | build5·8·9 개별 실행 | 내부 PASS지만 반복성 실패 | pair별 yaw `-128°`, `-190°`, rotation 차이 `68.564°`, translation 차이 `65.001 mm` |
| 2026-08-21 | JENKINS-SCENE0-3T1H | build5·8·9 train, build10 hold-out | `CANDIDATE_RT / PASS` | yaw `170°` circular equivalent, down `29°`, roll `-1°`, confidence `0.585022`, train `3/3`, hold-out `1/1` |
| 2026-08-24 | JENKINS-CASE-A | build5·8·9 train, build10 hold-out | exit `3`, `FAIL / FINALIST_AMBIGUOUS` | margin `1.8209%` < required `2%`; fail-closed 정상 동작 |
| 2026-08-24 | JENKINS-CASE-B | build17·18·19 train, build20·21 hold-out | `CANDIDATE_RT / PASS` | train `3/3`, hold-out `2/2`, objective `0.7637627`, margin `6.4912%` |
| 2026-08-24 | JENKINS-CASE-C | build22·23 train, build24 hold-out | `CANDIDATE_RT / PASS` | train `2/2`, hold-out `1/1`, objective `0.8006294`, product state `NOT_PRODUCT_APPROVED_RT` |
| 2026-08-24 | JENKINS-FIXED-CROSS | Case C RT 고정 후 Case A/B 재추정 없이 적용 | 내부 gate PASS | Case A `4/4`, Case B `5/5`; RT 정답 검증은 아님 |

## Analyzer 실험

| 날짜 | 대상 | 실행 | 결과 | 핵심 수치 |
|---|---|---|---|---|
| 2026-08-25 | B0 Core | 11 CTest cases | `9 PASS / 2 FAIL` | 2 FAIL은 데이터 path 미mount; Case C hold-out objective `0.8006294005` |
| 2026-08-25 | T1 Structural | build22 5회 | 실행·결정성 PASS / basin FAIL | wall `2666,2711,2924,3009,3087 ms`, median `2924 ms`, recall@3 `0/1`, proposal `2.71563°,-27.2882°,-73.3458°` |
| 2026-08-25 | T2 Panorama | build22 5회 | 실행·결정성 PASS / basin FAIL | coverage `0.994752`, wall median `4526 ms`, recall@3 `0/1`, Top-K distinct basin 실패 |

T1/T2의 실행 가능성과 결정성은 확인했지만 baseline basin recall을 만족하지 못했으므로
현재 production calibration Core를 대체하지 않는다. Analyzer는 구현 중·테스트 중인
후보 경로로 기록한다.

## 산출물과 보존

각 실행은 commit/build, 입력 channel, train/hold-out 역할, status, reason, runtime,
핵심 metric과 결과 JSON/CSV 식별자를 함께 보존한다. 원본 이미지·점군·pcap을 문서
저장소에 복제하지 않고 작업 공간에 보존하며, 민감한 IP·계정·token·절대 경로는 공개
문서에 넣지 않는다.
