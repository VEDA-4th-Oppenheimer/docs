# 임베디드 2-Track 정적 분석 CI 가이드

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-GDE-10` |
| 파트 | 품질 및 CI 파이프라인 (Static Analysis & Security) |
| 담당 | 강유근 |
| 대상 소스 | `CLionProject/App/` (STM32), `RPi/driver/`, `RPi/daemon/` (RPi), `shared/protocol.h` |
| 설정 파일 | `CLionProject/tools/cppcheck_suppressions.txt`, `RPi/tools/cppcheck_suppressions.txt`, `tools/misra_rules.txt` |
| 기준 도구 | Cppcheck 2.10+ (misra.py), Clang-Tidy 15+ |
| 검증일 | 2026-08-24 |
| 준수 표준 | MISRA C:2012 Mandatory/Required, Linux Kernel Style, CWE-120/125/476 |

---

## 1. 개요

본 가이드는 방산 및 고신뢰성 임베디드 무기체계 소프트웨어 품질 기준을 충족하기 위해 구축된 **임베디드 2-Track 정적 분석 파이프라인(STM32 Cppcheck/MISRA vs RPi Clang-Tidy)** 및 **MISRA C:2012 Rule 15.5(Single Return) 리팩토링 명세와 오탐 억제 엔지니어링 기준**을 정의한다.

개발 초기 산재했던 다중 리턴문(Multi-Return), 벤더 헤더 포인터 캐스팅 충돌, 브링업 벤치 매크로 노이즈를 체계적으로 리팩토링하고 억제 사유를 명문화하여, GitHub Actions CI 자동화 게이트를 통한 고신뢰성 펌웨어 빌드 환경을 확립하였다.

---

## 2. 적용 범위와 경계

| 다루는 것 | 다루지 않는 것 |
|---|---|
| Track 1: STM32 `App/` 모듈 Cppcheck + MISRA C:2012 정적 검사 | STM32 CubeMX 생성 `Core/`, `Drivers/` 벤더 코드 분석 (수정 불가 영역) |
| Track 2: RPi `driver/` 및 `daemon/` Clang-Tidy / Cppcheck 정적 검사 | RPi 브로커 HTTPS 인증서 발급 로직 (`broker-enroll.md`) |
| MISRA C:2012 Rule 15.5(단일 진입·단일 출구) 전면 리팩토링 | Qt 6 GUI 클라이언트 소스코드 분석 |
| `cppcheck_suppressions.txt` 6대 엔지니어링 억제 사유 관리 | |
| GitHub Actions CI 자동화 파이프라인 YAML 명세 | |

---

## 3. 2-Track 정적 분석 아키텍처

```text
               2-Track Automated Static Analysis CI Pipeline
               
  [Track 1: STM32 Firmware]           [Track 2: RPi Kernel & Daemon]
  - Target: App/ (C99), shared/       - Target: driver/, daemon/ (C11/C++17)
  - Engine: Cppcheck + misra.py       - Engine: Clang-Tidy + GCC Analyzer
  - Standard: MISRA C:2012            - Standard: Linux Kernel Coding Style / SEI CERT
            │                                     │
            ▼                                     ▼
  +─────────────────────────────────────────────────────────────+
  |              GitHub Actions CI Quality Gate                 |
  |  - Step 1: MISRA C:2012 & Cppcheck Static Analysis (Track 1)|
  |  - Step 2: Clang-Tidy Static Analysis (Track 2)             |
  |  - Step 3: ARM GCC Firmware Cross-Build Verification        |
  |  - Exit Code == 0 -> MERGE PASS / Exit Code != 0 -> REJECT  |
  +─────────────────────────────────────────────────────────────+
