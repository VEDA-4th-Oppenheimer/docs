# LiDAR–Camera 자동 Calibration 논문 검토 및 적용 정의

## 문서 기준

| 항목 | 기준 |
|---|---|
| 목적 | `auto_calib/develop`에서 조사한 targetless LiDAR–camera calibration 논문을 보고서용 근거로 정리 |
| 기준일 | 2026-08-25 |
| 적용 대상 | Camera `K+D` profile과 organized pan-tilt LiDAR로 `T_camera_lidar`를 추정하는 Automatic Calibration Core |
| 문서 성격 | 문헌 조사·방법 비교 문서. 논문 결과를 우리 실험 결과로 대체하거나 재현 완료로 주장하지 않음 |
| 원본 조사 범위 | `auto_calib/develop/automatic_calibration/docs/TARGETLESS_CALIBRATION_METHOD_REVIEW.md`, `BRIGHT_LIGHT_FALSE_PASS_ANALYSIS.md`, `paper_review/` |

## 1. Paper review와 참고 논문의 정의

### Paper review란 무엇인가

이 프로젝트에서 **paper review(논문 검토)**는 논문을 읽고 다음 네 가지를 분리해 기록하는 작업이다.

1. 논문이 해결하려는 calibration 문제와 센서·데이터 전제
2. 핵심 알고리즘, 목적함수, 초기화와 품질 평가 방법
3. 논문이 제시한 실험 범위와 한계
4. 현재 프로젝트에서 채택할 부분, 보류할 부분, 직접 검증해야 할 부분

따라서 paper review는 논문의 내용을 번역하거나 논문 방법을 그대로 구현했다는 선언이 아니다. 보고서에서는 `문헌 근거`, `우리 구현`, `우리 실험 증거`를 서로 다른 문장과 표로 유지한다.

### 참고 논문(reference paper)이란 무엇인가

**참고 논문**은 우리 알고리즘의 설계 선택이나 비교 기준을 설명할 때 인용하는 외부 연구다. 참고 논문이 있다는 사실만으로 다음을 의미하지 않는다.

- 논문의 데이터셋·센서·수치 결과를 우리 장비에 재현했다는 뜻이 아니다.
- 논문에서 사용한 알고리즘을 현재 Core가 모두 구현했다는 뜻이 아니다.
- 논문이 보고한 정확도나 처리 시간을 우리 제품의 성능으로 가져올 수 있다는 뜻이 아니다.
- 우리 실험의 `PASS`, `CANDIDATE_RT`, `PRODUCT_APPROVED_RT`를 논문 인용만으로 판정할 수 있다는 뜻이 아니다.

### 보고서 인용 규칙

| 표기 | 의미 |
|---|---|
| `문헌 근거` | 논문 원문에서 확인되는 방법·전제·실험 관찰 |
| `프로젝트 해석` | 우리 센서와 목표에 맞춘 적용 가능성·위험 분석 |
| `구현 상태` | `auto_calib/develop` 코드와 커밋으로 확인한 현재 상태 |
| `실험 증거` | 우리 데이터·로그·metric·실패 코드로 확인한 결과 |
| `보류` | 연구적으로 의미가 있지만 현재 제품 경로에는 연결하지 않은 항목 |

문서 본문에는 필요한 주장 직후 `[^P1]` 형태의 각주를 붙인다. 각주가 있는 문장은 문헌의 사실을 설명하고, 같은 문단의 우리 수치와 상태는 별도의 실험 로그로 해석한다.

## 2. 프로젝트 문제와 논문 분류

현재 프로젝트의 제품 대상은 고정된 camera `K+D` profile을 사용해 자연 장면에서 LiDAR–camera **extrinsic `R,t`**를 추정하는 것이다. 따라서 문헌을 다음 네 갈래로 나눠 읽는다.

| 분류 | 질문 | 현재 프로젝트 관계 |
|---|---|---|
| 직접 정합 | 카메라와 LiDAR를 어떤 공통 표현·통계량으로 맞추는가? | geometry NID, edge 보조항, 향후 signal NMI 검토 |
| 기하·구조 정합 | 평면·선분·경계·normal을 어떻게 대응시키는가? | plane/normal/structural line gate와 연결 |
| 초기화·최적화 | 넓은 초기 오차와 local minimum을 어떻게 줄이는가? | 현재 staged multi-basin 탐색과 비교, 2D–3D RANSAC은 미구현 |
| 학습 기반 | semantic·depth·uncertainty를 학습해 modality gap을 줄이는가? | 후속 연구 후보, 현재 제품 의존성·검증 부담으로 보류 |

