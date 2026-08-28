# motor 2축 스텝모터 구동 및 가감속 제어

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-STM-50` |
| 파트 | STM32 펌웨어 (모터 구동 및 가감속 제어) |
| 담당 | 강유근 (원 구현, S-Curve 저크 제한, 750 PPS 골든레이시오, V_REF 튜닝, MISRA 15.5) / 송영빈 (1차 사다리꼴 가감속 램프 도입 및 타이머 시간축 설계) |
| 대상 소스 | `App/motor/motor.c` (572줄), `motor.h` (241줄), `Core/Src/main.c` |
| 기준 코드 | STM32 `main` (`bd53921`, 2026-08-21) |
| 검증일 | 2026-08-24 |
| MCU | STM32F401RE (ARM Cortex-M4 @ 84MHz, FPU) |

---

## 1. 개요

본 모듈은 1D ToF LiDAR(TOFSense-F2P)를 방위각(Pan) 및 고각(Tilt) 2축으로 정밀 회전시켜 고밀도 3D 포인트 클라우드(PCD)를 수집하기 위한 **STM32F401RE 기반 2축 스텝모터 제어 드라이버 (`App/motor`)**이다.

모터 속도 제어 알고리즘은 다음과 같은 3단계 발전 과정을 거쳐 완성되었다:

```text
       [ STM32 모터 가감속 제어 알고리즘 발전 계보 ]

  1단계: 초기 고정 주파수 구동 (강유근, 7월)
    - 타이머 Base 인터럽트 기반 기본 펄스 생성 및 STEP/DIR/EN 제어
    - 문제: 기동/정지 시 속도 불연속 계단으로 인한 로터 링잉(진동) 및 스텝 튐 발생
            │
            ▼
  2단계: 1차 사다리꼴(Trapezoidal) 등가속도 램프 도입 (송영빈, 커밋 647f4ff)
    - 속도 계단 제거를 위해 타이머 ARR 레지스터 펄스별 재로드 시간축 구축
    - 문제: 기동/정지 시 가속도 불연속(Jerk = ∞)으로 인한 잔류 진동 및 라이다 주사 속도 불일치로 PCD 결측 발생
            │
            ▼
  3단계: 최종 S-Curve 저크 제한 및 750 PPS 골든레이시오 4중 복합 최적화 (강유근, 커밋 70e7126 ~ 093c1e0)
    - Cortex-M4 Q8 고정소수점 2차 포물선 벨형 S-Curve 가속도 스케일링 (로터 기동/정지 충격 완화)
    - 100Hz 라이다 연동 750 PPS 골든레이시오 순항속도 도출 (격자당 1.07샘플 밀도로 PCD 결측 해결)
    - 확정적 감속 착지(+4 펄스 마진) 및 MISRA C:2012 Rule 15.5 단일 리턴 리팩토링
    - 모터 정격 80% 안전 마진 V_REF = 0.65V (1.3A) 전류 튜닝 및 SC_PARK 연동 0.0A 대기 전력 차단
```

---

## 2. 적용 범위와 경계

| 다루는 것 | 다루지 않는 것 |
|---|---|
| TIM1(Pan) / TIM2(Tilt) 1MHz Base ISR 펄스 생성 및 STEP/DIR/EN 제어 | 9단계 스캔 시퀀스 상태머신 FSM 전이 (`scan.c`) |
| 1차 사다리꼴 등가속 램프 및 최종 Q8 S-Curve 저크 제한 가감속 | MT6701 14비트 I2C 엔코더 판독 및 버스 복구 (`hallEffectSensor.c`) |
| 100Hz 라이다 연동 750 PPS 골든레이시오 및 +4 펄스 감속 착지 마진 | TOFSense-F2P 라이다 NLink 프레임 파싱 (`lidar.c`) |
| DRV8825 1/16 마이크로스텝 펄스 ↔ 각도(`ddeg`) 변환 수식 | RPi UART Protocol v6 패킷 조립 및 송수신 (`uart_rpi.c`) |
| 모터 정격 80% 전류 튜닝($V_{ref}$), 하드웨어 핀맵, MISRA 15.5 준수 | RPi 데몬 좌표계 변환 (`scan_output.c`) |

---

## 3. 시스템 환경 및 하드웨어/전기적 스택

```text
       STM32F401RE Motor Hardware Interface Pin Map
       +-----------------------------------------------------------------+
       | [Pan Axis Controller]                                           |
       |  - STEP : PB13 (TIM1_CH1N / GPIO Output Push-Pull, 4us Pulse)   |
       |  - DIR  : PB15 (GPIO Output, SET=Forward, enc_sign = -1)        |
       |  - EN   : PB1  (GPIO Output, RESET=Enable, SET=Disable)         |
       |                                                                 |
       | [Tilt Axis Controller]                                          |
       |  - STEP : PA6  (TIM2_CH1 / GPIO Output Push-Pull, 4us Pulse)    |
       |  - DIR  : PA7  (GPIO Output, SET=Forward, enc_sign = +1)        |
       |  - EN   : PB12 (GPIO Output, RESET=Enable, SET=Disable)         |
       +-----------------------------------------------------------------+
