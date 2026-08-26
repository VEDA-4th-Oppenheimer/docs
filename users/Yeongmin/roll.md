# 이영민 — 담당 범위와 작성 문서

## 담당 범위

| 파트 | 맡은 것 | 저장소 위치 |
|---|---|---|
| OpenSDK 애플리케이션 | CV5 카메라 앱 구성, LifeCycleManager·AppDispatcher, Snapshot API, Docker/CMake 빌드와 CAP 패키징 | `OpenSDK` — `tcp_server/`, `calibration/`; 추가 검증용 `lsd_line_detection/`, `sam_segmentation/` |
| CCTV 영상 전처리 | 4채널 Snapshot, Grayscale, Gaussian 5×5, CLAHE, Sharpening과 채널별 처리 증적 | 별도 작업본 — `vision_preprocessing/`; VPT-31 기준 구현 |
| 추가 검증용 구조선 검출 | 현재 자동 캘리브레이션 경로와 분리된 LSD 선분 검출과 VPT-92의 NFA·길이·방향·법선 필터 검증 | `OpenSDK` — `lsd_line_detection/` (현재 구조에는 미사용); 별도 VPT-92 기준 구현 |
| 추가 검증용 AI 세그멘테이션 | 현재 자동 캘리브레이션 경로와 분리된 MobileSAM encoder·decoder ONNX 변환, OpenCV 4.12 DNN 호환과 4채널 마스크 검증 | `OpenSDK` — `sam_segmentation/` (현재 구조에는 미사용) |
| 카메라 수신 서버 | LiDAR JSON의 TLS 1.2+ mTLS 수신, 파일 framing·검증, 세션별 저장과 웹 상태 조회 | `OpenSDK` — `tcp_server/` |
| 자동 캘리브레이션 통합 | LiDAR JSON 선택, 4채널 Snapshot, 채널 1 staging, Calibration Core 이식·실행과 결과 판정 | `OpenSDK` — `calibration/` |
| CV5 성능 최적화 | staged 탐색 적용, Cortex-A76/NEON Release 설정, Ceres 스레드·가시성 재사용과 요청 시간 측정 | `OpenSDK` — `calibration/automatic_calibration/`, `calibration/dependencies/` |
| 카메라 인터페이스 | RPi→CCTV 업로드의 카메라 수신 측 전송 형식, mTLS 신원과 응답 계약 | `docs` — `interfaces/camera-upload.md` (이현우와 공동) |

## 작성 문서

| 문서 | 다루는 것 |
|---|---|
| [OpenSDK 앱 구조와 카메라 런타임](../../components/opensdk/architecture.md) | CV5 앱 lifecycle, AppDispatcher, 4채널 Snapshot, CAP 구성과 앱 간 데이터 경계 |
| [추가 검증용 영상 전처리와 구조선 검출](../../components/opensdk/vision-preprocessing.md) | 현재 캘리브레이션 구조에는 사용하지 않는 전처리·LSD 독립 구현, VPT-31/92와 공개 CAP의 차이 |
| [추가 검증용 MobileSAM 세그멘테이션](../../components/opensdk/mobile-sam.md) | 현재 캘리브레이션 구조에는 사용하지 않는 독립 CAP의 ONNX 분리, OpenCV 4.12 호환, 8×8 자동 prompt와 4채널 결과 |
| [LiDAR JSON mTLS 수신 서버](../../components/opensdk/tcp-server.md) | TLS 1.2+, 포트 2222, 파일 framing, JSON 검증, `.part` 처리와 `/tmp/calibration` 세션 |
| [카메라 캘리브레이션 앱](../../components/opensdk/calibration-app.md) | JSON 선택, 4채널 Snapshot, 채널 1 staging, Calibration Core 실행과 candidate-only 결과 |
| [CV5 캘리브레이션 최적화](../../components/calibration/cv5-optimization.md) | staged 탐색, ChArUco intrinsic·왜곡 보정, ARM/NEON, Ceres 2스레드와 성능 검증 |
| [카메라 업로드 계약](../../interfaces/camera-upload.md) | RPi 송신과 CCTV 수신의 mTLS 신원, 파일 framing, 응답·재시도 계약 (이현우와 공동) |
| [OpenSDK 빌드 및 CAP 배포](../../guides/opensdk-build-and-deploy.md) | Docker, CV5 toolchain, OpenCV/Ceres 교차 컴파일, CAP 패키징, 배포와 운영 점검 |