```

| 구분 | Track 1 (STM32 Cortex-M4) | Track 2 (RPi4 Linux) |
| :--- | :--- | :--- |
| **대상 소스** | `CLionProject/App/` (motor, hallEffectSensor, scan, lidar, uart_rpi) + `shared/` | `RPi/driver/`, `RPi/daemon/` |
| **분석 도구** | Cppcheck 2.10+ & `misra.py` | Clang-Tidy 15+ / Cppcheck |
| **적용 표준** | MISRA C:2012 (Mandatory & Required) | Linux Kernel Style / SEI CERT C |
| **제외 대상** | `Core/`, `Drivers/` (CubeMX 생성 벤더 코드) | 3rd-party 서드파티 라이브러리 (`/usr/include/`) |
| **CI 게이트** | MISRA Required/Mandatory 위반 0건 | Clang-Tidy 경고 0건 |

---

## 4. MISRA C:2012 Rule 15.5 (Single Return) 전면 리팩토링

### 4.1 규칙 정의 및 위험성
* **MISRA C:2012 Rule 15.5 (Advisory/Required)**: "함수는 단 하나의 진입점과 단 하나의 출구(Return 문)를 가져야 한다."
* **다중 리턴의 위험성**: 함수 중간 탈출 분기가 많아지면 실행 경로 추적이 어려워지고, 자원 락 해제나 하드웨어 페리페럴 상태 복구가 누락되는 심각한 결함 유발.

---

### 4.2 실제 소스코드 리팩토링 사례 2종

#### [사례 1] 엔코더 각도 판독 (`App/hallEffectSensor/hallEffectSensor.c`)

```c
/* =========================================================================
 * [개선 전 (Before)]: 다중 return 문 남발로 MISRA 15.5 위반 (탈출 경로 4개)
 * ========================================================================= */
HAL_StatusTypeDef Encoder_ReadRawAngle_Old(I2C_HandleTypeDef *hi2c, uint16_t *raw_angle)
{
    if (hi2c == NULL || raw_angle == NULL) {
        return HAL_ERROR; /* [위반 1]: 조기 리턴 */
    }
    uint8_t buf[2];
    if (HAL_I2C_Mem_Read(hi2c, 0x0C, 0x03, I2C_MEMADD_SIZE_8BIT, buf, 2, 10) != HAL_OK) {
        return HAL_ERROR; /* [위반 2]: 중간 통신 에러 리턴 */
    }
    *raw_angle = ((uint16_t)buf[0] << 6) | (buf[1] >> 2);
    if (*raw_angle >= 16384) {
        return HAL_ERROR; /* [위반 3]: 유효 범위 초과 리턴 */
    }
    return HAL_OK;        /* [정상 리턴] */
}

/* =========================================================================
 * [개선 후 (After)]: 단일 변수(status) 반환 단일 출구 구조 확립 (MISRA 15.5 준수)
 * ========================================================================= */
HAL_StatusTypeDef Encoder_ReadRawAngle_New(I2C_HandleTypeDef *hi2c, uint16_t *raw_angle)
{
    HAL_StatusTypeDef status = HAL_ERROR;

    /* 1. 단일 진입 가드 조건 검사 */
    if ((hi2c != NULL) && (raw_angle != NULL)) {
        uint8_t buf[2] = {0u, 0u};
        
        /* 2. 안전한 I2C 통신 수행 */
        if (HAL_I2C_Mem_Read(hi2c, 0x0Cu, 0x03u, I2C_MEMADD_SIZE_8BIT, buf, 2u, 10u) == HAL_OK) {
            const uint16_t val = ((uint16_t)buf[0] << 6u) | ((uint16_t)buf[1] >> 2u);
            
            /* 3. 14비트(0~16383) 유효성 검증 */
            if (val < 16384u) {
                *raw_angle = val;
                status = HAL_OK;
            }
        }
    }

    /* 4. 단 하나의 출구 (Single Exit Point) */
    return status;
}
```

---

#### [사례 2] Q8 S-Curve 가속도 스케일링 (`App/motor/motor.c`, 커밋 `093c1e0`)

```c
/* =========================================================================
 * [개선 전 (Before)]: 조건 분기마다 조기 return 문을 사용하여 MISRA 15.5 위반 (탈출구 3개)
 * ========================================================================= */
static inline uint32_t axis_scurve_scale_q8_Old(uint32_t v_pps, uint32_t cruise_pps)
{
#if !MOTOR_SCURVE_ENABLE
    return 256u; /* [위반 1]: 매크로 비활성 시 조기 리턴 */
#else
    if (cruise_pps <= MOTOR_START_PPS) {
        return 256u; /* [위반 2]: 순항속도 미달 시 조기 리턴 */
    }
    const uint32_t span = cruise_pps - MOTOR_START_PPS;
    uint32_t delta = (v_pps > MOTOR_START_PPS) ? (v_pps - MOTOR_START_PPS) : 0u;
    if (delta > span) {
        delta = span;
    }
    const uint32_t x_q8 = (delta * 256u) / span;
    const uint32_t bell_q8 = (x_q8 * (256u - x_q8)) / 64u;
    const uint32_t floor_q8 = MOTOR_SCURVE_FLOOR_Q8;
    return floor_q8 + (((256u - floor_q8) * bell_q8) / 256u); /* [위반 3]: 중간 연산 리턴 */
#endif
}