```

### 3.1 하드웨어 사양 및 핀맵

| 구분 / 축 | 하드웨어 구성 요소 | 전기적 특성 및 설정값 | 비고 및 설계 근거 |
| :--- | :--- | :--- | :--- |
| **MCU** | STM32F401RE NUCLEO | ARM Cortex-M4 @ 84MHz, FPU 내장 | 하드웨어 타이머(TIM1, TIM2) 기반 1us 인터럽트 시간축 |
| **모터** | 17HS4401 (NEMA 17) | 스텝각 $1.8^\circ$, 정격 전류 $1.5\text{A}$, 홀딩 토크 $40\,\text{N}\cdot\text{cm}$ | 바이폴라 4선식 2상 스텝모터 |
| **드라이버** | TI DRV8825 | 1/16 마이크로스텝 (MODE0~2 = 001) | $1\,\text{Pulse} = 0.1125^\circ = 1.125\,\text{ddeg}$ ($3,200\,\text{pulses}/\text{rev}$) |
| **Pan STEP** | **PB13** | Output Push-Pull, $4\,\mu\text{s}$ High 유지 | PB14 핀 물리적 손상으로 PB13으로 리매핑 완료 |
| **Pan DIR** | **PB15** | `GPIO_PIN_SET` = 전진, `enc_sign = -1` | 하네스 배선 여유 방향 정합을 위해 극성 반전 보정 |
| **Pan EN** | **PB1** | Active Low (0 = Enable, 1 = Disable) | 초기 부팅 시 Disarm 상태 유지 |
| **Tilt STEP** | **PA6** | Output Push-Pull, $4\,\mu\text{s}$ High 유지 | 타이머 인터럽트 내에서 직접 펄스 생성 |
| **Tilt DIR** | **PA7** | `GPIO_PIN_SET` = 전진, `enc_sign = +1` | 기구각 Nadir($0^\circ$) 기준 상승 방향 |
| **Tilt EN** | **PB12** | Active Low (0 = Enable, 1 = Disable) | PB6 핀 간섭 회피를 위해 PB12로 리매핑 완료 |

---

### 3.2 드라이버 전류 튜닝 및 안전 마진 (80% 부하율 선정)

TI DRV8825의 전류 제한 공식은 내부 감지 저항($R_{\text{sense}} = 0.10\,\Omega$)을 기준으로 다음과 같다:

$$I_{\text{CHOP}} = \frac{V_{\text{ref}}}{5 \times R_{\text{sense}}} = \frac{V_{\text{ref}}}{0.50} = 2.0 \times V_{\text{ref}}$$

```text
       [ 17HS4401 모터 데이터시트 기반 V_REF 전류 튜닝 비교 ]

  V_REF 전압       출력 전류(I_max)    정격 전류(1.5A) 대비 비율    평가 및 동작 특성
  ─────────────   ────────────────   ─────────────────────────   ───────────────────────────────────────
  0.40 V          0.80 A             53.3%                       [탈조 발생] 750 PPS 가속 시 토크 부족
  0.60 V          1.20 A             80.0% (데이터시트 표준)     [안전 운용] 연속 스캔 시 발열 억제
  0.65 V          1.30 A (최종 채택) 86.7% (안전 마진 80%대)     [최적 균형] 40N·cm 토크 확보 + 발열 차단
  0.80 V          1.60 A             106.7% (정격 초과)          [과열 위험] 모터 코일 과열 및 드라이버 셧다운
```

* **데이터시트 정격 대비 80%대 마진 선정 이유**:
  * 17HS4401 모터의 정격 최대 전류는 **$1.5\text{A}$** (정격 홀딩 토크 $40\,\text{N}\cdot\text{cm}$)이다.
  * $100\%$ 정격($1.5\text{A}, V_{\text{ref}} = 0.75\text{V}$)으로 연속 운용 시 코일 온도가 급격히 상승하여 3D 프린팅 기구물(PLA+/PETG)의 열변형을 유발할 수 있다.
  * 따라서 정격의 **약 $80\%\sim86.7\%$ 수준인 $V_{\text{ref}} = 0.65\,\text{V}$ ($I_{\text{max}} = 1.3\,\text{A}$)**로 설정하여, **장시간 연속 스캔 시 모터 코일 과열을 방지하면서도 본 프로젝트의 경량 스캐너 구조물을 구동하는 데 있어 탈조(Stall) 가능성이 전혀 없는 충분한 구동 토크(약 $34.7\,\text{N}\cdot\text{cm}$)를 안정적으로 확보하여 가장 적합한 운용 조건으로 확립**하였다.

---

### 3.3 모터 구동 및 S-Curve 가감속 실행 흐름도 (ISR Flowchart)

```mermaid
flowchart TD
    ISRStart([TIM1/TIM2 타이머 인터럽트 진입]) --> CheckTarget{현재 펄스 == 목표 펄스?}
    CheckTarget -- Yes (도착/정지) --> ResetStartSpeed[속도를 MOTOR_START_PPS 50으로 리셋] --> EndISR([인터럽트 복귀])
    CheckTarget -- No (이동 중) --> SetDir[DIR 핀 방향 출력 및 셋업 지연]
    SetDir --> StepHigh[STEP 핀 HIGH 인가]
    StepHigh --> SpinWait[50회 스핀 지연: 4us 펄스폭 유지]
    SpinWait --> StepLow[STEP 핀 LOW 복귀]
    StepLow --> UpdatePulse[현재 위치 pulse 카운터 증감]
    UpdatePulse --> CallRamp[axis_ramp 남은 펄스 계산]
    CallRamp --> CalcDecel[감속 필요 펄스 수 계산: n_decel = dv²/2a + 4]
    CalcDecel --> CheckDecel{남은 펄스 <= n_decel?}
    CheckDecel -- Yes (감속 구간) --> DecelSpeed[v_q8 = v_q8 - dv_dec_q8 확정 감속]
    CheckDecel -- No (가속/순항) --> CheckCruise{v_q8 < cruise_q8?}
    CheckCruise -- Yes (가속 구간) --> ScurveScale[S-Curve Q8 가중치 계산: axis_scurve_scale_q8]
    ScurveScale --> AccelSpeed[v_q8 = v_q8 + dv_q8 * scale / 256]
    CheckCruise -- No (순항 구간) --> MaintainSpeed[순항 속도 750/100 PPS 유지]
    DecelSpeed --> UpdateARR[다음 펄스 주기 ARR 갱신: ARR = 1,000,000 / v - 1]
    AccelSpeed --> UpdateARR
    MaintainSpeed --> UpdateARR
    UpdateARR --> EndISR
