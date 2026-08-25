# Calibration 실험 문서 분류

이 디렉터리는 실제 입력·합성 입력·수동 출력물을 사용한 실험 기록을 둔다. 실험 결과는
알고리즘 구현이 존재한다는 증거와 구분하며, `PASS`라도 제품 외부 파라미터 승인으로
해석하지 않는다.

## 실험 종류

| 종류 | 목적 | 현재 상태 |
|---|---|---|
| Core 실험 | CH1 pair, Jenkins scene, staged search, hold-out과 fail-safe 동작 확인 | `auto-core.md`와 `experiment-evidence.md`에 실행 조건·수치·실패 원인을 기록 |
| Analyzer 구현 실험 | T1 Structural과 T2 Panorama의 후보 생성·schema·runner 확인 | 구현과 테스트를 분리했으며 production Core에는 미병합 |
| Manual Calibration | ChArUco board, intrinsic K+D, camera/marker와 LiDAR 기준 비교 | 독립 기준·진단 자료로만 사용 |
| 재현성 실험 | 같은 build·scene·train/hold-out 분할을 반복 실행 | Jenkins와 B0 기준선을 서로 다른 실행으로 기록 |

## 실험 판정 규칙

- 실행 성공, 결정성, baseline basin recall, hold-out 통과를 각각 기록한다.
- 입력 누락이나 mount 실패는 알고리즘 FAIL과 분리한다.
- single observation 결과는 `SINGLE_OBSERVATION_DIAGNOSTIC_ONLY`로 표시한다.
- 결과 JSON의 `CANDIDATE_RT/PASS`는 `NOT_PRODUCT_APPROVED_RT`와 함께 기록한다.
- 원본 PNG·PCD·PLY·CSV는 작업 공간에 보존하고, 문서에는 조건과 핵심 수치를
  재현 가능한 형태로 옮긴다.

상세 analyzer 구현·테스트 표는 `analyzer-experiments.md`, 세션별 수치 장부는
`calibration-experiment-log.md`와 `experiment-evidence.md`에 기록한다.
