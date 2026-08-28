# Calibration 분석 문서 분류

이 디렉터리는 자동 캘리브레이션의 설계 근거와 문헌·방법 분석을 분류한다. 분석 문서는
구현 결과나 테스트 PASS를 대신하지 않으며, 어떤 방법을 선택했는지와 어떤 전제가
필요한지를 설명한다.

## 포함 범위

| 분석 대상 | 문서에 포함해야 할 내용 | 현재 기준 |
|---|---|---|
| 논문 검토 | targetless LiDAR–camera calibration의 목적함수, 입력 조건, 장점·한계, 현재 Core와의 대응 | `paper-review.md`에 8개 문헌과 P1~P8 각주를 기록 |
| 구현 선택 | mutual information/NID, edge·plane·structural line, staged search, Ceres refinement를 왜 조합했는지 | `auto-core.md`에 실제 구현과 문헌 제안의 차이를 기록 |
| 적용 경계 | 문헌의 실험 조건과 우리 데이터의 차이, single observation·hold-out·product approval의 구분 | 각 분석 문서의 증거 수준과 제한사항에 기록 |

## 분석을 읽는 순서

1. 먼저 targetless 방법의 전제와 한계를 확인한다.
2. 그다음 현재 Core가 fixed K+D, 외부 파라미터 탐색, 구조 특징과 NID를 어떻게
   결합하는지 확인한다.
3. 마지막으로 실험·검증 문서에서 분석적 기대가 실제 수치로 검증되었는지 확인한다.

논문이 특정 방법을 제안했다는 사실은 우리 구현의 PASS나 제품 승인 증거가 아니다.
문헌 인용은 설계 배경으로, 실행 로그와 결과 JSON은 별도의 실험·검증 증적으로
기록한다.