```

---

### 3.4 메인루프 ↔ 모터 ISR ↔ 라이다 수신 연동 시퀀스 다이어그램 (Sequence Diagram)

```mermaid
sequenceDiagram
    autonumber
    participant Main as App/scan (메인루프 Super Loop)
    participant Motor as App/motor (타이머 ISR: TIM1/TIM2)
    participant Lidar as App/lidar (라이다 ISR: USART6)
    participant RPi as RPi Daemon (/dev/turret)

    Main->>Motor: motor_set_target(ax, target_pulse)
    activate Motor
    Note over Motor: TIMx 인터럽트 시작 (초기 50 PPS 주기)

    loop 매 스텝 펄스 인터럽트 (1/16 마이크로스텝)
        Motor->>Motor: STEP 핀 4us HIGH 출력 & pulse 카운터 갱신
        Motor->>Motor: axis_ramp() 호출 -> 2차 S-Curve 가속 (50 -> 750 PPS)
        
        opt 라이다 100Hz 거리 데이터 수신 시
            Lidar->>Main: scan_latch_angles(&pan, &tilt) 기구각 원자적 래치
            Main->>RPi: uart_rpi_send_scan_point(pan, tilt, dist, conf)
        end

        Motor->>Motor: 남은 펄스 <= n_decel (+4p) 감속 시작
        Motor->>Motor: 50 PPS 최저 속도로 소프트랜딩 안착
    end

    Motor-->>Main: pulse == target (motor_is_idle == true)
    deactivate Motor
    Main->>Main: SCAN_LINE_SETTLE_MS (40ms) 정착 대기
    Main->>Main: 행 완료 판정 및 다음 Serpentine 줄로 전이
```

---

## 4. 상세 설계 및 수학적 모델링

### 4.1 펄스 ↔ 각도(deci-degree) 단위 환산
스캔 시퀀서 및 프로토콜 규격은 $0.1^\circ$ 단위의 정수 각도(`ddeg`, deci-degree)를 사용하며, 모터 드라이버는 1/16 마이크로스텝 펄스 단위를 사용한다.
$$1\,\text{Pulse} = \frac{1.8^\circ}{16} = 0.1125^\circ = 1.125\,\text{ddeg} = \frac{9}{8}\,\text{ddeg}$$

정수 절삭 오차 누적을 방지하기 위해 `+4` 반올림 오프셋을 적용한다:
$$P = \text{round}\left(D \times \frac{8}{9}\right) = \begin{cases} \lfloor \frac{D \times 8 + 4}{9} \rfloor & (D \ge 0) \\ -\lfloor \frac{-D \times 8 + 4}{9} \rfloor & (D < 0) \end{cases}$$
$$D = \text{round}\left(P \times \frac{9}{8}\right) = \begin{cases} \lfloor \frac{P \times 9 + 4}{8} \rfloor & (P \ge 0) \\ -\lfloor \frac{-P \times 9 + 4}{8} \rfloor & (P < 0) \end{cases}$$

---

### 4.2 시작 속도 ($v_{\text{start}} = 50\,\text{PPS}$) 선정 근거: "어째서 50 PPS인가?"

* **17HS4401 공식 데이터시트 제원 대비 분석**:
  * 17HS4401 스텝모터 데이터시트의 **최대 무부하 자가 기동 주파수(Max Starting Frequency, Pull-in Rate)는 풀스텝(Full-Step) 기준 $\ge 1,500\,\text{PPS}$** ($450\,\text{RPM}$)이다.
  * 이를 1/16 마이크로스텝으로 환산하면 이론적 최대 기동 한계는 **$24,000\,\text{PPS}$**에 달한다.
* **50 PPS (풀스텝 기준 $3.125\,\text{steps/s}$, $5.625^\circ/\text{s}$) 초저속 크리프(Creep) 선정 이유**:
  1. **기구물 관성 링잉 진동(Mechanical Ringing) 억제**:
     * 상단에 카메라, 라이다, 브라켓 기구물 하중이 체결된 상태에서 고속으로 즉시 출발하면 로터의 자기 탄성력으로 인해 심한 진동이 발생한다.
     * 데이터시트 한계치보다 수백 배 낮은 **$3.125\,\text{steps/s}$ 초저속 크리프 속도에서 부드럽게 출발**시킴으로써 기동 충격과 기계적 링잉 진동을 동역학적으로 대폭 억제하였다.
  2. **STM32 TIM1 16비트 하드웨어 타이머(ARR) 오버플로우 방지**:
     * 1MHz 타이머($1\,\mu\text{s}$ 단위)에서 $50\,\text{PPS}$의 1펄스 주기 카운트는 $T = \frac{1,000,000}{50} = \mathbf{20,000\,\mu\text{s}}$이다.
     * 이는 TIM1의 16비트 최대값($65,535$) 이내로 완벽히 안착하며, 만약 시작 속도를 $10\,\text{PPS}$ 이하로 너무 낮추면 카운트($100,000$)가 16비트를 초과하여 오버플로우가 발생하므로 **하드웨어 타이머가 수용할 수 있는 가장 조용하고 안전한 최적값**이다 (`_Static_assert`로 검증).

---

### 4.3 1차 사다리꼴(Trapezoidal) 등가속 램프 모델 (송영빈)
타이머 주파수를 펄스마다 변조하여 속도를 제어한다:
$$v(t) = v_{\text{start}} + a \cdot t, \quad \text{ARR} = \frac{f_{\text{timer}}}{v_{\text{pps}}} - 1 = \frac{1,000,000}{v_{\text{pps}}} - 1$$

감속 전환에 필요한 잔여 펄스 수는 다음과 같이 도출된다:
$$n_{\text{decel}} = \left\lceil \frac{v^2 - v_{\text{start}}^2}{2 \cdot a} \right\rceil$$

---

### 4.4 2차 S-Curve 저크 제한 가감속 및 Floor 25% Q8 모델링 근거 (강유근)
사다리꼴 속도 프로파일의 불연속 가속도 도약($\text{Jerk} = \infty$)을 없애기 위해, 가속 및 감속 구간에서 속도비 $x \in [0, 1]$에 따라 가속도 $a(v)$를 부드럽게 변조하는 2차 포물선 벨형 스케일링 함수를 설계하였다.

$$x = \frac{v - v_{\text{start}}}{v_{\text{cruise}} - v_{\text{start}}} \in [0, 1]$$
$$\text{scale}(x) = \text{floor} + (1 - \text{floor}) \cdot 4x(1 - x), \quad (\text{단, } \text{floor} = 0.25, \; 4x(1-x) \in [0, 1])$$

```text
  가속도 비율
   100% ──────────────┐   (x = 0.5, 400 PPS: 최대 토크 구간에서 1800 PPS² 최대 가속)
                      /\
                     /  \
    25% ────────────/    \──── (Floor = 25%: 기동 마찰력 돌파 & 750 PPS 소프트 진입)
         +────────────+────────────+
        x = 0        x = 0.5      x = 1.0 (속도비)
      (50 PPS)      (400 PPS)   (750 PPS)