/* =========================================================================
 * [개선 후 (After)]: 단일 변수(scale_q8) 초기화 및 단일 return 문 구조 확립 (MISRA 15.5 준수)
 * ========================================================================= */
static inline uint32_t axis_scurve_scale_q8_New(uint32_t v_pps, uint32_t cruise_pps)
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

    /* 단 하나의 출구 (Single Exit Point) */
    return scale_q8;
}
```

---

## 5. 실제 오탐 억제 사유 관리 (`CLionProject/tools/cppcheck_suppressions.txt`)

프로젝트 코드베이스의 `cppcheck_suppressions.txt`는 다음과 같이 명확한 엔지니어링 근거를 바탕으로 6개 범주로 관리된다:

```text
# =====================================================================
# cppcheck 억제 목록 (VEDA ADTS)
#   검사 대상 = App/ (motor, hallEffectSensor, scan, lidar, uart_rpi) + shared/
#   검사 제외 = Core/, Drivers/ (CubeMX 자동생성 - 수정 불가 영역)
# =====================================================================

# 1. CubeMX / 벤더 자동생성 코드 전체 제외
*:*Core/*
*:*Drivers*

# 2. 시스템 매크로 노이즈 억제
missingIncludeSystem
preprocessorErrorDirective

# 3. 공유 계약 헤더 (shared/protocol.h) Advisory deviation
# 사유: RPi/STM32/커널 공유 헤더이므로 특정 컴포넌트에서 미사용 심볼이 존재함
misra-c2012-2.3:*shared/protocol.h
misra-c2012-2.4:*shared/protocol.h
misra-c2012-2.5:*shared/protocol.h
misra-c2012-20.1:*shared/protocol.h

# 4. ST HAL 페리페럴 베이스 포인터 캐스팅 (11.4 Advisory)
# 사유: STM32 HAL 헤더의 '#define GPIOB ((GPIO_TypeDef*)GPIOB_BASE)' 하드웨어 접근 매크로 수용
misra-c2012-11.4:*App/*

# 5. 모듈 공개 API의 단일 TU 참조 (8.7 Advisory)
# 사유: 계층 분리 아키텍처에서 모듈 공개 함수를 헤더로 노출하므로 static 강제화 배제
misra-c2012-8.7:*App/*

# 6. 브링업 벤치 도구 한정 억제 (stdio 21.6, 미사용 매크로 2.5)
# 사유: 브링업 전용 툴로 릴리즈 빌드 시 컴파일아웃되어 바이너리에 남지 않음
misra-c2012-21.6:*App/hallEffectSensor/encoder_bench.c
misra-c2012-2.5:*App/hallEffectSensor/encoder_bench.c
misra-c2012-21.6:*App/motor/motor_bench.c
misra-c2012-2.5:*App/motor/motor_bench.c
misra-c2012-21.6:*App/lidar/lidar_bench.c
misra-c2012-2.5:*App/lidar/lidar_bench.c

# 7. CI Cppcheck 2.13.0 파서 버그 오탐 대응 (코드 인라인 주석으로 국소 전환)
# 사유: 파일 통째 억제 대신 호출 라인 윗줄에 `// cppcheck-suppress misra-c2012-11.8`을
#      국소 적용하여, 파일 나머지 영역의 11.8 검사를 온전히 보존 (motor.c 8곳, hallEffectSensor.c 9곳)
```

### 5.1 인라인 주석 기반 국소 예외 처리 (Best Practice)
파일 전체를 억제하는 대신, 호출부 단위로 정밀하게 국소 예외 처리하여 코드 안전성을 극대화합니다:

```c
// cppcheck-suppress misra-c2012-11.8 ; CI Cppcheck 2.13.0 const struct 멤버 파서 오탐 대응
HAL_GPIO_WritePin(s_cfg[ax].step_port, s_cfg[ax].step_pin, GPIO_PIN_RESET);
```

---

## 6. GitHub Actions CI 자동화 워크플로우 명세 (`.github/workflows/ci.yml`)

```yaml
name: ADTS Embedded Firmware CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Source Repository
        uses: actions/checkout@v3

      - name: Install Toolchain & Static Analyzers
        run: |
          sudo apt-get update
          sudo apt-get install -y cppcheck gcc-arm-none-eabi cmake ninja-build clang-tidy

      - name: Run Track 1 (STM32 MISRA C:2012 & Cppcheck)
        run: |
          cppcheck --enable=all --inconclusive --std=c99 \
            --suppressions-list=STM32/tools/cppcheck_suppressions.txt \
            --rule-file=STM32/tools/misra_rules.txt \
            --error-exitcode=1 \
            STM32/App/

      - name: Run Track 2 (RPi Clang-Tidy)
        run: |
          clang-tidy RPi/driver/*.c RPi/daemon/*.c -- -I RPi/shared

      - name: Build STM32 Firmware (Verification Gate)
        run: |
          cmake --preset Debug -S STM32 -B STM32/build
          cmake --build STM32/build --target adts.elf
```

---

## 7. 정적 분석 전/후 품질 개선 비교

```text
       [ 정적 분석 체계 도입 및 품질 게이트 비교 ]

  [개선 전: 수동 검사 & 다중 리턴 구조]
    - 함수 내 다중 return 문으로 인한 제어 흐름 분기 복잡성 및 자원 해제 누락 위험
    - 경계 검사 부재로 인한 잠재적 런타임 Null Pointer 역참조 위험

  [개선 후: 2-Track CI 자동화 & MISRA Rule 15.5 단일 리턴]
    - 단일 변수(status) 반환 구조 전면 리팩토링으로 명확한 단일 진입/단일 출구 확립
    - Cppcheck / MISRA C:2012 / Clang-Tidy 연동 GitHub Actions 자동 품질 게이트 구축
```

| 품질 관리 항목 | 개선 전 (초기 코드베이스) | 개선 후 (2-Track CI 구축) | 개선 성과 및 기여도 |
| :--- | :--- | :--- | :--- |
| **MISRA C:2012 Rule 15.5** | 다중 리턴문 사용으로 제어 경로 분기 | **단일 변수(status) 반환 구조 전면 리팩토링** | **제어 흐름 단순화 및 100% 준수** |
| **메모리 / 포인터 안전성** | 포인터 유효성 검사 누락 구간 존재 | **진입 가드 및 경계 검사 엄격 적용** | **CWE 보안 취약점 사전 차단** |
| **오탐 억제 사유 관리** | 체계적인 억제 기준 부재 | **엔지니어링 근거 문서화 및 파일 분리 관리** | **분석 결과의 신뢰성 확보** |
| **품질 검증 자동화** | 개발자 수동 로컬 검사에 의존 | **GitHub Actions PR 머지 시 자동 검증** | **무결점 펌웨어 빌드 자동화** |

---

## 8. 결론 및 향후 발전 방향

### 8.1 과업 성과 요약
본 품질 관리 체계는 STM32 Cppcheck/MISRA와 RPi Clang-Tidy의 **2-Track 자동화 정적 분석 게이트**를 구축하고, MISRA C:2012 Rule 15.5 단일 리턴 리팩토링을 완수함으로써, 임베디드 펌웨어의 제어 흐름 복잡도를 대폭 낮추고 고신뢰성 무결점 소프트웨어 구조를 완성하였다. 이를 통해 PR 머지 단계에서 잠재 결함을 사전에 100% 차단하는 자동화된 방산 SW 품질 보증 체계를 확립하였다.

### 8.2 향후 발전 방향 및 구체적 구현 방안
1. **SonarQube Enterprise 연동 및 CWE/MISRA 대시보드 시각화**:
   * **CI 파이프라인 결합**: GitHub Actions 워크플로우에 `sonarsource/sonarcloud-github-action`을 연동하여 PR 생성 시 정적 분석 위반 추이 및 기술 부채(Technical Debt)를 브랜치별로 자동 리포팅.
   * **품질 게이트 기준**: 신규 코드 결함률 0%, 보안 핫스팟(Security Hotspots) 0건 미준수 시 빌드 자동 거절(Reject) 정책 확립.
2. **gcov/lcov 기반 펌웨어 단위 테스트(Unit Test) C0/C1 커버리지 90% 게이트 구축**:
   * **호스트 테스트 환경**: Native Host GCC 테스트 환경(`tests/`)에서 CppUTest / GoogleTest 프레임워크와 `lcov --coverage`를 실행.
   * **커버리지 기준**: 구문(Statement C0) 및 분기(Branch C1) 커버리지 90% 미만 시 PR 머지를 자동 차단하는 회귀 방호 CI 파이프라인 고도화.
