# RTSP/RTP 스트림 분석과 Qt 수신 대응

## 문서 기준

이 문서는 `wireshark_log`에서 수행한 RTSP/RTP·H.264 분석 문서, pcap 결과, 분석 스크립트를 기준으로 작성한다. 분석 문서와 스크립트는 광진의 개인 작업으로 기록하며, 전체 Qt 애플리케이션 구현의 소유권을 주장하는 문서는 아니다.

원본 pcap, CSV, 결과 로그는 작업 공간에 보존한다. 공개 문서에는 IP, 계정, 비밀번호, token, 로컬 절대 경로를 넣지 않는다.

정리 기준일은 2026-08-25이며, 원본 Qt GUI 구현·검증 기록에는 2026-08-04 기준일이 남아 있다.

## 작성 산출물 범위

| 분류 | 원본 문서·스크립트 | 기록하는 기여 |
|---|---|---|
| packet 측정 | `analysis_results.md`, `analysis_cbr_results.md`, `analysis_vbr_motion_results.md` | baseline·CBR·VBR motion의 frame/GOP/packet/수신시간 비교 |
| 장애 분석 | `qt_rtsp_packet_loss_troubleshooting.md`, `qt_rtsp_gstreamer_vs_ffmpeg.md` | UDP loss, FFmpeg queue, TCP 전환과 backend 비교 근거 |
| GPU·플랫폼 설계 | `ffmpeg_gpu_acceleration_guide.md`, `qt_cross_platform_gpu_guide.md`, `cross_platform_rtsp_hw_architecture.md` | decode backend와 zero-copy, Windows/Linux/macOS 경계 정리 |
| Qt 검증 문서 | `qt_gui_implementation_details.md`, `qt_gui_testing_verification.md` | RTSP 수신 구조와 검증 항목 문서화. 전체 Qt 앱 구현 소유권과는 구분 |
| 분석 스크립트 | `analyze_h264.py`, `analyze_cbr.py`, `analyze_vbr_motion.py`, `analyze_rtp.py`, `find_sps.py`, `debug_nal.py` | pcap/RTP/NAL 재현 분석 |

## 분석 방법

```text
pcapng
  -> RTP payload 추출
  -> H.264/H.265 NAL type·FU/STAP/AP 분류
  -> SPS 해상도·profile 파싱
  -> RTP timestamp별 frame grouping
  -> marker bit·sequence·도착시간·payload size 집계
  -> static / CBR / VBR-motion 비교
```

주요 스크립트는 `analyze_h264.py`, `analyze_cbr.py`, `analyze_vbr_motion.py`, `analyze_rtp.py`, `find_sps.py`, `debug_nal.py`다. H.264 SPS, IDR/P frame, FU-A/STAP-A와 HEVC VPS/SPS/PPS/FU/AP 구조를 분석하고, frame 완성에 걸린 시간을 첫 packet부터 marker packet까지 계산한다.

## 분석 결과

| 조건 | 관측 결과 | 의미 |
|---|---|---|
| 기존 Profile 4/VBR | `800×448`, H.264 High@3.1, 약 `29.7 fps`, 평균 `441 kbps`, IPP…P, GOP 약 60 | 저해상도·저대역폭 baseline |
| Profile 2/CBR | `2592×1520`, H.264 High@5.0, 평균 `4,971 kbps`, 약 `30.5 fps` | 고해상도에서 P-frame도 여러 RTP packet으로 분할 |
| Profile 2/VBR 정지 | 평균 `2.13 Mbps`, P-frame 약 `5.99 KB`, 수신 약 `5.64 ms` | 정지 장면은 대역폭 감소 |
| Profile 2/VBR 큰 움직임 | 평균 `3.82 Mbps`, peak `4.86 Mbps`, P-frame 약 `14.22 KB`, 수신 `10.76 ms` | motion vector 증가로 packet burst와 수신 지연 증가 |

### CBR 세부 수치