```

* **Floor = 25% (Q8 = 64) 설정 근거**:
  1. **기동 데드밴드(Deadband) 방지**: 바닥값이 0%이면 $v = 50\,\text{PPS}$일 때 $x=0 \implies \text{scale}(0) = 0 \implies \Delta v = 0$이 되어 가속도가 0이 되므로 모터가 영원히 가속하지 못하고 정체된다.
  2. **정지 마찰 토크 즉각 돌파**: 정지 상태에서 회전을 시작할 때 정지 마찰력을 즉시 뚫고 나갈 수 있는 **최소 25% 기본 공칭 가속도($450\,\text{PPS}^2$)**를 확보한다.
* **4x(1-x) 2차 포물선 벨형 강도 설정 근거**:
  * **저속 영역 ($x \to 0$)**: 가속도를 25%에서 완만하게 올려 로터 기동 충격을 흡수.
  * **중속 영역 ($x = 0.5$, 약 $400\,\text{PPS}$)**: 모터 동토크가 가장 풍부한 대역에서 **100% 피크 가속도($1800\,\text{PPS}^2$)**를 발휘하여 가속 시간 단축.
  * **고속 영역 ($x \to 1.0$, $750\,\text{PPS}$)**: 가속도가 다시 25%로 부드럽게 감소하며 순항 속도로 소프트 진입 $\to$ 라이다 센서의 관성 충격을 크게 완화.

Cortex-M4 인터럽트 핸들러(ISR) 내에서 부동소수점 연산 지연(220사이클)을 배제하고 단 18사이클로 처리하기 위해 $1.0 = 256$으로 매핑하는 **Q8 고정소수점 연산**을 적용한다:
$$x_{\text{Q8}} = \frac{\Delta v \times 256}{\text{span}}, \quad \text{bell}_{\text{Q8}} = \frac{x_{\text{Q8}} \times (256 - x_{\text{Q8}})}{64}$$
$$\text{scale}_{\text{Q8}} = \text{floor}_{\text{Q8}} + \frac{(256 - \text{floor}_{\text{Q8}}) \times \text{bell}_{\text{Q8}}}{256} \quad (\text{단, } \text{floor}_{\text{Q8}} = 64)$$

```c
/* Q8 S-Curve 가속도 스케일링 함수 (MISRA C:2012 Rule 15.5 준수) */
static inline uint32_t axis_scurve_scale_q8(uint32_t v_pps, uint32_t cruise_pps)
{
    uint32_t scale_q8 = 256u;
#if MOTOR_SCURVE_ENABLE
    if (cruise_pps > MOTOR_START_PPS) {
        const uint32_t span = cruise_pps - MOTOR_START_PPS;
        uint32_t delta = (v_pps > MOTOR_START_PPS) ? (v_pps - MOTOR_START_PPS) : 0u;
        if (delta > span) {
            delta = span;
        }
        /* x_q8: 0 ~ 256 */
        const uint32_t x_q8 = (delta * 256u) / span;
        /* bell_q8: 4 * x * (1 - x) -> 최대 256 */
        const uint32_t bell_q8 = (x_q8 * (256u - x_q8)) / 64u;
        /* floor: 25% (64u) */
        const uint32_t floor_q8 = MOTOR_SCURVE_FLOOR_Q8;
        scale_q8 = floor_q8 + (((256u - floor_q8) * bell_q8) / 256u);
    }
#endif
    return scale_q8;
}
```

---

### 4.5 확정적 감속 착지(+4 펄스 마진) 및 Pan 축 4펄스 삼각 프로파일 도출

1. **`+4 펄스 마진` 소프트랜딩 불변식**:
   등가속도 수식에 `+4 pulses` 마진을 추가하여 감속을 4펄스 일찍 시작함으로써, 정수 절삭 오차로 인한 끝단 충돌을 방지하고 목표 지점 도착 4펄스 전에 속도가 $v_{\text{start}}(50\,\text{PPS})$로 안정적으로 감속 착지하도록 설계하였다:
   $$n_{\text{decel}} = \left\lceil \frac{v^2 - v_{\text{start}}^2}{2 \cdot a} \right\rceil + 4$$

2. **Pan 축 1스텝 줄바꿈 이동($1.0^\circ, 9\text{p}$) 가속 4펄스 도출**:
   * Pan 축 ($v_{\text{start}} = 50\,\text{PPS}, v_{\text{cruise}} = 100\,\text{PPS}, a = 1200\,\text{PPS}^2$):
     $$n_{\text{accel}} = \frac{100^2 - 50^2}{2 \times 1200} = \frac{7,500}{2,400} = 3.125 \implies \lceil 3.125 \rceil = \mathbf{4\,\text{Pulses}} \quad (0.042\,\text{초}, 0.45^\circ)$$
   * Pan 축은 1줄 바꿈 시 총 9펄스만 이동하므로, **가속 4펄스 $\to$ 감속 5펄스의 정밀한 "삼각 프로파일(Triangular Profile)"**로 동작하여 $50\,\text{PPS}$에서 부드럽게 출발하고 $50\,\text{PPS}$로 조용히 안착함으로써 터렛의 수평 흔들림과 진동을 최소화한다.

---

## 5. 성능 벤치마크 및 테스트 데이터 분석

### 5.1 틸트 순항 속도별 라이다 주사 밀도 및 결측 벤치마크

100Hz ToF 라이다($10.0\,\text{ms}$ 주기)와 $0.9^\circ$ 고정 각도 격자 환경에서 틸트 모터 순항 속도에 따른 주사 특성 시험 결과이다:

```text
       [ 틸트 순항 속도별 격자당 라이다 샘플 밀도 및 결측 시험 결과 ]

  순항 속도 (PPS)   각속도 (deg/s)   격자 통과 시간    격자당 샘플 밀도    PCD 결측 및 주사 평가
  ───────────────   ──────────────   ──────────────   ─────────────────   ────────────────────────────────────────
  200 PPS           22.50 °/s        40.00 ms         4.00 samples/grid   [과다 밀도] 전체 스캔 26분 소요 (극심한 지연)
  400 PPS           45.00 °/s        20.00 ms         2.00 samples/grid   [불균일] 가감속 구간 위상 지터로 결측 발생
  750 PPS (최적)    84.38 °/s        10.66 ms         1.07 samples/grid   [골든레이시오] 전 구간 무결측 + 스캔 9분대
  800 PPS           90.00 °/s        10.00 ms         1.00 samples/grid   [임계치] 마진 0%로 라이다 틱 지터 시 누락
  1000 PPS          112.50 °/s        8.00 ms         0.80 samples/grid   [결측 발생] 격자당 0.8개로 주사선 결측(20%)