## 3. 논문별 검토

### P1 — Pandey et al., MI 기반 targetless calibration

**문헌 근거.** Pandey 등은 별도 calibration target 없이 카메라와 3D LiDAR가 측정한 surface intensity 사이의 mutual information을 최대화해 외부 파라미터를 추정한다. 여러 view를 충분히 사용하면 추정 분산과 평균 오차가 감소하는 경향을 실험으로 분석했다.[^P1]

**프로젝트 해석.** 우리 Core의 `signal-strength NMI`를 검토할 때 가장 직접적인 출발점이다. 그러나 F2P `signal_strength`가 reflectivity만 나타내지 않고 거리·입사각·포화·노출·AGC의 영향을 받는다면 raw intensity의 통계적 의존성을 보장할 수 없다.

**구현 상태.** Core에 `evaluateSignalNmiPose` 진단 경로는 있으나 기본 `signal_nmi_weight=0`이다. 현재 제품 PASS는 raw signal MI를 근거로 하지 않는다.

**판정.** 설계 참고로 채택, signal-strength conformance가 끝날 때까지 제품 목적함수에는 보류.

### P2 — Taylor–Nieto, NMI 기반 자동 calibration

**문헌 근거.** Taylor와 Nieto는 LiDAR scan을 camera model로 2D feature image로 변환하고, 카메라 영상과 LiDAR 영상 사이의 normalized mutual information을 비교해 calibration parameter를 탐색한다. 논문은 extrinsic뿐 아니라 일부 intrinsic parameter 탐색도 다루지만, 현재 프로젝트는 `K+D`를 고정한다.[^P2]

**프로젝트 해석.** LiDAR를 카메라 평면의 공통 표현으로 투영한 뒤 cross-modal score를 계산한다는 관점은 우리 geometry NID 설계와 연결된다. 다만 우리 organized pan-tilt scan은 시야가 제한되고 cell invalid·가림·반복 구조가 많으므로 NID 하나를 제품 승인 근거로 삼지 않는다.

**구현 상태.** range/normal geometry NID를 2×2 spatial cell에서 사용하며, edge·absolute support·구조선·hold-out을 함께 본다. focal length 공동 탐색은 연구·진단 flag로 제한한다.

**판정.** NID/공간 분할의 설계 근거로 채택, 논문의 최적화 범위와 결과 수치를 제품 성능으로 전이하지 않음.

### P3 — Koide et al., direct NID refinement toolbox

**문헌 근거.** Koide 등은 2D–3D correspondence를 SuperGlue로 찾고 RANSAC으로 초기 변환을 얻은 뒤 normalized information distance 기반 direct registration으로 refinement하는 targetless toolbox를 제안했다. 논문은 edge-alignment 방식과 비교해 정확도·강건성을 평가한다.[^P3]

**프로젝트 해석.** 넓은 yaw 오차와 대칭 장면의 local minimum을 줄이려면 coarse grid만으로 충분하지 않을 수 있으며, correspondence 기반 초기화가 유력한 보강 방향이라는 근거가 된다.

**구현 상태.** 현재 Core는 `coarse score map → separated contiguous basin → 5°/1° local → Ceres`를 사용한다. 자동 2D–3D correspondence와 RANSAC 초기화, SuperGlue 의존성은 구현하지 않았다. T1/T2 analyzer도 실제 perspective correspondence와 Ceres/NID 연결 전 단계다.

**판정.** 후속 초기화·비교 기준으로 채택, 현재 Core가 Koide toolbox를 재현했다고 기록하지 않음.

### P4 — Tamas–Kato, 자연 평면 기반 targetless calibration

**문헌 근거.** Tamas와 Kato는 특수 calibration pattern이나 명시적인 point correspondence 없이 공통 planar region을 이용하는 방법을 제시한다. 논문 설명상 extrinsic에는 최소 한 평면, intrinsic-extrinsic에는 최소 두 평면이 필요하다.[^P4]

