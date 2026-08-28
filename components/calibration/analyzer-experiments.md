# Calibration Analyzer 실험 — 구현 및 테스트 현황

## 문서 목적

이 문서는 기존 Calibration Core(B0)를 대체하기 전 단계의 T1 Structural Analyzer와 T2 Panorama Analyzer를 기록한다. **구현 현황**과 **테스트 현황**을 분리해, 코드가 존재하는 것과 검증을 통과한 것을 혼동하지 않는다.

기준일은 2026-08-25이며, T1/T2 branch는 `auto_calib/develop`에 merge하지 않았다.

## 논문 근거와 실험 범위

T1/T2의 후보 신호는 자연 edge·구조선과 cross-modal 정합을 검토하기 위한 연구 실험이다. 자연 edge의 추출과 장면 내 공간 분포를 calibration 관측성의 조건으로 보는 선행 연구[^P7]와, 2D–3D correspondence/RANSAC 후 NID refinement로 초기 오차를 줄이는 방법[^P3]을 비교 기준으로 참고했다.

다만 현재 T1/T2 구현은 LSD 방향 cluster, LiDAR normal, panorama raster score를 생성하는 단계다. 논문에 포함된 완전한 perspective projection, 2D–3D correspondence, RANSAC, Ceres/NID refinement를 구현하거나 재현한 것이 아니다. 아래 runtime·proposal hash·basin recall은 우리 worktree와 CH1 입력의 실험 증거이며 논문 성능 수치가 아니다.

## 1. 구현 현황

### B0 기준선

B0는 `f684cd6`의 staged Core다. coarse score map, separated basin, 5°/1° local search, Ceres refinement, training/hold-out gate를 포함한다.

### T1 Structural Analyzer

| 항목 | 현재 구현 |
|---|---|
| branch/commit | `codex/exp-structural-analyzer-20260824` / `79aeb0d` |
| 입력 | synthetic 및 CH1 JSON/real input |
| 후보 신호 | OpenCV LSD 방향 cluster + LiDAR normal 조합 |
| 출력 | orientation proposal CSV/JSON |
| 구현 이력 | `058ab97` 최초 analyzer, `2986691` standalone JSON runner, `79aeb0d` invalid scan cell 처리 |
| 미구현 | projective vanishing point, 완전한 2D–3D correspondence, Ceres/NID refinement, production fallback 연결 |

T1은 후보 방향을 제안하는 라이브러리이며 `PROPOSALS_READY`가 올바른 RT basin 또는 제품 승인 결과를 의미하지 않는다.

### T2 Panorama Analyzer

| 항목 | 현재 구현 |
|---|---|
| branch/commit | `codex/exp-panorama-analyzer-20260824` / `afd277a` |
| 입력 | organized JSON raster 및 synthetic seam/raster case |
| 후보 신호 | panorama orientation score와 seam-safe circular 처리 |
| 출력 | orientation proposal result schema |
| 보강 commit | `53bfcba` real-input runner, `b0d9cb0` panorama experiment, `afd277a` result schema |
| 미구현 | perspective geometry, 실제 2D–3D correspondence, Ceres/NID refinement, production 연결 |

T2의 high coverage는 후보 생성 입력이 유효하다는 뜻일 뿐, 방향 basin 검증이 끝났다는 뜻이 아니다.

## 2. 테스트 현황

### 비교 조건

```text
B0 staged Core
  -> T1 Structural proposal
  -> T2 Panorama proposal
  -> 같은 CH1/Jenkins scene0와 build22·23 training / build24 hold-out 비교
```

| ID | 대상 | 테스트 | 결과 | 판정 |
|---|---|---|---|---|
| T-00 | B0 | CTest 11 cases, Case C | 9 PASS, 2 FAIL은 데이터 경로 미마운트. `CANDIDATE_RT/PASS`, hold-out objective `0.8006294005` | 비교 기준 |
| T-01 | T1 | unit + build22·23·24 real input + Case A/B | unit PASS, proposal CSV 5회 hash 동일, wall-time median `2924 ms` | 실행·결정성 확인 |
| T-02 | T2 | unit + build22·23·24 real input + Case A/B | unit PASS, build22 coverage `0.994752`, proposal CSV 결정성 확인, wall-time median `4526 ms` | 실행·결정성 확인 |
| T-03 | T1 | B0 baseline-basin recall@3 | `0/1` | 필수 조건 실패 |
| T-04 | T2 | B0 baseline-basin recall@3 | `0/1` | 필수 조건 실패 |