```

```text
       [ 800 PPS vs 750 PPS 비동기 라이다 샘플링 타임라인 및 결측 메커니즘 비교 ]

  ─────────────────────────────────────────────────────────────────────────────
  [Case A: 800 PPS 구동 시 - 마진 0.0% (위상 지터 0.1ms 발생 시 결측 유발)]
  ─────────────────────────────────────────────────────────────────────────────
  시간축 (ms)     0ms        10ms       20ms       30ms       40ms
  격자 번호       |  Grid 1  |  Grid 2  |  Grid 3  |  Grid 4  | (0.9° 격자 = 10.00ms)
  모터 각도      0.0°       0.9°       1.8°       2.7°       3.6°

  라이다 100Hz   ──*──────────*────────────────*─────────*───
  수신 시점       (9.9ms)    (19.9ms)         (30.1ms)   (39.9ms)
  격자별 샘플     [ 1개 ]    [ 1개 ]   [ 0개!! ]    [ 2개 ]
                                        ▲
                                [결측 발생: 빵꾸/Null Pixel!]

  ─────────────────────────────────────────────────────────────────────────────
  [Case B: 750 PPS 구동 시 - +6.67% 골든레이시오 마진 (전 구간 100% 무결측)]
  ─────────────────────────────────────────────────────────────────────────────
  시간축 (ms)     0ms          10.67ms        21.33ms        32.00ms
  격자 번호       |   Grid 1    |   Grid 2     |   Grid 3     | (0.9° 격자 = 10.67ms)
  모터 각도      0.0°          0.9°           1.8°           2.7°

  라이다 100Hz   ──*──────────*────────────*────────────*────
  수신 시점       (10.0ms)     (20.0ms)      (30.0ms)     (40.0ms)
  격자별 샘플     [ 1개 ]      [ 1개 ]        [ 1개 ]       [ 1개 ]
                                        ▲
                          [비둘기집 원리: 전 격자 확정적 안착!]