- IDR 평균 `210 KB`, 평균 수신 완료 `170.30 ms`, 최대 `735.73 ms`
- P-frame 평균 `18.4 KB`, 평균 수신 완료 `16.80 ms`, 최대 `453.18 ms`
- GOP 평균 `61.1 frame`, 약 2초마다 IDR
- IPP…P 구조이며 B-frame은 관측되지 않음

### baseline 세부 수치

- 전체 `9,364 frame`, 추정 `29.7 fps`
- IDR 평균 `43,704 bytes`, 수신 평균 `109.76 ms`, 최대 `934.59 ms`
- P-frame 평균 `1,006 bytes`, 수신 평균 `2.44 ms`
- IDR은 P-frame보다 약 43배 큼

## 실험·검증 로그

### Log-R01: Profile 4 / VBR baseline

| 항목 | 기록 |
|---|---|
| 캡처 | 약 `311.9 s`, 총 `9,364 frames`, `16.39 MB` |
| 영상 | H.264 High@3.1, `800×448`, 4:2:0, 8-bit |
| 전송 | RTP over UDP, dynamic payload `98` |
| frame 구조 | IDR `181`, P `9,091`, 기타 `92`, B-frame 없음 |
| GOP | 평균 `60 frames`, IDR 약 `2 s` 간격 |
| bitrate | 평균 `441 kbps` |
| IDR | 평균 `43,704 B`, 평균 수신 `109.76 ms`, 최대 `934.59 ms` |
| P-frame | 평균 `1,006 B`, 평균 수신 `2.44 ms`, 최대 `305.62 ms` |

이 baseline은 저해상도·저대역폭 조건이며, P-frame 대부분이 단일 RTP packet으로 도착했다. IDR의 큰 frame size와 최대 수신 지연은 이후 고해상도 비교의 기준으로 사용했다.

### Log-R02: Profile 2 / CBR

| 항목 | 기록 |
|---|---|
| 캡처 | 약 `106.22 s`, 총 `3,242 frames` |
| 영상 | H.264 High@5.0, `2592×1520` |
| bitrate | 목표 약 `5.0 Mbps`, 실제 평균 `4,971.0 kbps`, 초별 약 `539~7,512 kbps` |
| frame 구조 | IDR `52`, P `2,926`, 기타 `264`, B-frame 없음 |
| FPS/GOP | 약 `30.5 fps`, GOP 평균 `61.1 frames`, IDR 약 `2 s` |
| IDR | 평균 `210,082 B`, 평균 수신 `170.30 ms`, 최대 `735.73 ms` |
| P-frame | 평균 `18,380 B`, 평균 수신 `16.80 ms`, 최대 `453.18 ms` |
| packet 분할 | IDR 약 `145~160 RTP packets`, P-frame 약 `12~25 FU-A packets` |

고해상도 CBR에서는 P-frame도 여러 RTP packet으로 분할되어 수신 buffer와 reorder queue에 부담을 준다. 평균 bitrate만으로 손실을 판단하지 않고 frame size·packet count·marker completion time을 함께 기록했다.

### Log-R03: Profile 2 / VBR motion

| 구간 | 평균 bitrate | P-frame 평균 크기 | 평균 수신 완료 | 해석 |
|---|---:|---:|---:|---|
| 정지 `0~15 s` | `2.13 Mbps` | `5,994 B` | `5.64 ms` | baseline idle |
| 큰 움직임 `24~44 s` | `3.82 Mbps`, peak `4.86 Mbps` | `14,216 B`, peak `18.6 KB` | `10.76 ms`, max `17.54 ms` | packet burst 증가 |
| 정지 복귀 `48~58 s` | `2.10 Mbps` | `6,344 B` | `7.06 ms` | bitrate와 packet 분할 감소 |

캡처 전체는 `58.88 s`, `1,928 frames`였다. 정지에서 motion으로 전환할 때 P-frame 크기는 약 `6 KB → 14.2 KB`, 분할 packet은 약 `4.79 → 10.64`, 수신 완료 시간은 `5.64 → 10.76 ms`로 증가했다.