실행 근거는 `auto_calib/analyzer_experiments/reports/DUAL_ANALYZER_EXECUTION_REPORT_20260825.md`에 모아 두었다. 원본 proposal은 각 worktree의 `automatic_calibration/generated/analyzer_eval/` 아래 `analyzer_result.json`과 `orientation_proposals.csv`로 보존하며, docs 저장소에는 전체 생성물을 복사하지 않는다.

### 실행 환경 로그

| 항목 | 값 |
|---|---|
| 실행일 | 2026-08-25 KST |
| B0 기준 | `f684cd66c036b85d6a97e35d8706288c3b089355` |
| T1 기준 | `79aeb0d8eacc2dbdd4da884cf590621ee6e38485` |
| T2 기준 | `afd277ad00669e7733046b587be5d381c55737ae` |
| 입력 | CH1 Jenkins `scene0`, build5~24, synthetic cases |
| 실행 자원 | `auto-calib-dev:ubuntu-latest`, 2 CPU |
| 입력 보존 | 원본 image/JSON/PCD와 고정 K+D를 read-only mount |
| production branch | T1/T2 merge하지 않음 |

### B0 기준선 실행 로그

| 로그 항목 | 결과 |
|---|---|
| CTest | 전체 11 cases 중 `9 PASS`, `2 FAIL` |
| B0 실패 2건 | 데이터 경로가 컨테이너에 mount되지 않은 실행 환경 문제 |
| Case C | build22·23 training, build24 hold-out |
| Case C 상태 | `CANDIDATE_RT / PASS` |
| 선택 basin | seed `-183°`, circular 기준 약 `177°` |
| down / optical roll | `42°` / `3°` |
| training | `2/2 PASS` |
| hold-out objective | `0.8006294005` |
| separated hold-out competitor | `1` |
| 제품 상태 | `NOT_PRODUCT_APPROVED_RT`, `activation_allowed=false` |
| B0 wall-time | `/mnt/c` bind mount 기준 약 `34분` |

B0의 34분 실행은 analyzer가 줄여야 할 비용의 기준선이다. 이 수치는 전체 pipeline wall-time이며 Ceres와 1° local stage 후보 평가가 대부분을 차지했다.

### T1 원시 반복 실행 로그

`structural_orientation_analyzer_tests`는 PASS했다. 실제 JSON의 null cell 처리를 보강한 뒤 build22를 5회 같은 입력으로 실행했다.

```text
wall-time samples: 2666, 2711, 2924, 3009, 3087 ms
median:             2924 ms
internal runtime:   approximately 0.68 s
proposal CSV hash:  5회 동일
build22 proposals:  2.71563°, -27.2882°, -73.3458°
```

build23·24와 Case A/B rank-1 proposal도 대부분 `-5°~+5°` 부근이었다. B0 기준 basin 약 `177°`와 모두 10° window 밖이었고, down/roll은 항상 `0°` seed에 머물렀다. 따라서 T1은 실행·결정성은 통과했지만 B0 basin recall은 `0/1`이다.

T1의 `fallback_required=false`는 후보가 생성됐다는 뜻일 뿐이다. B0 basin이나 절대 기하 gate를 포함하지 않은 proposal을 그대로 연결하면 잘못된 방향을 확정할 수 있으므로 production 연결 전 fallback gate가 필요하다.

### T2 원시 반복 실행 로그

`panorama_orientation_analyzer_tests`는 PASS했다. build22 coverage와 5회 반복 wall-time은 다음과 같다.

```text
coverage:            0.994752
wall-time samples:   4538, 4310, 7187, 4291, 4526 ms
median:              4526 ms
proposal CSV hash:   5회 동일
build22 proposals:   -15.3°, -16.2°, -14.4°
```

