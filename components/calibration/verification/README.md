# Calibration 검증 문서 분류

이 디렉터리는 구현이 존재하는지보다, 특정 입력과 특정 커밋에서 어떤 검증이 실제로
실행되었고 무엇을 보장하지 않는지를 기록한다.

## 검증 층위

| 층위 | 기록 내용 | 해석 |
|---|---|---|
| Core unit/regression | geometry, projection, NID, plane, ambiguity, lifecycle assertion | 코드·fixture 회귀 |
| Real-input/hold-out | Jenkins scene의 train/hold-out, result gate와 reason | 후보 생성·fail-safe 검증 |
| Analyzer | runner 실행, schema, 결정성, baseline basin recall | 실험 구현 검증; production 승격 아님 |
| Manual | board print 조건, K+D RMS, pose·plane residual | 독립 입력 기준·진단 자료 |
| Product approval | ground truth, 독립 장면, 운영 적용 gate | 현재 자동 결과의 PASS와 별도 단계 |

## 확인된 실행 집계

- 2026-08-21 역사적 R4: 9 suites, `9/9 PASS`, `78.08 s`. 이후 코드 변경 전의
  별도 실행이므로 최신 B0와 합산하지 않는다.
- 2026-08-25 B0: 11 cases, `9 PASS / 2 FAIL`. 두 FAIL은 데이터 경로 미mount인
  환경 실패이며 알고리즘 PASS로 합산하지 않는다.
- Case A는 `FINALIST_AMBIGUOUS`로 거절되었고, Case B/C는 내부 후보 PASS지만
  제품 RT 승인 상태가 아니다.

`CANDIDATE_RT/PASS`, `INTERNAL_GATE_PASS`, camera-side PASS는 각각 다른 검증
층위이며 모두 `activation_allowed=false` 보호 정책과 함께 읽어야 한다.