### Log-R04: Qt/FFmpeg missed packet 현상

관측 로그는 다음과 같다.

```text
[rtsp] RTP: missed 14 packets
[rtsp] max delay reached. need to consume packet
[rtsp] RTP: missed 37 packets
[rtsp] max delay reached. need to consume packet
```

해석 순서는 `motion burst → OS UDP socket buffer overflow 가능성 → RTP sequence gap → FFmpeg reorder wait → max_delay 도달 → incomplete NAL decode`다. Wireshark에 packet이 보인다는 사실만으로 Qt process가 모든 packet을 수신했다는 뜻은 아니다.

### 분석과 구현의 증거 수준

| 기록 | 증거 수준 | 의미 |
|---|---|---|
| R01/R02/R03 pcap 분석 | 측정 결과 | 동일한 분석 스크립트로 frame·packet·시간을 집계한 수치 |
| R04 FFmpeg log | 현상 로그 + 원인 가설 | UDP socket/reorder 병목과 연결되지만 kernel drop counter 추가 측정 필요 |
| TCP·buffer_size·max_delay 대응 | 구현/실험 항목 | 환경별 latency·drop 재측정이 필요 |
| GPU·zero-copy·GStreamer/FFmpeg 비교 | 설계·비교 문서 | 이 문서의 pcap 수치가 GPU 성능을 입증하지 않음 |

## Packet loss 원인 해석

움직임이 커지면 P-frame이 5~6 KB에서 14~18 KB 이상으로 증가하고, MTU 기준 여러 RTP packet이 짧은 시간에 burst로 도착한다. UDP 수신에서는 다음 단계가 병목이 될 수 있다.

```text
NIC/Wireshark capture
  -> OS UDP socket receive buffer
  -> FFmpeg RTP reorder queue
  -> NAL/frame assembly
  -> decoder
```

Wireshark에 packet이 보이더라도 Qt/FFmpeg가 OS socket buffer에서 제때 읽지 못하면 sequence gap이 생길 수 있다. `max delay reached`는 reorder 대기 후 불완전한 NAL을 decoder로 넘기는 상황과 연결되며, frame drop·깨짐으로 나타날 수 있다.

## 대응 우선순위

1. **RTSP over TCP 우선**: UDP packet loss를 줄이기 위해 interleaved TCP를 먼저 시험한다.
2. **UDP 유지 시 receive buffer 확대**: burst를 흡수할 수 있도록 FFmpeg `buffer_size`를 환경별로 측정해 조정한다.
3. **수신 loop 분리**: `av_read_frame`과 decode/render 작업이 packet 수신을 막지 않도록 수신 스레드를 분리한다.
4. **motion/CBR 조건을 함께 시험**: 평균 bitrate만 보지 말고 IDR/P-frame 크기, packet count, marker 완료시간, missed sequence를 같이 기록한다.
5. **GPU 전환 시 zero-copy 확인**: GPU decode 후 CPU `QImage` 복사가 다시 병목이 되지 않는지 별도 측정한다.

## Qt 구현과 분석의 경계

현재 Qt `RtspDecoder`에는 TCP transport, read timeout, `max_delay`, 연결 재시도 상한과 metadata stream 전달이 반영되어 있다. 이 문서는 그 구현을 제품 성능 보증으로 해석하지 않고, pcap 기반 원인·측정 항목·재현 조건을 남기는 분석 기록으로 사용한다.

## 재현 기록 형식

각 분석에는 다음을 함께 기록한다.

- camera profile/resolution/codec/profile/level
- CBR/VBR와 목표 bitrate
- capture duration, frame count, RTP payload type
- IDR/P/B 개수와 GOP 간격
- frame size, packet count, marker 완료시간
- sequence gap, `max delay`, decoder error 로그
- 사용 pcap/CSV/script 버전과 분석 날짜

평균 bitrate 하나만으로 packet loss 원인을 결론내리지 않는다. 고정 장면과 motion 장면을 같은 network/decoder 조건에서 비교해야 한다.
