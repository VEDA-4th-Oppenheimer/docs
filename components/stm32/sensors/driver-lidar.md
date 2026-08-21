# Edge AI CCTV 2D 마커리스 자동 캘리브레이션 킷 · Module 1 (H/W & Embedded Control)

**LiDAR 수신 드라이버 (`App/lidar/`)**
작성: 송영빈 (VEDA 7기 1팀) · STM32F401RE / TOFSense-F2 P / NLink Protocol
각도 래치 · 샘플 큐: 이현우

---

## 1. 개요

본 문서는 캘리브레이션 킷의 2축 Pan-Tilt 스텝모터에 탑재된 1D LiDAR(TOFSense-F2 P)의
UART 통신 드라이버 구현 내용을 정리한 것입니다. STM32 MCU가 라이다로부터 거리 데이터를
수신·파싱·검증하여 최종적으로 각도(θ, φ) 데이터와 결합해 Raspberry Pi 4B로 전달하기까지의
파이프라인 중 **앞단(센서 파싱 + 각도 결합)** 에 해당합니다.

> **각도 결합까지가 이 모듈의 책임입니다.** 초기 설계에서는 `lidar_get_distance_mm()` 을
> 상위 로직이 폴링해 각도와 짝짓는 구조였으나, 그 방식은 스캔 정밀도를 만족하지 못해
> **프레임 완성 시점에 ISR 에서 각도를 래치하는 구조로 변경**되었습니다(4.3절). 폴링 API 는
> 디버그용으로만 남아 있습니다.

**센서 사양**: TOF(Time of Flight) 방식, 거리 분해능 1mm, 최대 갱신 주파수 100Hz,
FOV 1~2°. 측정 거리는 데이터시트 재확인이 필요합니다(9절 ①).

---

## 2. 통신 프로토콜 (NLink)

TOFSense 계열은 Nooploop사의 NLink 프로토콜을 사용하며, UART 기본 통신 설정은
8N1 / 115200bps(가변)입니다. 한 프레임은 고정 16바이트로 구성됩니다.

### 2.1 패킷 구조

| Byte | 필드 | 타입 | 설명 |
|---|---|---|---|
| 0 | Header | uint8 | 고정 `0x57` |
| 1 | Function Mark | uint8 | 고정 `0x00` |
| 2 | Reserved | uint8 | 예약 (통상 `0xFF`) |
| 3 | Id | uint8 | 센서 모듈 ID |
| 4~7 | System Time | uint32 | 센서 자체 시계 (ms, LE) |
| 8~10 | Distance | uint24 | 거리값 (mm, LE) |
| 11 | Dis Status | uint8 | 거리 데이터 신뢰도 상태 |
| 12~13 | Signal Strength | uint16 | 신호 강도 (LE) |
| 14 | Range Precision | uint8 | 측정 정밀도(cm). **F2 P는 미지원 — `0xFF` 고정** |
| 15 | Check Sum | uint8 | Byte 0~14 합의 하위 8비트 |

**엔디안**: NLink는 Little-Endian을 따릅니다. 거리값은
`buf[8] | (buf[9]<<8) | (buf[10]<<16)` 로 추출합니다.

### 2.2 Distance Status 코드

| 값 | 의미 |
|---|---|
| 0 | 정상 측정 |
| 1 | 표준편차 15mm 초과 (경고성, 사용 가능) |
| 2 | 신호 강도 부족 |
| 4 | 위상(Phase) 경계 초과 |
| 5 | HW 또는 VCSEL 결함 |
| 7 | 위상 불일치 |
| 8 | 내부 알고리즘 언더플로우 |
| 14 | 측정 자체가 무효 |

**실측 참고**: 1축 브링업에서 유효점 359/359 가 전부 `1` 로 수신되었습니다.

> **주의 — 파서는 Dis Status로 거르지 않습니다.** 초기 구현은 "0과 1만 통과"시켰으나
> 현재는 **체크섬만 검사하고 원본 값을 그대로 상행**합니다. 변경 이유는 4.5절 참조.

### 2.3 공식 예제 코드 대비 검증

구현한 파싱 로직을 Nooploop 공식 지원 문서(support.nooploop.com/tofsense/example-code)와
공식 파서 저장소(github.com/nooploop-dev/nlink_unpack)의 Raw Data Analysis / Python
예제와 대조 검증했습니다.

