# Analyzer 검증 기록

T1 Structural과 T2 Panorama는 현재 automatic calibration Core를 대체하지 않는
후보 analyzer다. 2026-08-25 실행은 구현·테스트 실행 여부·결정성·baseline basin
recall을 분리해 판정했다.

| 대상 | 실행 조건 | 실행·결정성 | baseline basin recall | 최종 판정 |
|---|---|---|---:|---|
| B0 Core | Case C, 11 CTest cases | `9 PASS / 2 FAIL`; 2 FAIL은 데이터 path 미mount | 해당 없음 | 기존 Core 기준선 |
| T1 Structural | build22 5회 | PASS; wall median `2924 ms`, internal `0.68 s` | `0/1` | production 미승격 |
| T2 Panorama | build22 5회 | PASS; coverage `0.994752`, wall median `4526 ms` | `0/1` | production 미승격 |

T1 대표 proposal은 `2.71563°,-27.2882°,-73.3458°`, T2 대표 proposal은
`-15.3°,-16.2°,-14.4°`이며 baseline 후보 basin과 일치하지 않았다. 따라서 runner가
정상 종료하고 결과 schema가 유효하다는 사실만으로 calibration 정확도를 주장하지
않는다.

## 재현성 판정

각 analyzer는 같은 build와 입력을 5회 실행해 proposal·result schema·hash를 비교했다.
실행 시간 변동이 있어도 proposal이 동일하게 생성되는 결정성은 별도로 기록하며,
recall 실패는 결정성 PASS로 상쇄하지 않는다. 입력 path가 mount되지 않은 2건은 환경
실패로 분류하고 알고리즘 실패율에 섞지 않는다.
