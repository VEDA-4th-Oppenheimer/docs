# CCTV 영상 전처리와 LSD 구조선 검출

VPT-31 영상 전처리, VPT-92 구조선 검출 및 OpenSDK `lsd_line_detection` CAP의 구현
범위를 구분해 정리한다. 기준은 2026-08-04의 VPT-31/VPT-92 독립 구현, 2026-08-24
로컬 `vision_preprocessing` 작업본과 OpenSDK 공개 커밋 `704fbd1`(2026-08-19)이다.

| 구현 | 담당 범위 | 입력 | 출력 |
|---|---|---|---|
| VPT-31 라이브러리 | 입력 정규화와 영상 전처리 | BGR/BGRA/GRAY 프레임 | `CV_8UC1` 영상과 원본 프레임 메타데이터 |
| `vision_preprocessing` | VPT-31 흐름의 4채널 OpenSDK 적용 | CH1~CH4 JPEG Snapshot | 단계별 JPEG, 최종 GRAY8, 처리 CSV |
| VPT-92 라이브러리 | LSD·NFA 구조선 추출과 필터링 | VPT-31의 `CV_8UC1` | 선분 좌표·점수·방향 JSON과 overlay |
| `lsd_line_detection` | OpenSDK에서 기본 LSD 선분 표시 | `app/res/*.jpg`, `*.jpeg` | `storage/lsd_results/lsd_<원본명>` |

`vision_preprocessing`과 VPT-92 기준 구현은 확인된 로컬 작업본이다. 2026-08-24 공개
OpenSDK 저장소에 포함된 앱은 `lsd_line_detection`이며, 고급 NFA 파이프라인이 해당
CAP에 이미 통합되었다고 표현하면 안 된다.

## 전처리 파이프라인

```text
CH1~CH4 Snapshot 또는 BGR/BGRA/GRAY 입력
  -> 선택적 크기 정규화
  -> Grayscale
  -> Gaussian 5×5
  -> CLAHE, 선택
  -> Sharpening, 선택
  -> GRAY8 결과
  -> VPT-92 구조선 검출 입력
```

VPT-31 라이브러리는 영상 취득과 분리되어 있으며 `channel_id`, `frame_id`,
`timestamp_us`를 보존한다. OpenSDK 작업본은 플랫폼 Snapshot에서 입력을 얻고 각
채널의 JPEG·처리 시간을 별도로 남긴다.

### Grayscale과 Gaussian

```cpp
cv::cvtColor(source, grayscale, cv::COLOR_BGR2GRAY);
cv::GaussianBlur(grayscale, processed, cv::Size(5, 5), 0.0);
```

Grayscale은 후속 구조선 검출용 단일 채널 영상을 만든다. Gaussian 5×5는 고주파
노이즈를 완화한다. 출력은 `CV_8UC1`이므로 VPT-92에서 다시 색상 변환할 필요가 없다.

### CLAHE와 Sharpening

```cpp
auto clahe = cv::createCLAHE(clip_limit, cv::Size(tile_grid, tile_grid));
clahe->apply(processed, corrected);

cv::GaussianBlur(processed, smooth, cv::Size(0, 0), 1.0);
cv::addWeighted(processed, 1.0 + amount, smooth, -amount, 0.0, sharpened);
```

CLAHE는 국소 대비를 높이고 Sharpening은 완화 영상과 원본의 차이를 이용해 경계를
강조한다. 두 연산은 각각 켜고 끌 수 있다. 과도한 보정이 오히려 허위 선분을 늘릴 수
있으므로 VPT-92의 통과 선분 수와 처리 시간을 함께 비교한다.

### OpenSDK 전처리 설정

```json
{
  "output_width": 0,
  "output_height": 0,
  "clahe_enabled": 1,
  "clahe_clip_limit": 2.0,
  "clahe_tile_grid_size": 8,
  "sharpen_enabled": 1,
  "sharpen_amount": 1.0
}
```

| 항목 | 기본값 | 의미 |
|---|---:|---|
| `output_width`, `output_height` | `0`, `0` | 둘 다 양수일 때만 크기를 변경; 0이면 원본 크기 유지 |
| `clahe_enabled` | `1` | CLAHE 수행 여부 |
| `clahe_clip_limit` | `2.0` | 최소 `0.1`로 보정하는 국소 대비 제한 |
| `clahe_tile_grid_size` | `8` | 최소 1의 CLAHE 타일 격자 크기 |
| `sharpen_enabled` | `1` | Sharpening 수행 여부 |
| `sharpen_amount` | `1.0` | 최소 0의 경계 강조 강도 |

설정 파일이 없으면 코드에 정의된 기본값을 사용한다. 출력 크기는 두 값이 모두 양수일
때 `cv::INTER_AREA`로 변경한다.

## OpenSDK Snapshot과 저장 구조

SDK 채널은 `0~3`, 웹 화면의 채널은 `1~4`이다. 요청 하나에서 네 채널을 차례대로
Snapshot하고 채널별 결과를 저장한다.