- **헤더 검증**: `buf[0]==0x57 && buf[1]==0x00` — 동일
- **체크섬**: Byte 0~14 합의 하위 8비트를 Byte 15와 비교 — 동일
- **거리 추출**: 공식 C 예제는 `(buf[8]<<8 | buf[9]<<16 | buf[10]<<24)/256` 형태로
  계산하나, 이는 24비트 값을 상위 비트에 배치한 뒤 256으로 나눠 내리는 것으로
  `buf[8] | (buf[9]<<8) | (buf[10]<<16)` 와 수치적으로 동일. 공식 Python 예제
  (`nByteUnpack`)도 Little-Endian 3바이트를 그대로 읽어 동일한 결과 — 현재 구현과 일치
- **Dis Status 위치(Byte 11)** — 동일

---

## 3. 하드웨어 결선 및 통합 지점

| 항목 | 값 |
|---|---|
| 포트 | USART6 — **PC6 = TX, PC7 = RX** (라이다 TX가 STM32 PC7로 들어와야 함) |
| 설정 | 115200 8N1, 흐름제어 없음, `USART6_IRQn` 활성 |
| 수신 방식 | `HAL_UART_Receive_IT(&huart6, &g_rx_byte, 1)` — **1바이트씩** 인터럽트 |
| 디버그 출력 | USART2 (ST-Link VCP), 115200 |
| 출력 레이트 | F2 P 액티브 출력 기본 50Hz — **100Hz로 설정해 사용**. 스캔 샘플 간격이 `틸트속도 / rate` 로 결정되므로 50Hz면 격자가 절반으로 성깁니다 |

`main.c` 에서의 결선은 네 곳입니다. `RxCplt`/`Error` 콜백은 USART1(RPi)과 공유되므로 각
모듈이 `huart->Instance` 를 확인한 뒤 자기 것만 처리합니다.

```c
lidar_init(&huart6);       /* 초기화 — 큐 비우고 수신 최초 무장            */
lidar_process();           /* 메인루프 매 바퀴 — 샘플 큐를 scan 으로 배출  */
lidar_on_rx_cplt(huart);   /* HAL_UART_RxCpltCallback 에서 위임            */
lidar_on_error(huart);     /* HAL_UART_ErrorCallback 에서 위임             */
```

---

## 4. 소스 코드 아키텍처

UART/인터럽트 제어와 순수 패킷 파싱을 분리해 재사용성과 테스트 용이성을 확보했습니다.

| 파일 | 책임 |
|---|---|
| `lidar.c / .h` | UART 인터럽트 수신 상태 관리, **각도 래치**, 샘플 큐, 진단 카운터, 에러 복구 |
| `lidar_parser.c / .h` | 순수 패킷 파싱 (헤더 판별 · 체크섬 · 필드 추출). HAL 의존성 없음 → PC 유닛 테스트 가능 |

> **`calib.c / .h` 는 삭제되었습니다**(커밋 `5b229cb`). 오프셋 보정·EMA 필터는 펌웨어에서
> 수행하지 않습니다 — 원본 raw 데이터를 그대로 RPi로 올리고 보정은 상위(데몬/캘리브)에서
> 합니다. 근거는 4.5절과 같습니다.

### 4.1 데이터 흐름

```
USART6 RX ISR ─ 1바이트씩 상태머신 ─ 16바이트 완성
                      │
                      ├─ lidar_parser_parse()   체크섬 검증 + 필드 추출
                      ├─ scan_latch_angles()    pan/tilt 스냅샷   ← 핵심
                      └─ 샘플 링버퍼 push
                                │
   메인루프 lidar_process() ────┴─ pop ─ scan_submit_sample() ─ uart_rpi ─ RPi
```

경계는 하나입니다. **ISR이 생산하고 메인루프가 소비합니다.** ISR에서 하는 일은 바이트
누적 · 체크섬 · 모터 카운터 읽기(각도 래치)까지이고, UART 송신처럼 긴 작업은 전부
메인루프로 넘깁니다.

### 4.2 수신 상태 머신

```
STATE_WAIT_HEADER     0x57 수신 대기
      │ (0x57 매치)
      ▼
STATE_WAIT_FUNC_MARK  0x00 수신 대기
      │ (0x00 매치)          │ (불일치 → 재동기화)
      ▼                     └──────────► STATE_WAIT_HEADER
STATE_COLLECT_BODY    나머지 14바이트 적재
      │ (16바이트 완성)
      ▼
lidar_parser_parse() → 체크섬 검증 → 각도 래치 → 큐 push
```