**프로젝트 해석.** 실내의 바닥·벽·책상·문틀처럼 평면과 평면 교차선이 반복되는 장면에 기하학적 설명을 제공한다. 동시에 평면이 실제로 두 센서에서 같은 region인지, plane origin과 frame이 일치하는지 검증해야 한다.

**구현 상태.** Core는 robust normal·plane segmentation·plane intersection을 만들고 structural line과 Manhattan 정보를 별도 gate로 기록한다. Manual의 태블릿 display-plane 기반 `T_camera_lidar`는 이 논문을 재현한 것이 아니라 현장 진단용 geometry 조합이다.

**판정.** plane-based correspondence의 설계 참고로 채택, display-plane 예비값을 논문 수준의 ground truth로 승격하지 않음.

### P5 — Jiang et al., semantic mutual information

**문헌 근거.** Jiang 등은 camera와 LiDAR의 semantic information 사이 mutual information을 neural estimator로 추정하고, differentiable objective와 matrix exponential을 이용한 targetless extrinsic calibration을 제안했다.[^P5]

**프로젝트 해석.** 조명·반사·센서 intensity 차이 때문에 raw appearance와 raw signal의 직접 상관이 약할 때, 양 센서의 semantic 공통 표현이 대안이 될 수 있다.

**구현 상태.** 우리 프로젝트에는 semantic segmentation 모델, semantic MI estimator, 학습 데이터셋, differentiable training loop가 없다.

**판정.** 후속 연구 후보. 현재 Core나 T1/T2 성능의 근거로 사용하지 않음.

### P6 — Han et al., UniCalib

**문헌 근거.** UniCalib은 camera image와 sparse LiDAR를 unified dense depth representation으로 바꾸고, probabilistic flow와 reliability map으로 대응 불확실성·occlusion·동적 영역을 다루는 학습 기반 targetless calibration 방법이다. WACV 2026 논문은 KITTI 등 세 데이터셋에 대한 평가를 보고한다.[^P6]

**프로젝트 해석.** 우리처럼 modality gap과 unreliable correspondence가 큰 경우의 최신 연구 방향이다. 하지만 camera depth estimator, depth completion, 학습 모델, CV5 이식성, 실내 F2P domain transfer를 별도로 검증해야 한다.

**구현 상태.** 현재 제품 경로는 classical geometry/NID/edge/Ceres 기반이며 UniCalib의 neural flow나 reliability map을 사용하지 않는다.

**판정.** research watchlist. 현재 설계·실험의 직접 구현으로 기록하지 않음.

### P7 — Yuan et al., natural edge 기반 pixel-level calibration

**문헌 근거.** Yuan 등은 targetless 환경에서 자연 edge를 정합하고, LiDAR point cloud의 voxel cutting과 plane fitting으로 edge를 추출하는 방법을 제시한다. 또한 edge의 장면 내 분포가 calibration 관측성에 영향을 준다는 점을 분석한다.[^P7]

**프로젝트 해석.** 단순히 edge 개수가 많다는 사실보다 서로 다른 방향·공간 영역에 구조선이 분포하는지가 중요하다는 근거가 된다. 우리 false basin 분석에서 sparse edge subset과 낮은 평균 edge distance를 별도 위험으로 분리한 이유와 연결된다.

**구현 상태.** Core는 range/normal 변화, plane intersection, structural line, visible support와 spatial distribution을 함께 기록한다. 그러나 논문의 edge extractor나 정확도 수치를 그대로 사용하지 않는다.

**판정.** structural feature와 coverage gate의 설계 근거로 채택.

### P8 — Li et al., plane-constrained bundle adjustment

**문헌 근거.** Li 등은 LiDAR plane point와 visual point를 함께 사용해 plane-constrained bundle adjustment로 intrinsic·extrinsic을 공동 최적화하는 targetless 방법을 제안했다.[^P8]

**프로젝트 해석.** 평면 제약을 이용한 `K+RT` 공동 추정이 연구적으로 가능하다는 근거지만, intrinsic과 extrinsic을 동시에 풀면 camera profile 변화·보정 상태·관측성 문제가 제품 gate에 섞일 수 있다.

**구현 상태.** 우리 제품 경로는 Manual ChArUco `K+D`를 고정하고 `R,t`만 추정한다. `K+RT` 공동 추정 API/flag는 논문 재현·민감도 진단을 위해 남아 있을 뿐 제품 승인 경로가 아니다.

