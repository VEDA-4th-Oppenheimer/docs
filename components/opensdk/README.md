# OpenSDK

Edge AI 카메라 Open Platform SDK 관련 문서를 둔다 — API 조사, 호출 예시,
샘플 코드 분석, 카메라 단 연동 방법.

| 문서 | 내용 | 담당 |
|---|---|---|
| [architecture.md](architecture.md) | CV5 OpenSDK 앱 구성, LifeCycleManager·AppDispatcher, Snapshot과 앱 간 책임 경계 | 이영민 |
| [vision-preprocessing.md](vision-preprocessing.md) | VPT-31 Grayscale·Gaussian·CLAHE·Sharpening과 VPT-92 LSD·NFA 구조선 검출 | 이영민 |
| [mobile-sam.md](mobile-sam.md) | MobileSAM ONNX 분리, OpenCV DNN 호환, 8×8 prompt와 4채널 마스크 | 이영민 |
| [tcp-server.md](tcp-server.md) | LiDAR JSON mTLS 수신, 안전한 파일 framing, 세션 저장과 인증서 운영 | 이영민 |
| [calibration-app.md](calibration-app.md) | JSON 선택, 4채널 Snapshot, 채널 1 Core 실행과 결과·상태 관리; 구버전 auto_calib Core 업데이트 범위 포함 | 이영민 (앱) / 광진 (Core 업데이트) |