| 상태 | 조건 | 동작 |
|---|---|---|
| `STATE_WAIT_HEADER` | `g_idx == 0` | 수신 바이트가 `0x57`이면 버퍼에 저장 후 진행, 아니면 대기 유지 |
| `STATE_WAIT_FUNC_MARK` | `g_idx == 1` | `0x00`이면 진행, 아니면 `g_idx=0`으로 재동기화(헤더 오탐) |
| `STATE_COLLECT_BODY` | `g_idx >= 2` | 계속 적재, 16바이트 도달 시 파싱 후 `g_idx` 리셋 |

**오버플로우 가드**: `g_idx` 가 버퍼 크기(`LIDAR_PACKET_SIZE`)를 넘어서면 무조건 0으로
리셋하여 재동기화합니다.

### 4.3 핵심: 각도를 ISR에서 래치하는 이유

거리와 각도를 짝짓는 **시점**이 이 모듈 설계의 핵심입니다.

폴링(메인루프에서 `lidar_get_distance_mm()` 을 읽어 각도와 결합)으로는 요구 정밀도를
만족할 수 없습니다. 메인루프가 언제 읽느냐에 따라 최대 한 프레임 주기(100Hz = 10ms)만큼
어긋나는데, 틸트가 90°/s 로 도는 동안 그 사이에 **0.9°** 를 움직입니다. 스캔 격자가
0.9°인데 스미어가 0.9°면 격자 한 칸이 통째로 뭉개집니다.

따라서 프레임의 **마지막 바이트를 받은 그 순간** `scan_latch_angles()` 로 모터 카운터를
읽어 샘플에 함께 담습니다. 카운터 읽기뿐이라 ISR에서 안전합니다.

래치 시각은 `stm_ts_ms`(STM32 HAL tick)로 함께 상행합니다. 라이다 자체 시계인
`device_time_ms` 와는 **서로 다른 clock domain 이므로 섞어 쓰면 안 됩니다.**

### 4.4 샘플 큐 (SPSC 링버퍼)

```c
#define LIDAR_SAMPLE_QUEUE_LEN   8U     /* lidar.h */
```

- 생산자 = RX ISR(`g_q_head` 만 증가), 소비자 = 메인루프(`g_q_tail` 만 증가). 각각 한쪽에서만
  증가하는 8비트 단일 워드 접근이라 **락이 필요 없습니다.**
- 깊이가 2의 거듭제곱이라 인덱스는 마스킹(`& (LEN-1)`)으로 감쌉니다.
- 8칸 = 100Hz 기준 **80ms** 여유. 실제로는 한 칸을 넘지 않습니다 — 메인루프에서 가장 느린
  구간이 점 하나 상행(115200에서 23바이트 ≈ 2ms)이기 때문입니다.

**넘칠 때는 새 샘플을 버립니다.** 가장 오래된 것을 밀어내지 않고 새 것을 버린 뒤
`queue_drops` 를 올립니다 — 이미 들어간 샘플은 각도가 짝지어져 있고, 순서를 흐트러뜨리면
데몬이 격자에 넣을 때 더 헷갈리기 때문입니다. `drops` 증가는 라이다가 아니라 **메인루프가
80ms 이상 밀렸다**는 신호입니다.

### 4.5 파서 정책: 체크섬 외에는 거르지 않는다

`lidar_parser_parse()` 는 **체크섬만** 검사하고, 거리 범위 · Dis Status · 신호 강도 판정은
전부 RPi 데몬에 맡깁니다.

판정 기준이 바뀌면 이미 찍어둔 스캔을 다시 해석할 수 있어야 하는데, 펌웨어가 미리 버리면
그 점은 영영 복구되지 않습니다. 실제로 1축 브링업에서 거리 상한 필터 때문에 먼 벽이
잘려나간 적이 있고, 그때 쓰던 상한 값 자체도 사양과 달랐습니다. `calib` 모듈을 걷어낸
것도 같은 이유입니다.

유일한 예외는 거리 폭 변환입니다. 프레임은 u24, 프로토콜은 u16(mm)이라 `lidar_process()`
에서 `0xFFFF` 로 클램프합니다. 사양 상한 내에서는 항상 그대로 들어가며, 범위를 넘는 값은
센서 오류이지만 **버리지 않고** Dis Status와 함께 올려 데몬이 판정하게 합니다.

### 4.6 공개 함수 (Public API)

**`lidar.h`**

