# Automatic Calibration Core 검증 기록

기준 commit은 `auto_calib/develop`의 `f92626e`와 `f684cd6` 계열이며, 실행 결과는
커밋·데이터셋·분할별로 구분한다. 이 문서는 OpenSDK의 Core version-sync 자체가
CV5에서 실행 PASS였다는 증거가 아니라, 원본 automatic calibration Core의 검증
기록이다.

## 역사적 9-suite 실행

2026-08-21 R4 기록은 총 `78.08 s`, `9/9 PASS`, `0 FAIL`이다.

| suite | 시간 | 검증 |
|---|---:|---|
| `automatic_synthetic_lidar_tests` | `0.10 s` | 6-DoF transform round-trip, `K^-1` ray consistency |
| `automatic_calibration_core_tests` | `5.47 s` | plane segmentation, plane intersection, NMI, M1/M2/M3 core |
| `challenger_m1_2_stress_tests` | `43.52 s` | TESL monotonicity, absolute support 16-case, 1,000회 재현성 |
| `challenger_m2_1_ambiguity_tests` | `<0.01 s` | confidence margin, support ratio, circular wrap |
| `challenger_m2_2_stress_tests` | `28.34 s` | normal gate, greedy collision, 108 random poses |
| `challenger_m3_stress_tests` | `0.13 s` | NID 1%, `K^-T`, intrinsic fuzzing 100,000회 |
| `manual_marker_tests` | `0.20 s` | ChArUco pattern과 transform composition |
| `top_view_tests` | `0.02 s` | Top-View projection과 metadata serialization |
| `top_view_gui_smoke` | `0.29 s` | offscreen GUI argument parsing과 smoke run |

## 실데이터 gate 결과

| 조건 | 결과 | 의미 |
|---|---|---|
| 2026-08-18 Challenger | `CANDIDATE_RT / PASS` | visible edge `861`, NID point `2714`, mean edge `23.50 px`, confidence `0.7916` |
| 2026-08-19 remediation | `COARSE_OVERLAP_INSUFFICIENT` | sparse candidate를 fail-closed |
| 2026-08-19 legacy | false positive 사례 | mean edge `8.42 px`인데 bracket error `93.837 mm`; 낮은 residual만으로 통과시키지 않음 |
| Jenkins scene0 결합 | `CANDIDATE_RT / PASS` | visible edge `1674`, NID point `1797`, mean edge `18.51 px`, bracket error `0.004 mm` |

브래킷 불변식은 `t=-R·C_lidar`로 확인했지만, 독립 ground truth가 없으면 제품 외부
파라미터의 정답을 증명하지 않는다. 모든 결과는 후보·진단 자료와 자동 활성화 금지
정책을 함께 기록한다.
