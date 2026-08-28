# 자동 캘리브레이션

포인트클라우드와 CCTV 2D 영상을 매칭해 카메라 외부 파라미터를 구하는 파트다.
알고리즘 설계, 논문 조사, 샘플 코드 분석 문서를 여기에 둔다.

## 문서 분류

기존의 상세 문서는 파일 트리를 유지하고, 아래 디렉터리를 문서 성격별 분류·검증
입구로 추가한다.

| 분류 | 포함 내용 |
|---|---|
| `analysis/` | 논문 검토, 문헌의 방법과 현재 Core 설계의 대응, 적용 전제와 한계 |
| `experiments/` | Core·Manual·Jenkins·Analyzer 실행 이력, 입력 조건, 수치, 실패 원인 |
| `verification/` | Core suite, hold-out gate, analyzer 결정성·recall, PASS의 증거 수준 |

분류 문서는 다른 문서로 책임을 넘기는 경로 안내가 아니라, 각 분류의 목적·판정
규칙·핵심 수치를 직접 포함하는 요약이다. 기존 상세 문서와 수치가 다르면 commit,
입력 데이터와 실행 날짜가 더 구체적으로 기록된 항목을 우선한다.

| 문서 | 내용 | 담당 |
|---|---|---|
| [cv5-optimization.md](cv5-optimization.md) | staged coarse-to-fine 탐색, 렌즈 왜곡 보정, ARM/NEON 최적화와 결과 검증 경계 | 이영민 |
| [auto-core.md](auto-core.md) | Automatic Calibration Core의 입력 계약, 특징·목적함수·staged 탐색·상태 수명주기와 커밋 이력 | 광진 |
| [paper-review.md](paper-review.md) | targetless LiDAR–camera calibration 논문 검토, 문헌·구현·실험 증거의 구분과 각주 기준 | 광진 |
| [analyzer-experiments.md](analyzer-experiments.md) | T1/T2 analyzer의 구현 현황과 테스트 현황을 분리한 실험 기록 | 광진 |
| [experiment-evidence.md](experiment-evidence.md) | Core·analyzer·Manual·Jenkins와 downstream 연계 증적의 출처·판정·보존 기준 | 광진 |
| [manual-reference.md](manual-reference.md) | ChArUco board 출력물, Manual intrinsic·왜곡 보정 기준과 예비 RT 사용 경계 | 광진 |
| `experiments/calibration-experiment-log.md` | Core·Manual·Jenkins·Analyzer를 날짜·입력·결과·실패 원인으로 분리한 실험 이력 | 광진 |
| `verification/core-verification.md` | Core 9-suite, 실데이터 gate, hold-out과 제품 승인 경계 | 광진 |
| `verification/analyzer-verification.md` | B0·T1·T2 실행·결정성·baseline basin recall 판정 | 광진 |