**판정.** 후속 연구 비교군. 현재 제품 정책에서는 보류.

## 4. 논문 근거와 우리 구현의 대응표

| 설계·실험 항목 | 참고 논문 | 현재 구현 | 현재 증거 수준 |
|---|---|---|---|
| geometry NID / spatial score | P1, P2, P3 | range/normal NID, 2×2 cell, edge 보조항 | Core unit·real log. 논문 수치 재현 아님 |
| natural edge / plane intersection | P4, P7 | plane segmentation, structural line, visible support | Core stress·실데이터 로그 |
| wide-initialization robustness | P3 | separated basin, 5°/1° local, Ceres | Core ambiguity·hold-out 로그 |
| 2D–3D RANSAC initialization | P3 | 미구현 | 후속 구현 항목 |
| signal/intensity MI | P1, P2 | 진단 API, 기본 weight `0` | conformance 전 보류 |
| semantic MI | P5 | 미구현 | 연구 후보 |
| unified depth/probabilistic flow | P6 | 미구현 | 연구 후보 |
| plane-constrained K+RT | P8 | 제품 경로에서 보류 | Manual K+D 고정 정책 |

## 5. 우리 문서의 각주 사용 범위

각주는 다음 문서의 문헌 관련 주장에만 추가했다.

| 문서 | 추가한 문헌 각주 범위 |
|---|---|
| `auto-core.md` | NID/NMI, natural edge·plane structural feature, RANSAC/NID refinement 비교, K+RT 공동 추정 보류 |
| `analyzer-experiments.md` | T1/T2 후보 신호가 연구 아이디어를 참고했지만 실제 2D–3D correspondence·Ceres/NID가 미구현임을 명시 |
| `manual-reference.md` | plane-based targetless 문헌과 tablet display-plane 진단 경로가 동일한 구현이 아님을 명시 |
| `experiment-evidence.md` | 문헌 조사 산출물과 실행 증적을 분리해 기록 |
| `roll.md` | 개인 문서 목록에서 paper review 문서를 목차로 연결 |

논문 각주는 우리 실험 로그의 `PASS`, `FAIL`, `CANDIDATE_RT`, runtime, RMSE, yaw, hold-out 수치를 뒷받침하는 출처가 아니다. 그 수치의 근거는 해당 실행 커밋·입력 package·JSON/CSV·실험 로그다.

## 6. 참고문헌

접근일은 2026-08-25다. 논문 원문·초록·서지정보를 확인할 수 있는 출처를 우선했다.