build22·23·24의 세 proposal은 서로 다른 basin이 아니라 1° 이내로 붙은 하나의 인접 basin이었다. Case A/B도 대부분 `-4°~-17°`였고 build17만 `-131.4°`였다. invalid raster와 low coverage fallback unit test는 PASS했지만, high coverage만으로 `PROPOSALS_READY`가 되므로 방향 검증 없이 연결할 수 없다. T2의 B0 baseline-basin recall은 `0/1`이다.

### 테스트 실행과 구현 상태의 분리 로그

| 확인 항목 | T1 | T2 | 해석 |
|---|---|---|---|
| library/runner 존재 | PASS | PASS | 구현됨 |
| unit test | PASS | PASS | 기본 입력 처리 확인 |
| real input execution | PASS | PASS | build22·23·24와 Case A/B 실행 |
| 동일 입력 결정성 | PASS | PASS | proposal CSV hash 동일 |
| B0 basin recall@3 | `0/1` | `0/1` | 필수 조건 실패 |
| down/roll | `0°` seed | `0°` seed | 추정 미완료 |
| perspective geometry | 미구현 | 미구현 | 실제 2D–3D 정합 없음 |
| Ceres/NID refinement | 미연결 | 미연결 | B0 대체 불가 |
| production merge | 하지 않음 | 하지 않음 | 실험 branch 유지 |
| activation | `false` | `false` | 안전 상태 |

두 analyzer는 unit test와 결정성은 통과했지만 올바른 기하 basin을 찾았다는 증거는 없다. 현재 보고서에서 wall-time 절감, Ceres 호출 감소, 제품 정확도 개선을 주장하지 않는다.

### T1 테스트 해석

- build22 proposal은 동일 입력 5회에서 CSV hash가 동일했다.
- proposal은 대체로 `-5°~+5°` 부근이며 B0 basin 약 `177°`와의 circular distance가 10° window 밖이다.
- down/roll proposal은 `0°` seed에 머문다.
- 따라서 unit·결정성은 통과했지만 B0 기준 basin을 재현하지 못했다.

### T2 테스트 해석

- build22 coverage는 `0.994752`로 높았고 invalid raster/low coverage fallback도 테스트했다.
- proposal `-15.3°`, `-16.2°`, `-14.4°`는 서로 다른 후보가 아니라 하나의 인접 basin으로 볼 가능성이 높다.
- down/roll proposal은 `0°` seed에 머문다.
- 따라서 coverage·결정성은 통과했지만 B0 basin과의 일치 및 실제 기하 정합은 확인되지 않았다.

## 3. 구현과 테스트의 분리 판정

| 구분 | 현재 상태 |
|---|---|
| 코드/runner 존재 | T1/T2 모두 확인 |
| unit test | T1/T2 PASS |
| 동일 입력 결정성 | T1/T2 확인 |
| B0 baseline basin recall | T1/T2 모두 `0/1` |
| down/roll 추정 | 미완료 |
| Core projection/Ceres/NID 연결 | 미완료 |
| production merge | 하지 않음 |
| activation | 항상 `false` |

## 4. 다음 구현·테스트 순서

1. Top-K를 인접 점수 순서가 아니라 circular non-maximum suppression으로 분리한다.
2. B0 basin 또는 절대 기하 gate를 만족하지 못하면 `fallback_required=true`로 설정한다.
3. LiDAR azimuth/range signature와 camera line 방향·finite projection을 연결한다.
4. down/roll을 Manhattan normal과 perspective reprojection으로 생성한다.
5. 보강 후 동일 Case C에서 projection 호출 수, fallback, hold-out, wall-time을 B0와 비교한다.

현재 결론은 T1/T2를 Core 대체 구현이 아닌 후보 생성 실험으로 유지하는 것이다.

## 논문 근거 각주

[^P3]: K. Koide et al., “General, Single-shot, Target-less, and Automatic LiDAR-Camera Extrinsic Calibration Toolbox,” *IEEE ICRA*, 2023. [arXiv 원문](https://arxiv.org/abs/2302.05094)
[^P7]: C. Yuan et al., “Pixel-level Extrinsic Self Calibration of High Resolution LiDAR and Camera in Targetless Environments,” arXiv:2103.01627, 2021. [arXiv 원문](https://arxiv.org/abs/2103.01627)