| 함수 | 파라미터 | 반환 | 설명 |
|---|---|---|---|
| `lidar_init` | `UART_HandleTypeDef *huart` | `void` | 드라이버 초기화, 큐 리셋, 수신 인터럽트 최초 등록 |
| `lidar_on_rx_cplt` | `UART_HandleTypeDef *huart` | `void` | 1바이트 수신 완료 콜백. 상태머신 · 파싱 · 각도 래치 · 큐 push |
| `lidar_on_error` | `UART_HandleTypeDef *huart` | `void` | UART 에러 콜백. 플래그 클리어 · 재동기화 · 재기동 |
| `lidar_process` | – | `void` | **메인루프에서 매 바퀴 호출.** 큐를 비우며 `scan_submit_sample()` 호출 |
| `lidar_get_distance_mm` | – | `uint16_t` | 최신 거리값(mm). **스캔 경로와 무관한 조회/디버그용** |
| `lidar_get_frame_count` | – | `uint32_t` | 체크섬 통과 프레임 수 |
| `lidar_get_csum_errors` | – | `uint32_t` | 체크섬 불일치 수 |
| `lidar_get_queue_drops` | – | `uint32_t` | 큐가 차서 버린 샘플 수 |
| `lidar_get_rx_bytes` | – | `uint32_t` | USART6로 들어온 총 바이트(파싱 이전) |
| `lidar_get_uart_diag` | `uint8_t*, uint32_t*, uint32_t*` | `void` | 재무장 결과 / HAL RxState / ErrorCode |
| `lidar_get_last_frame` | `lidar_frame_t *out` | `bool` | 마지막 유효 프레임 스냅샷(진단용) |

**`lidar_parser.h`**

| 함수 | 파라미터 | 반환 | 설명 |
|---|---|---|---|
| `lidar_parser_is_header` | `uint8_t byte` | `bool` | 헤더 바이트(`0x57`) 여부 |
| `lidar_parser_is_func_mark` | `uint8_t byte` | `bool` | Function Mark(`0x00`) 여부 |
| `lidar_parser_parse` | `const uint8_t *buf, lidar_frame_t *out` | `bool` | 16바이트 패킷의 체크섬 검증 후 **전 필드**를 `out` 에 채움. 체크섬 외의 이유로는 실패하지 않음 |

```c
typedef struct {                /* 가공하지 않은 원본 값 */
    uint32_t device_time_ms;    /* 라이다 자체 시계             */
    uint32_t d_mm;              /* 24비트라 uint32 로 받는다    */
    uint16_t signal_strength;
    uint8_t  dis_status;
    uint8_t  range_precision;
} lidar_frame_t;
```

---

## 5. 상행 계약 (`proto_scan_point`)

`lidar_process()` 가 꺼낸 샘플은 `scan_submit_sample()` 을 거쳐 `CMD_SCAN_DATA`(18B)로
RPi에 올라갑니다. `scan` 은 **스윕 구간(`SC_SWEEP`)의 점만** 상행합니다 — 줄 끝 정지나
팬 이동 중의 점은 격자에 넣을 각도가 아니라 같은 각도에 중복만 만들기 때문입니다.

| 필드 | 출처 |
|---|---|
| `pan_ddeg` / `tilt_ddeg` | 프레임 완성 시점의 래치 각도 (0.1°) |
| `d_mm` | 프레임 거리 (u24 → u16 클램프) |
| `signal_strength` | **F2 P 원본 그대로** (정규화하지 않음) |
| `device_time_ms` | **F2 P 원본 시계** |
| `stm_ts_ms` | 래치 시각 (STM32 HAL tick) |
| `dis_status` / `range_precision` | **F2 P 원본 그대로** |

`signal_strength` 는 calibrated reflectivity 가 아니므로 **재질 판별에 단독 사용 금지**
입니다(`shared/protocol.h` 계약 주석).

---

## 6. UART 에러 복구 (`lidar_on_error`)

HAL은 프레이밍(Framing)/오버런(Overrun)/패리티 에러 발생 시 내부적으로 UART 수신을
중단시킵니다. 이를 방치하면 **에러 1회로 라이다 드라이버가 영구히 멈추므로**,
`main.c` 의 `HAL_UART_ErrorCallback()` 에서 반드시 `lidar_on_error()` 를 호출해 에러 플래그
클리어 및 수신 재기동을 수행해야 합니다.

```c
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
  uart_rpi_on_error(huart);
  lidar_on_error(huart);   // USART6(라이다) 에러 복구
}
```

`lidar_on_error()` 는 `__HAL_UART_CLEAR_PEFLAG()` 로 플래그를 지우고 `g_idx` 를 리셋한 뒤
`HAL_UART_Receive_IT()` 로 재무장합니다.

> **주의**: 워치독(IWDG)은 이 정지와 무관하게 계속 정상 급여(refresh)되므로, **라이다만
> 조용히 멈춰 있는 상황이 겉으로 드러나지 않습니다.** 7절의 진단 카운터가 그 감지 수단입니다.