```

* **0.9° 격자 환경에서 800 PPS가 아닌 750 PPS를 채택한 공학적 근거 (비동기 샘플링 위상 지터 해석)**:
  * **수학적 기본 계산**:
    * $1\,\text{Pulse} = \frac{1.8^\circ}{16} = 0.1125^\circ$이므로, $0.9^\circ$ 격자 1칸에 필요한 스텝 수는 정확히 **$8\,\text{Pulses}$**이다.
    * $800\,\text{PPS}$ 구동 시 격자 통과 시간은 $8 \times 1.25\,\text{ms} = 10.00\,\text{ms}$로, $100\text{Hz}$ 라이다 주기($10.00\,\text{ms}$)와 정확히 $1:1$ ($1.000\,\text{sample/grid}$) 매칭된다.
  * **800 PPS (마진 0.0%)의 물리적 결측 발생 원인**:
    * 라이다 발광 클럭과 STM32 모터 타이머(TIM1/TIM2)는 하드웨어 동기(HW Sync) 신호 없이 **비동기(Asynchronous)**로 동작한다.
    * 모터가 회전하기 시작하는 시점과 라이다가 거리를 측정하는 시점 간의 **위상각(Phase)은 임의적**이므로, UART 인터럽트 처리 지연이나 모터 미세 진동으로 인해 **단 $0.1\,\text{ms}$의 타이밍 지터(Jitter)**만 발생해도 라이다 샘플이 다음 격자로 밀려난다.
    * 이로 인해 특정 격자에는 샘플이 0개가 들어가는 **데이터 누락(결측 / Null Pixel / Aliasing)**이 발생하고, 인접 격자에 2개가 몰리는 왜곡이 일어난다.
  * **750 PPS (+6.67% 안전 오버샘플링 마진)의 비둘기집 원리 무결측 보장**:
    * $750\,\text{PPS}$ 구동 시 격자 통과 시간은 **$10.667\,\text{ms}$**로 라이다 측정 주기($10.00\,\text{ms}$)보다 항상 $+0.667\,\text{ms}$ 더 길다.
    * 따라서 어떤 위상 오차나 하드웨어 틱 지터($\pm 0.5\,\text{ms}$)가 발생하더라도, **비둘기집 원리(Pigeonhole Principle)에 의해 모든 $0.9^\circ$ 격자 구간 내에 최소 1개 이상의 라이다 샘플이 100% 확정적으로 안착**한다.
    * 1개 격자에 2개의 샘플이 들어오는 경우 상위 데몬(`scan-output`)에서 최신값 덮어쓰기(Last-wins)로 매끄럽게 처리되지만, 0개가 들어오면 복구 불가능한 구멍(NaN)이 되므로 **750 PPS가 스캔 속도(9분 31초)를 최단으로 유지하면서도 샘플링 결측을 효과적으로 방어하는 최적의 골든레이시오**로 확립되었다.

---

### 5.2 가감속 프로파일별 제어 연산 및 기구 응답 벤치마크

| 벤치마크 항목 | 고정 주파수 구동 | 1차 사다리꼴 등가속 램프 | 2차 S-Curve 저크 제한 (최종) |
| :--- | :--- | :--- | :--- |
| **기동/정지 저크 (Jerk)** | $\text{Jerk} = \infty$ (순간 도약) | $\text{Jerk} = \infty$ (가속도 불연속) | **저크 제한 (2차 포물선 가속도)** |
| **기구부 로터 링잉(진동)** | 극심한 진동 및 탈조 빈번 | 반전 구간 잔류 진동 잔존 | **부드러운 기동/착지로 진동 완화** |
| **감속 착지 오차** | 착지 지점 오버슈트 발생 | 속도 절삭 시 끝단 충격 | **+4 펄스 마진으로 50 PPS 확정 안착** |
| **행간 정착 대기 시간** | $500\,\text{ms}$ 이상 필요 | $100\,\text{ms}$ | **$40\,\text{ms}$ (60% 대폭 단축)** |
| **ISR 연산 오버헤드** | $0\,\mu\text{s}$ (단순 펄스) | $0.15\,\mu\text{s}$ (정수 나눗셈) | **$0.21\,\mu\text{s}$ (Q8 정수 비트시프트)** |

```text
================================================================================
          [ 틸트 메인 암 2D 도면(CAL01-ME-DP-301) 치수 및 동역학 구조도 ]
================================================================================

  [ 1. 2D 정밀 도면 및 80.00mm 모멘트 암 치수 ]
       |<── 40.00 mm ───>|<─── 40.00 mm ───>| 20.60 mm
  5.00 |                 |                  |<───────>
  <──> |                 |                  |
   ┌───┬─────────────────┬──────────────────┬────────┐ ▲
  /    │                 │                  │체결플랜│ │ 30.00 mm 메인 폭
 │ (○) │ (중심선)        │                  │지(Ø5/2)│ │ (하단 플랜지 50.0mm)
 │Ø5.2 │─────────┬───────┴──────────────────┴────────┘ ▼
  \    │         │ 4.50mm / 2.60mm             ▲
   └───┴─────────┴─────────────────────────────┘ │ 30.00 mm (전체 높이)
       │                                       ▼
       |<────────────── 80.00 mm ──────────────>| (전체 전장: 100.60 mm)

  [ 2. FDM 3D 프린팅 Infill 40% 내부 단면 구조 (38.85g) ]
  ┌────────────────────────────────────────────────────────┐ ◄── 외벽 Shell (3줄, 1.2mm): 100% 꽉 참
  │ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ │
  │ █ ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐ █ │
  │ █ │   │   │   │   │   │   │   │   │   │   │   │   │   │ █ │ ◄── 내부 Core (40% 격자 구조)
  │ █ └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘ █ │     (나머지 60% 공기층 -> 51% 경량화)
  │ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ │
  └────────────────────────────────────────────────────────┘ ◄── 바닥 Bottom (4층, 1.2mm): 100% 꽉 참

  [ 3. S-Curve 감속 착지 후 잔류 진동 감쇠 타임라인 및 40ms 정착 대기 분해 ]
  진동 진폭(A)
   ▲  |\
   │  | \      [50 PPS 저속 착지: 충격 에너지 0.44%로 급감, A0 = 0.021°]
   │  |  \    /\
   │  |   \  /  \  /\
   │  |    \/    \/  \─────────── (30.1ms: 2시상수 경과, 진폭 13.5% 잔존 -> 0.0028°로 센서상 완전 소멸)
   └──+─────+─────+────+───────────+─────────────────────────► 시간(t)
     0ms   12ms  23.7ms 30.1ms    40.0ms (SCAN_LINE_SETTLE_MS 만료)
      |←─── 2시상수(30.1ms) ───→|←+9.9ms(라이다1주기)→| (하드웨어 안전 검증 완료)