1. G. Pandey, J. McBride, S. Savarese, and R. Eustice, “Automatic Targetless Extrinsic Calibration of a 3D Lidar and Camera by Maximizing Mutual Information,” *AAAI*, vol. 26, no. 1, pp. 2053–2059, 2012. [AAAI 원문 및 DOI](https://ojs.aaai.org/index.php/AAAI/article/view/8379)
2. Z. Taylor and J. Nieto, “Automatic Calibration of Lidar and Camera Images using Normalized Mutual Information,” *IEEE ICRA*, 2013. [저자 제공 원문 PDF](https://www-personal.acfr.usyd.edu.au/jnieto/Publications_files/TaylorICRA2013.pdf)
3. K. Koide, S. Oishi, M. Yokozuka, and A. Banno, “General, Single-shot, Target-less, and Automatic LiDAR-Camera Extrinsic Calibration Toolbox,” *IEEE ICRA*, 2023. [arXiv 원문](https://arxiv.org/abs/2302.05094)
4. L. Tamas and Z. Kato, “Targetless Calibration of a Lidar - Perspective Camera Pair,” *ICCV Workshops*, pp. 668–675, 2013. [CVF Open Access](https://openaccess.thecvf.com/content_iccv_workshops_2013/W21/html/Tamas_Targetless_Calibration_of_2013_ICCV_paper.html)
5. P. Jiang, P. Osteen, and S. Saripalli, “Calibrating LiDAR and Camera using Semantic Mutual information,” arXiv:2104.12023, 2021. [arXiv 원문](https://arxiv.org/abs/2104.12023)
6. S. Han, X. Zhu, J. Wu, X. Cai, W. Yang, H. Yu, and G.-S. Xia, “UniCalib: Targetless LiDAR-camera Calibration via Probabilistic Flow on Unified Depth Representations,” *WACV*, pp. 1906–1915, 2026. [CVF Open Access](https://openaccess.thecvf.com/content/WACV2026/html/Han_UniCalib_Targetless_LiDAR-camera_Calibration_via_Probabilistic_Flow_on_Unified_Depth_WACV_2026_paper.html)
7. C. Yuan, X. Liu, X. Hong, and F. Zhang, “Pixel-level Extrinsic Self Calibration of High Resolution LiDAR and Camera in Targetless Environments,” arXiv:2103.01627, 2021. [arXiv 원문](https://arxiv.org/abs/2103.01627)
8. L. Li, H. Li, X. Liu, D. He, Z. Miao, F. Kong, R. Li, Z. Liu, and F. Zhang, “Joint Intrinsic and Extrinsic LiDAR-Camera Calibration in Targetless Environments Using Plane-Constrained Bundle Adjustment,” arXiv:2308.12629, 2023. [arXiv 원문](https://arxiv.org/abs/2308.12629)

### 본문 각주 원문

[^P1]: G. Pandey, J. McBride, S. Savarese, and R. Eustice, “Automatic Targetless Extrinsic Calibration of a 3D Lidar and Camera by Maximizing Mutual Information,” *AAAI*, 2012. [AAAI 원문 및 DOI](https://ojs.aaai.org/index.php/AAAI/article/view/8379)
[^P2]: Z. Taylor and J. Nieto, “Automatic Calibration of Lidar and Camera Images using Normalized Mutual Information,” *IEEE ICRA*, 2013. [저자 제공 원문 PDF](https://www-personal.acfr.usyd.edu.au/jnieto/Publications_files/TaylorICRA2013.pdf)
[^P3]: K. Koide, S. Oishi, M. Yokozuka, and A. Banno, “General, Single-shot, Target-less, and Automatic LiDAR-Camera Extrinsic Calibration Toolbox,” *IEEE ICRA*, 2023. [arXiv 원문](https://arxiv.org/abs/2302.05094)
[^P4]: L. Tamas and Z. Kato, “Targetless Calibration of a Lidar - Perspective Camera Pair,” *ICCV Workshops*, 2013. [CVF Open Access](https://openaccess.thecvf.com/content_iccv_workshops_2013/W21/html/Tamas_Targetless_Calibration_of_2013_ICCV_paper.html)
[^P5]: P. Jiang, P. Osteen, and S. Saripalli, “Calibrating LiDAR and Camera using Semantic Mutual information,” arXiv:2104.12023, 2021. [arXiv 원문](https://arxiv.org/abs/2104.12023)
[^P6]: S. Han, X. Zhu, J. Wu, X. Cai, W. Yang, H. Yu, and G.-S. Xia, “UniCalib: Targetless LiDAR-camera Calibration via Probabilistic Flow on Unified Depth Representations,” *WACV*, 2026. [CVF Open Access](https://openaccess.thecvf.com/content/WACV2026/html/Han_UniCalib_Targetless_LiDAR-camera_Calibration_via_Probabilistic_Flow_on_Unified_Depth_WACV_2026_paper.html)
[^P7]: C. Yuan, X. Liu, X. Hong, and F. Zhang, “Pixel-level Extrinsic Self Calibration of High Resolution LiDAR and Camera in Targetless Environments,” arXiv:2103.01627, 2021. [arXiv 원문](https://arxiv.org/abs/2103.01627)
[^P8]: L. Li, H. Li, X. Liu, D. He, Z. Miao, F. Kong, R. Li, Z. Liu, and F. Zhang, “Joint Intrinsic and Extrinsic LiDAR-Camera Calibration in Targetless Environments Using Plane-Constrained Bundle Adjustment,” arXiv:2308.12629, 2023. [arXiv 원문](https://arxiv.org/abs/2308.12629)

## 수정 이력

| 버전 | 날짜 | 변경 내용 |
|---|---|---|
| 0.1 | 2026-08-25 | `auto_calib/develop`의 targetless calibration 문헌 조사 내용을 보고서용 정의·적용 범위·각주 규칙·참고문헌으로 재구성 |