```text
storage/captured/
└── ch0_snapshot.jpg ... ch3_snapshot.jpg

storage/preprocessed/
├── ch0_00_grayscale.jpg
├── ch0_01_gaussian5x5.jpg
├── ch0_02_clahe.jpg
├── ch0_03_sharpen.jpg
├── ch0_final.jpg
├── ch1_final.jpg ... ch3_final.jpg
└── processing_metrics.csv
```

```csv
channel_id,timestamp_ms,input,output,processing_time_ms,status
0,1760000000000,../storage/captured/ch0_snapshot.jpg,../storage/preprocessed/ch0_final.jpg,12.5,ok
```

실제 CSV 컬럼은 위 여섯 개다. 해상도, 픽셀 포맷과 처리 파라미터를 CSV에 남기는
기능은 현재 OpenSDK 작업본 코드에서 확인되지 않으므로 구현 완료로 적지 않는다.

## VPT-92 구조선 검출

VPT-92 독립 구현은 `LSD_REFINE_ADV`를 사용해 좌표 외에 폭, 정밀도와 NFA 점수를
함께 얻는다.

```cpp
auto detector = cv::createLineSegmentDetector(
    cv::LSD_REFINE_ADV,
    scale,
    sigma_scale,
    quantization_bound,
    angle_threshold_deg,
    log_eps,
    density_threshold,
    bins);

detector->detect(frame.image, raw, widths, precisions, nfas);
```

| 파라미터 | 기준 기본값 | 역할 |
|---|---:|---|
| `scale` | `0.8` | 검출 이미지 스케일 |
| `sigma_scale` | `0.6` | 내부 평활화 비율 |
| `quantization_bound` | `2.0` | 그라디언트 양자화 경계 |
| `angle_threshold_deg` | `22.5` | 선분 방향 허용 범위 |
| `density_threshold` | `0.7` | 선분 영역 밀도 |
| `bins` | `1024` | 내부 정렬 bin 수 |
| `min_length_px` | `20.0` | 통과 최소 선분 길이 |
| `min_nfa` | `0.0` | 통과 최소 `-log10(NFA)` 점수 |
| `axis_tolerance_deg` | `5.0` | 수평·수직 분류 허용 각도 |
| `axis_aligned_only` | `false` | 수평·수직만 남길지 여부 |

NFA 점수는 기대되는 거짓 검출 수의 음의 상용로그다. `0`은 기대 거짓 검출 수 1,
값이 클수록 더 강한 통계적 신뢰를 의미한다. 구현은 길이·NFA를 먼저 검사한 뒤 필요하면
수평·수직 방향으로 한 번 더 거른다.

```text
dx = x2 - x1
dy = y2 - y1
length = hypot(dx, dy)
angle_deg = canonical_angle(atan2(dy, dx))
normal_angle_deg = canonical_angle(angle_deg + 90)
```

### VPT-92 결과 예시

```json
{
  "requirement": "R-CAL-SFR-007",
  "channel_id": "camera-2",
  "frame_id": 42,
  "timestamp_us": 123456789,
  "raw_line_count": 12,
  "accepted_line_count": 4,
  "processing_ms": 8.2,
  "lines": [
    {
      "x1": 20.0,
      "y1": 50.0,
      "x2": 235.0,
      "y2": 50.0,
      "width": 2.0,
      "precision": 0.1,
      "nfa": 3.2,
      "length": 215.0,
      "angle_deg": 0.0,
      "normal_angle_deg": 90.0,
      "orientation": "horizontal"
    }
  ]
}
```

예시 값은 형식 설명용이다. 실제 선분 수와 처리 시간은 입력 영상·플랫폼에 따라
달라진다.

## 공개 LSD CAP과 VPT-92의 차이

OpenSDK 공개 `lsd_line_detection` 앱은 다음 경로만 구현한다.

```cpp
cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
auto detector = cv::createLineSegmentDetector(cv::LSD_REFINE_STD);
detector->detect(gray, lines);
detector->drawSegments(image, lines);
```

| 기능 | VPT-92 독립 구현 | 공개 LSD CAP |
|---|---|---|
| LSD 모드 | `LSD_REFINE_ADV` | `LSD_REFINE_STD` |
| 입력 | VPT-31의 `CV_8UC1` | `app/res`의 JPEG |
| NFA 점수 | 추출 및 임계값 필터 | 미구현 |
| 길이·수평·수직·법선 | 추출 및 분류 | 미구현 |
| 결과 JSON | `lines.json` | 미구현 |
| 시각화 | `overlay.png` | `lsd_<원본명>` JPEG |
| 4채널 Snapshot 직접 입력 | 별도 OpenSDK 어댑터 필요 | 미구현 |

공개 CAP을 VPT-92 수준으로 확장하려면 `LSD_REFINE_ADV`, NFA 출력, 프레임
메타데이터, Snapshot 연결 및 JSON 증적을 앱 코드에 명시적으로 이식해야 한다.

## 확인된 검증 범위

VPT-31/VPT-92 독립 테스트는 Grayscale/Gaussian 결과, 메타데이터 보존, CLAHE와
Sharpening 적용, 합성 수평·수직 선분 반복성, 빈 이미지와 컬러 입력 거부를 검사한다.
다만 해당 테스트 통과가 공개 LSD CAP의 NFA 기능 또는 실제 CV5 4채널 통합시험 통과를
의미하지는 않는다.