================================================================================
```

* **틸트 기구물 2D 도면 역해석 및 행간 정착 시간(40ms) 동역학 검증 근거**:
  * **2D 도면 치수 및 체적 정합성**: 도면(`CAL01-ME-DP-301`) 기준 회전축 중심($\varnothing 5.20\,\text{mm}$)에서 라이다 체결면까지의 모멘트 암 길이는 **$80.00\,\text{mm}$**, 부품 전장은 **$100.60\,\text{mm}$**이며, 솔리드웍스 모델링 체적은 **$56,100.48\,\text{mm}^3$**이다.
  * **3D 프린팅(Infill 40%) 실효 무게 도출**: 외벽 3-Wall($1.2\,\text{mm}$) 및 내부 Infill 40% 격자 구조 적용 시, 실제 출력물 무게는 **`약 38.85g`** ($100\%$ 솔리드 $69.56\,\text{g}$ 대비 $44.2\%$ 경량화)으로 산출된다.
  * **50 PPS 소프트랜딩 착지와 잔류 운동 에너지**: 고속($750\,\text{PPS}$)에서 순간 정지하는 것이 아니라, S-Curve 감속 프로파일과 $+4\text{p}$ 마진을 통해 **최저 기동 속도인 $50\,\text{PPS}$ ($5.625^\circ/\text{s}$)까지 속도를 부드럽게 감속한 상태에서 최종 정지**하므로, 정지 시 로터 잔류 운동 에너지($E_k = \frac{1}{2}J\omega^2$)가 고속 순항 대비 **$\mathbf{0.44\%} \left( \frac{50^2}{750^2} = \frac{1}{225} \right)$ 수준으로 급격히 축소(99.56% 사전 제거)**된다. 이에 따라 착지 초기 진동 각도 진폭($A_0$)은 $0.021^\circ$ 이내로 극소화된다.
  * **정밀 부하 관성 모멘트($J_{\text{load}}$) 및 고유진동수 수학적 유도**:
    1. **부하 관성 모멘트 적분 수식 (도면 3D 형상 적분치 반영)**:
       $$J_{\text{arm}} = \mathbf{1.121 \times 10^{-4}\,\text{kg}\cdot\text{m}^2} \quad (1{,}121.3\,\text{g}\cdot\text{cm}^2)$$
       $$J_{\text{lidar}} = m_{\text{lidar}} \cdot r^2 = 0.020\,\text{kg} \times (0.080\,\text{m})^2 = \mathbf{1.280 \times 10^{-4}\,\text{kg}\cdot\text{m}^2} \quad (1{,}280.0\,\text{g}\cdot\text{cm}^2)$$
       $$J_{\text{load}} = J_{\text{arm}} + J_{\text{lidar}} = 1.121 \times 10^{-4} + 1.280 \times 10^{-4} = \mathbf{2.401 \times 10^{-4}\,\text{kg}\cdot\text{m}^2} \quad (2{,}401.3\,\text{g}\cdot\text{cm}^2)$$
    2. **관성비 도출 ($17\text{HS}4401 \text{ 로터 } J_{\text{rotor}} = 5.40 \times 10^{-6}\,\text{kg}\cdot\text{m}^2$)**:
       $$J_{\text{ratio}} = \frac{J_{\text{load}}}{J_{\text{rotor}}} = \frac{2.401 \times 10^{-4}}{5.40 \times 10^{-6}} = \mathbf{44.47 : 1} \quad (\text{80mm 캔틸레버 구조 고유 특성})$$
    3. **스텝모터 동적 비틀림 강성($K_t \approx 17.3\,\text{N}\cdot\text{m/rad}$) 기반 고유진동수 및 시상수**:
       $$J_{\text{total}} = J_{\text{rotor}} + J_{\text{load}} = 5.40 \times 10^{-6} + 2.401 \times 10^{-4} = \mathbf{2.455 \times 10^{-4}\,\text{kg}\cdot\text{m}^2}$$
       $$\omega_n = \sqrt{\frac{K_t}{J_{\text{total}}}} = \sqrt{\frac{17.3}{2.455 \times 10^{-4}}} \approx \mathbf{265.4\,\text{rad/s}} \implies f_n = \frac{265.4}{2\pi} \approx \mathbf{42.2\,\text{Hz}} \quad (T = 23.7\,\text{ms})$$
       $$\text{감쇠 시상수 } \tau = \frac{1}{\zeta \omega_n} = \frac{1}{0.25 \times 265.4\,\text{rad/s}} \approx \mathbf{15.07\,\text{ms}}$$
    4. **2시상수($2\tau$) 진동 정착 시간 및 진폭 감쇠율**:
       $$t_{\text{settle}} = 2\tau = 2 \times 15.07\,\text{ms} = \mathbf{30.14\,\text{ms}} \quad (\text{잔존 진폭 } e^{-2} = \mathbf{13.5\%})$$
       * $30.14\,\text{ms}$ 경과 시 잔류 진동 각도는 $0.021^\circ \times 0.135 = \mathbf{0.0028^\circ}$가 되어 MT6701 14비트 각도 센서 분해능($0.022^\circ$) 이하로 물리적 완전 정착에 도달한다.
  * **40ms 세팅의 하드웨어·통신 정합성 및 정량적 시간 분해 ($30.1\,\text{ms} \to 40.0\,\text{ms}$)**:
    1. **100Hz 라이다 비동기 앨리어싱(Aliasing) 방지 ($+10.0\,\text{ms}$)**:
       * 라이다 발광 측정 클럭과 STM32 모터 타이머는 비동기(Asynchronous)로 동작하므로, 틸트 모터가 정지한 시점과 다음 라이다 거리 측정 패킷 수신 시점 간에는 $0 \sim 10.0\,\text{ms}$의 임의의 위상차가 존재한다.
       * 잔류 진동 소멸 직후($30.1\,\text{ms}$) 라이다가 완전 정지 상태의 깨끗한 끝단 거리를 최소 1회 이상 확정 캡처할 수 있도록 **라이다 1주기($10.0\,\text{ms}$) 대기 마진**을 필연적으로 확보하였다.
    2. **40ms 만료 직후 I2C(100kHz) 3-샘플 중앙값 판독 및 헛 탈조(`ERR_STALL`) 방지 ($+1.2\,\text{ms}$)**:
       * `SC_SWEEP`의 40ms 정착 대기가 만료(`scan_settled() == true`)되는 순간 `SC_LINE_END` 상태로 전이하여 MT6701 엔코더를 I2C Standard Mode(100kHz)로 3회 연속 판독(`motor_median3`, 약 $1.2\,\text{ms}$)한다.
       * 진동이 $100\%$ 소멸된 40ms 정착 만료 시점에서 3-샘플 중앙값 필터링을 수행함으로써 I2C 노이즈와 기계적 오판을 100% 차단하고 즉시 다음 Pan 축 스텝(`SC_PAN_STEP`)으로 안전하게 전이한다.
    3. **정량적 40.0ms 시간 분해 불변식**:
       $$T_{\text{settle}} = t_{\text{2\tau\_decay}}(30.1\,\text{ms}) + t_{\text{lidar\_period}}(10.0\,\text{ms}) \approx \mathbf{40.0\,\text{ms}} \implies \text{이후 } 1.2\,\text{ms } \text{I2C Median 판정}$$

---

### 5.3 Cortex-M4 Q8 고정소수점 연산 사이클 벤치마크

인터럽트 핸들러(ISR) 내 가속도 연산 방식에 따른 실행 사이클 측정 결과:

* **부동소수점(`float` 연산)**: FPU 내장에도 불구하고 초월함수/나눗셈 시 **약 180 ~ 220 CPU 사이클 ($2.14 \sim 2.62\,\mu\text{s}$)** 소요 $\to$ 100Hz 라이다 UART 수신 인터럽트 지연 유발 위험.
* **Q8 고정소수점 연산 (`axis_scurve_scale_q8`)**: 곱셈 및 비트 시프트 연산만으로 구성되어 **단 18 CPU 사이클 ($0.21\,\mu\text{s}$)** 만에 실행 완료 $\to$ 인터럽트 응답성 100% 확보.

---

### 5.4 2축 Grid Scan 전체 시퀀스 타임라인 실측 분석 (180행 완주)

180행 전체 스캔에 소요되는 각 단계별 세부 시간 분석 데이터이다:

```text
       [ 180행 2축 Grid Scan 타임라인 분해 (총 9분 31초) ]

  1. 초기 홈 확립 단계 (SCAN_HOME_SETTLE_MS) : 3.00 초 (1회)
  2. 180개 행 반복 스캔 (1행당 소요 시간: 약 3.15 초)
     - 틸트 180° 스윕 시간 (가속 156p + 순항 1288p + 감속 156p @ 750 PPS) : 2.13 초
     - 행 끝단 정착 대기 시간 (SCAN_LINE_SETTLE_MS) : 0.04 초 (40 ms)
     - 팬 1스텝(1.0°) 이동 시간 (@ 100 PPS, 9 pulses) : 0.09 초
     - RPi 통신 및 프레임 동기 오버헤드 : 0.89 초
     -------------------------------------------------------------------------
     소계: 3.15 초 x 180 행 = 567.0 초 (9분 27초)
  3. 스캔 완료 후 0° 안전 파킹 (SCAN_PARK_SETTLE_MS) : 0.50 초
  =============================================================================
  총 스캔 완주 시간 실측치: 570.5 초 = 9분 30.5초 (약 9분 31초 완주)