---

## 7. 진단 — "라이다가 안 온다"를 원인별로 가르기

1축 브링업에서 원인을 좁히는 데 하루가 걸렸습니다. 아래 조합을 보면 1분 안에 갈립니다.

| 관측 | 원인 |
|---|---|
| `bytes=0` | 물리 계층. 배선(TX/RX 뒤바뀜) · GND · 라이다 전원 |
| `bytes>0`, `frames=0` | 보레이트 불일치, 또는 출력 모드가 NLink가 아님 |
| `frames>0`, `csum_err` 도 증가 | 전기적으로는 닿는데 신호가 지저분. 선 길이 · 간섭 · 접촉 불량 |
| `frames` 증가, `drops` 증가 | 메인루프 지연으로 큐(8칸=80ms) 넘침. 라이다 문제 아님 |
| `frames` 증가, `drops=0` | 라이다 정상. 문제는 다른 곳 |

`rx_bytes` 카운터가 없으면 1행과 2행이 구분되지 않아 추가했습니다.

수신이 아예 기동하지 않는 경우는 `lidar_get_uart_diag()` 로 봅니다.

| 값 | 의미 |
|---|---|
| `rearm_rc` | 마지막 `HAL_UART_Receive_IT` 반환값. 0=OK, 2=BUSY(**수신 미기동**) — 한 번 실패하면 이후 수신이 영영 되지 않으므로 `bytes=0` 의 유력 원인 |
| `rx_state` | HAL `RxState`. `0x62`(BUSY_RX)가 정상 수신대기, `0x22`(READY)면 미대기 |
| `err_code` | `ErrorCode`. 0=정상, 8=ORE(오버런) 등 |

카운터는 모두 단조 증가하므로, 일정 주기로 두 번 읽어 **증분**을 보면 프레임 레이트와
오류율이 나옵니다. 마지막 유효 프레임의 원본 필드는 `lidar_get_last_frame()` 으로 확인합니다.

---

## 8. 정적분석 관련 메모

`App/` 은 MISRA-C:2012 게이트 대상입니다. 이 모듈의 개별 deviation 은 다음 두 가지이며,
모두 근거 주석과 함께 룰 단위로 억제합니다.

| 룰 | 위치 | 근거 |
|---|---|---|
| 8.9 | `g_rx_byte` | `HAL_UART_Receive_IT` 가 주소를 물고 있어 파일 스코프 필요 |
| 14.4 | `__HAL_UART_CLEAR_PEFLAG` | ST HAL의 `do{...}while(0U)` 관용구 |

폴더 통째 억제로 되돌리지 않습니다 — 정적분석 가이드 §2 참조.

---

## 9. 알려진 이슈 및 미해결 항목

**① 측정 거리 사양 확인 필요 (미해결)** — 팀 내에서 0.05~40m와 25m 두 값이 함께 쓰이고
있습니다. `lidar_process()` 의 u24→u16 클램프(`0xFFFF` = 65.5m)는 어느 쪽이든 정상 값을
자르지 않으므로 **동작에는 영향이 없고**, 문서 정합성 문제입니다. 데이터시트로 확정해
한쪽으로 통일하십시오.

**② Dis Status = 1 상시 관측** — 현 보드/환경에서 대부분 `1` 로 수신됩니다. 2.2절 표에
따르면 경고 수준(표준편차 15mm 초과)이므로 이 값만으로 품질을 판단하지 말고, 실측 오차가
예상보다 크면 설치 각도 · 표적 반사율 · 측정 거리를 재점검하십시오.

**③ 보정·필터는 펌웨어에 없습니다** — `calib` 모듈 삭제(`5b229cb`)로 오프셋 보정과 EMA
필터가 제거되었습니다. 원본 raw 데이터를 그대로 올리는 것이 현재 설계이며, 보정이 필요하면
**RPi 데몬 쪽에 구현**합니다. 펌웨어로 되돌리려면 4.5절의 근거를 먼저 반박해야 합니다.

---

## 10. 참고 자료

- Nooploop TOFSense-F2 P Datasheet — `ftp.nooploop.com/downloads/tofsense/TOFSense_F2_P_Datasheet_V1.0_en.pdf`
- Nooploop 공식 Support: Protocol — `support.nooploop.com/tofsense/protocol`
- Nooploop 공식 Support: Example Code — `support.nooploop.com/tofsense/example-code`
- 공식 NLink 파서 (C) — `github.com/nooploop-dev/nlink_unpack`
- 사내 문서: 정적분석 가이드, `shared/protocol.h`(통신 계약)