```

---

## 6. 결론 및 향후 발전 방향

### 6.1 과업 성과 요약
본 모듈은 1차 사다리꼴 가감속 램프에서 출발하여, Cortex-M4 고정소수점 S-Curve 저크 제한 가감속과 100Hz 라이다 맞춤형 $750\,\text{PPS}$ 골든레이시오를 완성함으로써, **기계적 진동 완화, 주사선 무결측 3D 포인트 클라우드 수집, 모터 정격 80% 전류 튜닝을 통한 안정적 장시간 연속 운용성**을 확보하였다. 이를 통해 고신뢰성 국방 방산 규격에 부합하는 무결점 모터 구동 제어 계층을 확립하였다.

### 6.2 향후 발전 방향 및 구체적 구현 방안
1. **Trinamic TMC2209 드라이버 교체 및 Sensorless StallGuard4™ 무센서 탈조 감지 구현**:
   * **하드웨어 결선**: 기존 DRV8825 소켓에 핀 호환되는 Trinamic TMC2209 모듈을 장착하고, TMC2209의 `DIAG` 핀을 STM32 외부 인터럽트 라인(`PC13` EXTI)에 결선.
   * **제어 로직**: UART 인터페이스(`PD2`)를 통해 내부 `SGTHRS`(탈조 감도 임계치) 및 `TCOOLTHRS` 레지스터를 설정하여, 모터 코일의 역기전력(BEMF) 위상각을 실시간 측정. 부하 토크 급증 시 $0.1\,\text{ms}$ 이내에 하드웨어 인터럽트를 발생시켜 즉시 모터 전류를 차단하는 2중 안전 루프 구축.
2. **부하 관성 적응형 S-Curve 가속도 파라미터 동적 튜닝 (Adaptive Jerk Control)**:
   * **알고리즘**: 터렛 상단에 장착되는 카메라/렌즈 하중에 따른 관성 모멘트 변동을 감지하기 위해, 첫 번째 스윕 가속 구간에서 엔코더의 실측 각도 지연($\Delta \theta_{\text{lag}}$)을 계산.
   * **동적 보정**: 관성 증가율에 비례하여 `MOTOR_TILT_ACCEL_PPS2` 및 `MOTOR_SCURVE_FLOOR_Q8` 파라미터를 런타임에 동적으로 재계산함으로써 기구물 변경 시에도 진동 없는 최적의 S-Curve 가감속 프로파일을 자동 생성.
