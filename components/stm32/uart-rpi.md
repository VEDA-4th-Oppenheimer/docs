---
tags:
  - project/adts
  - part/stm32
  - uart
  - protocol
doc_id: ADTS-STM-60
part: STM32
owner: 이현우
status: partially-verified
updated: 2026-08-24
source: STM32/App/uart_rpi/uart_rpi.c
commit: bd53921
---

# uart_rpi 프로토콜 어댑터

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-STM-60` |
| 파트 | STM32 (RPi 링크) |
| 담당 | 이현우 |
| 대상 소스 | `App/uart_rpi/uart_rpi.c` (361줄), `uart_rpi.h` (64줄) |
| 기준 코드 | STM32 `bd53921` (`main`, 2026-08-21) |
| 직전 기준선 | `c5c1c67`. `App/uart_rpi/` 는 두 커밋 간 변경 없음 |
| 포트 | USART1 PA9 TX / PA10 RX, 115200 8N1 |
| 상태 | 구현 완료 · 거절 경로(STM-60-01/03)는 관측 수단이 없어 미검증 (6장) |

← [[00 개발보고서 개요]] · 계약: [[10 Protocol v6 통신 계약]] · 상위: [[61 scan 2축 스캔 시퀀서]] · 연결: [[62 펌웨어 런타임 연결]]

---

## 1. 개요

`uart_rpi` 는 STM32 스캔 제어와 Raspberry Pi 사이의 Protocol v6 어댑터이다.

1. USART1 바이트를 ISR 에서 링버퍼에 적재한다
2. 메인루프에서 프레임으로 파싱한다 (SOF / LEN / CRC16)
3. 검증된 명령을 상위 계층(`scan`)에 디스패치한다
4. 상행 프레임을 조립·송신한다

### 1.1 ISR 을 짧게 유지한다

```
USART1 RX ISR   바이트를 링버퍼에 넣고 다음 수신 무장
메인루프        프레임 검증, 명령 실행, I2C, 모터 제어
```

현재 `scan_home()` 은 상태만 전이하고, 실제 엔코더 I2C 판독은 메인루프의
`scan_process()` 경로에서 수행한다. 이 구조는 ISR 에 블로킹 I2C 가 들어오는 것을
막는다. 다만 과거 ISR 직접 실행 구조와 라이다 프레임 유실, 수정 후 해소를 함께
보여 주는 측정 로그는 남아 있지 않으므로 소요 시간과 과거 장애는 검증 사실로
주장하지 않는다.

---

## 2. 적용 범위와 경계

| 다루는 것 | 다루지 않는 것 |
|---|---|
| 프레임 파싱·조립·디스패치 | 모터 구동 (강유근) |
| 링버퍼와 오버플로 정책 | 엔코더 판독 (강유근) |
| 1Hz STATUS 와 진단 카운터 수집 | 라이다 NLink 파싱 (송영빈) |
| 스캔 점·DONE 상행 | 스캔 시퀀스 → [[61 scan 2축 스캔 시퀀서]] |

모터·엔코더·라이다의 결과가 어떤 프레임으로 외부에 보이는지만 다룬다.

### 2.1 main.c 결선

```c
uart_rpi_init(&huart1);        /* 초기화 + 첫 수신 무장                */
uart_rpi_process();            /* 메인루프 매 바퀴 — 링버퍼를 파서로   */
uart_rpi_status_tick();        /* 메인루프 매 바퀴 — 내부에서 1초 판정 */
uart_rpi_on_rx_cplt(huart);    /* HAL_UART_RxCpltCallback 에서 위임    */
uart_rpi_on_error(huart);      /* HAL_UART_ErrorCallback 에서 위임     */
```

`RxCplt`/`Error` 콜백은 USART6(라이다)와 공유한다. `uart_rpi` 는 초기화 때 저장한
핸들 포인터와 `huart` 를 직접 비교하고, `lidar` 는 `huart->Instance` 를 비교해
자기 UART 만 처리한다.

---

## 3. 설계

### 3.1 정적 상태 (`uart_rpi.c:40~48`)

| 상태 | 컨텍스트 | 의미 |
|---|---|---|
| `s_huart` | init / main | RPi 링크 UART 핸들 |
| `s_rx` | ISR | HAL 1바이트 수신 버퍼 (`volatile`) |
| `s_rb[256]` | ISR 생산 / main 소비 | 수신 링버퍼 |
| `s_rb_head` / `s_rb_tail` | ISR / main | 실효 용량 255B |
| `s_scan_count` | main | `SCAN_DATA` TX 성공 수 |
| `s_tx_fail` | main | HAL TX 실패 누적 |
| `s_rb_ovf` | ISR | 링버퍼 오버플로 (`volatile`) |

head 만 ISR 이, tail 만 메인루프가 증가시키는 SPSC 구조라 락이 없다.

결정 — 락 대신 소유권을 나눴다.

| 대안 | 기각 사유 |
|---|---|
| 임계구역(`__disable_irq`)으로 감싼다 | 바이트마다 인터럽트를 끄면 라이다 ISR 지연이 누적된다 |
| DMA 원형 버퍼 | HAL DMA 설정이 늘고, 파서가 어차피 바이트 단위로 돈다 |

파급: **락이 없는 근거는 "생산자 1 · 소비자 1" 하나뿐이다.** `s_rb_tail` 을
건드리는 두 번째 소비자(진단 명령, 다른 파서)가 생기면 그 순간 경쟁이 된다.
`s_rb_head`·`s_rb_tail`·`s_rb`·`s_rx` 가 `volatile` 인 것도 이 전제 위에 있다.

`rx_ovf` 는 소비자가 따라잡지 못한 **하행 바이트 양**의 지표다. 메인루프 지연이
길수록 오르기 쉽지만, 같은 지연에서도 RPi 가 보낸 바이트가 255B 미만이면 오르지
않는다. 따라서 블로킹 시간만의 지표로 해석하지 않는다.

### 3.2 TX 정책 — 동기 블로킹

모든 명령 응답과 스캔 점이 `HAL_UART_Transmit`(타임아웃 100ms)으로 직렬화된다.
명시적 TX mutex 는 없지만 호출이 메인루프 컨텍스트에 집중돼 있다.

> [!danger] ISR 에서 부르면 안 된다
> 라이다 ISR 은 각도를 래치만 하고, 점 상행은 메인루프의 `lidar_process()` →
> `scan_submit_sample()` 경로로 넘긴다.

| 장점 | 대가 |
|---|---|
| 호출이 끝날 때 성공/실패를 바로 안다 | 최대 100ms 블로킹 동안 RX 배출·status·스캔 제어가 밀린다 |
| `SCAN_DONE` 의 `point_count` 를 성공 반환 수로 셀 수 있다 | HAL 성공이 RPi 수신 성공을 뜻하지 않는다 |

결정 — 동기 블로킹을 택했다.

| 대안 | 기각 사유 |
|---|---|
| IT/DMA TX + 송신 큐 | 큐 깊이·우선순위·오버플로 정책이 새로 필요하고, 실패를 호출자에게 돌려줄 방법이 사라진다 |
| 실패를 무시하고 fire-and-forget | 점 카운터가 실제 송신 수보다 커진다 — 아래 4.1 의 폐기 이유 |

트레이드오프를 그대로 안고 있다. 100ms 블로킹은 STM-60-04 로 열려 있다.

반증: 100ms 타임아웃이 실제로 걸리면 `tx_fail` 은 올라야 한다. `rx_ovf` 는 그
동안 RPi 가 255B를 넘게 보낸 경우에만 함께 오른다. 2026-08-19 표준 스캔에서
둘 다 0 이었다는 결과는 해당 실행에서 TX 실패와 RX 오버플로를 관측하지 않았다는
뜻이며, 두 카운터가 항상 함께 움직인다는 뜻은 아니다.

---

## 4. 구현 — 코드 해설

### 4.1 프레임 송신 — `uart_rpi_send_frame()` (`:58`)

```c
bool uart_rpi_send_frame(uint8_t cmd, const void *payload, uint8_t payload_len)
{
    bool ok = false;

    if (payload_len <= PROTO_MAX_PAYLOAD) {            /* CWE-120 경계검사 */
        uint8_t  frame[PROTO_MAX_FRAME];
        frame[0] = PROTO_SOF;
        frame[1] = cmd;
        frame[2] = payload_len;

        if ((payload_len > 0u) && (payload != NULL)) {
            /* cppcheck-suppress misra-c2012-21.15 ; 합의된 바이트열 직렬화 */
            (void)memcpy(&frame[PROTO_HEADER_LEN], payload, payload_len);
        }

        total = (uint8_t)(PROTO_HEADER_LEN + payload_len);
        crc   = proto_crc16(frame, total);
        frame[total]      = (uint8_t)(crc & 0xFFu);          /* little-endian */
        frame[total + 1u] = (uint8_t)((crc >> 8) & 0xFFu);
        total = (uint8_t)(total + PROTO_CRC_LEN);

        ok = (HAL_UART_Transmit(s_huart, frame, total, 100u) == HAL_OK);
        if (!ok) s_tx_fail++;
    }
    return ok;
}
```

- 드라이버측 `turret_send_frame()` 과 바이트 단위로 대칭이다. 양쪽이 같은
  `proto_crc16()` 을 쓴다
- `payload_len <= PROTO_MAX_PAYLOAD` 가 스택 오버플로(CWE-120)를 막는 지점이다
- MISRA 21.15(`memcpy` 타입 불일치) deviation 에 근거 주석을 단다 — 정책 A 에
  따라 폴더 통째 억제는 금지이다

결정 — 반환값을 `bool` 로 돌려준다. 예전에는 `(void)` 로 버렸다(`uart_rpi.c:50~56`).

버리면 타임아웃이나 부분 전송이 나도 호출자가 모른다. 특히 스캔 점은 보낸 셈
치고 카운터를 올려 **`SCAN_DONE.point_count` 가 RPi 가 실제로 받은 수보다
커질 수 있다.** `PONG`·`HOMED`·`ERROR` 도 조용히 사라진다.

현재 드라이버는 `point_count` 를 private `last_point_count` 에 저장하지만
`TURRET_GET_STATE` ABI 로 내보내지 않는다. 따라서 데몬의 `stm_reported` 는 항상
0 이고, STM32 송신 성공 수와 데몬 수신 수의 종단 간 대조는 아직 끊겨 있다.

파급: 이 함수가 `s_tx_fail` 을 올리는 유일한 지점이다. 다른 경로로 TX 를
추가하면 그 실패는 진단에 잡히지 않는다.

2026-08-19 산출물에서 수신 히스토그램 합 52,794는 유효 40,088 + 병합 12,706과
일치한다. 이것은 데몬 내부의 수신·격자 배치 보존식을 확인하지만, JSON 에
STM32 `point_count` 가 기록되지 않으므로 STM32→드라이버 구간의 무손실까지
입증하지는 않는다.

### 4.2 수신 ISR — `uart_rpi_on_rx_cplt()` (`:317`)

```c
const uint16_t next = (uint16_t)((s_rb_head + 1u) & 0xFFu);  /* 256 wrap */

/* 가득 차면 새 바이트를 버린다(옛 것을 덮지 않는다).
 *
 * 주의: 예전에는 full 검사 없이 그냥 썼다. 두 가지가 문제였다 —
 *   ① 아직 안 읽은 바이트를 덮는데, 그건 파싱 중인 프레임의 일부일
 *      수 있어 그 프레임까지 같이 깨진다. 새 것을 버리면 손실이
 *      뒤쪽에만 남고 파서의 SOF 재동기화가 알아서 복구한다.
 *   ② 정확히 한 바퀴(256B) 추월하면 head == tail 이 되어 소비자가
 *      비어 있는 것으로 오인한다. 즉 넘쳤다는 사실조차 사라진다.
 *
 * 256B 는 하행 프레임 20개분이라 정상 상태에서는 절대 안 찬다.
 * 차는 경우는 메인루프가 오래 막힌 때뿐이고(엔코더 I2C 재시도 +
 * 버스 복구, 벤치 도구), 그래서 이 카운터가 곧 메인루프 블로킹의
 * 지표가 된다 — 지금은 그걸 볼 방법이 없다. */
if (next != s_rb_tail) {
    s_rb[s_rb_head] = s_rx;
    s_rb_head       = next;
} else {
    s_rb_ovf++;
}
(void)HAL_UART_Receive_IT(huart, (uint8_t *)&s_rx, 1u);
```

위 소스 주석의 "256B는 하행 프레임 20개분"과 "정상 상태에서는 절대 안 찬다"는
표현은 정확하지 않다. 실효 용량은 255B이고, 하행 프레임은 zero-payload 명령
5B와 `SCAN_START` 15B 등으로 크기가 다르다. 지속적인 하행 버스트나 메인루프
지연이 겹치면 찰 수 있다. 마지막 문장의 관측 공백만 v6에서 해소되어
`s_rb_ovf` 가 `proto_status.rx_ovf` 로 상행된다.

"새 것을 버린다"는 정책의 근거 두 가지가 핵심이다. 특히 ②가 미묘하다 —
링버퍼가 정확히 한 바퀴 추월하면 `head == tail` 이 되어 넘쳤다는 사실 자체가
사라진다.

> [!bug] STM-60-03 — `HAL_UART_Receive_IT` 반환값을 확인하지 않는다
> 재무장이 실패하면 RX 가 조용히 영구 정지한다. `rx_ovf` 도 안 오르므로
> 진단에도 안 걸린다.

반증: 연속 하행 입력 중 `rx_ovf` 가 오른다면 같은 구간의 엔코더 I2C 재시도·
버스 복구 같은 소비 지연을 함께 확인한다. 링버퍼 255B 는 115200 8N1 입력이
끊김 없이 찰 때 약 22ms 분이다. 입력이 적으면 더 긴 블로킹도 잡히지 않으므로
**0 이라는 것이 "메인루프가 한 번도 안 막혔다" 는 뜻은 아니다.**

### 4.3 프레임 파서 — `proto_feed()` (`:265`)

```c
static void proto_feed(uint8_t b)
{
    static uint8_t buf[PROTO_MAX_FRAME];
    static uint8_t idx  = 0u;
    static uint8_t need = 0u;

    if (idx == 0u) {
        /* 프레임 경계 탐색: SOF 만 시작으로 인정, 그 외 바이트는 버림 */
        if (b == PROTO_SOF) { buf[0] = b; idx = 1u; need = 0u; }
    } else {
        buf[idx] = b;
        idx      = (uint8_t)(idx + 1u);

        if (idx == PROTO_HEADER_LEN) {
            uint8_t len = buf[2];
            if (len > PROTO_MAX_PAYLOAD) {
                idx = 0u; need = 0u;                    /* CWE-120: 프레임 폐기 */
            } else {
                need = (uint8_t)(PROTO_HEADER_LEN + len + PROTO_CRC_LEN);
            }
        }

        if ((need != 0u) && (idx >= need)) {
            proto_dispatch(buf, need);
            idx = 0u; need = 0u;
        }
    }
}
```

`idx` 가 `PROTO_MAX_FRAME`(29 = 3 + 24 + 2)을 넘지 않는 것은 LEN 게이트와
`need <= 29` 에 의존한다. 드라이버측은 여기에 더해 `rx_idx >= PROTO_MAX_FRAME`
검사를 하나 더 두는데, 이쪽은 `need` 로 상한이 확정되므로 필요가 없다.

결정 — 재동기화를 SOF 탐색에만 맡기고 타임아웃을 두지 않았다.

| 대안 | 기각 사유 |
|---|---|
| 프레임 간 타임아웃으로 리셋 | 타이머 상태가 늘고, 하행이 드물어(명령 단위) 임계 잡기가 애매하다 |
| 길이 대신 SOF/EOF 로 구분 | 페이로드에 EOF 바이트가 나오면 escape 가 필요해진다 |

파급: **`idx` 의 상한 근거는 LEN 게이트와 `PROTO_MAX_FRAME`의 파생 관계다.**
`buf` 는 함수 static 이므로 스택 객체가 아니며, `PROTO_MAX_FRAME` 은
`PROTO_MAX_PAYLOAD` 에서 파생되어 현재 정의에서는 함께 커진다. 두 매크로의
파생 관계를 끊거나 별도 상수로 바꾸면 static 버퍼 경계를 다시 증명해야 한다.

반증: SOF 재동기화가 실제로 작동한다면 바이트 유실 뒤에도 다음 프레임부터
정상 파싱돼야 한다. 깨진 프레임 하나가 뒤 프레임까지 연쇄로 무너뜨린다면
`need` 계산이나 폐기 경로가 잘못된 것이다.

> [!bug] STM-60-06 — 파서 상태가 함수 static 이다
> `uart_rpi_init()` 재호출로 리셋되지 않는다. 재초기화 테스트가 비결정적이 된다.

### 4.4 명령 디스패치 — `proto_dispatch()` (`:196`)

```c
uint32_t raw     = ((uint32_t)buf[flen - 1u] << 8) | (uint32_t)buf[flen - 2u];
uint16_t rx_crc  = (uint16_t)raw;                       /* MISRA 10.8 회피 */
uint16_t crc_len = (uint16_t)len + (uint16_t)PROTO_HEADER_LEN;
uint16_t calc    = proto_crc16(buf, crc_len);

if (rx_crc == calc) {
    switch (cmd) {
    case CMD_HOME:
        /* 여기서 엔코더를 직접 읽지 않는다 — 블로킹 I2C 라 디스패처
         * 안에서 수십 ms 를 잡아먹고 그 사이 프레임이 밀린다.
         * scan_process() 가 메인루프에서 수행하고 CMD_HOMED 를 보낸다. */
        scan_home();
        break;

    case CMD_SCAN_START:
        if (len == sizeof(struct proto_scan_start)) {
            struct proto_scan_start ss;
            (void)memcpy(&ss, &buf[PROTO_HEADER_LEN], sizeof(ss));
            scan_start(&ss);
        }
        break;

    case CMD_DISARM:
        /* scan_stop 이 아니라 scan_abort 다 — 전자는 SC_DONE 을 거쳐
         * 파킹까지 가므로, 전류를 끊은 뒤 유령 이동과 가짜 SCAN_DONE 이
         * 생긴다(scan_abort 구현부 주석). */
        scan_abort();                               /* 시퀀스 폐기 먼저 */
        motor_disarm();                             /* -> 전류 차단     */
        break;

    case CMD_PING:
        (void)uart_rpi_send_frame(CMD_PONG, NULL, 0u); /* heartbeat 응답 */
        break;
    ...
    }
} else {
    DBG("CRC FAIL rx=%04X calc=%04X\r\n", rx_crc, calc);
}
```

세 가지가 중요하다.

1. `CMD_HOME` 에서 I2C 를 안 읽는다. 디스패처는 메인루프 안이지만 여전히
   "프레임 배출 루프" 안이라, 여기서 수십 ms 를 쓰면 뒤 프레임이 밀린다
2. `CMD_DISARM` 이 `scan_abort()` 를 부른다. `scan_stop()` 이면 `SC_DONE` 을 거쳐
   가짜 `SCAN_DONE` 을 보내고 파킹 목표를 다시 만들게 된다. 현재 `motor.c`의
   `s_armed`가 전류 차단 뒤 펄스와 스텝카운트 갱신을 막으므로 실제 유령 이동은
   생기지 않지만, 완료 통지와 파킹 시퀀스 자체가 비상정지 의미에 맞지 않는다
3. CRC 실패는 `DBG` 만 찍고 버린다 (STM-60-01)

> [!bug] STM-60-02 — 길이 검증이 느슨하다
> `CMD_SCAN_START` 는 `len` 이 틀리면 아무 통지 없이 무시된다(else 절 없음).
> `HOME`/`STOP`/`DISARM`/`PING` 은 payload 가 붙어 와도 실행된다.
> 계약대로면 둘 다 `ERR_BAD_LEN` 이어야 한다.

파급 — 이 디스패처의 침묵 경로가 세 갈래다.

| 경로 | 코드 | 지금 |
|---|---|---|
| CRC 불일치 | `:262` else | `DBG` 만. 카운터도 없다 |
| `SCAN_START` 길이 불일치 | `:220` if 의 else 없음 | 아무 일도 안 일어난다 |
| 알 수 없는 `cmd` | `:257` default | `DBG` 만 |

셋 다 **RPi 쪽에서는 "명령을 보냈는데 아무 반응이 없다" 로만 보인다.** 원인을
가르려면 양 끝 카운터가 필요한데 현재 `proto_status` 에 CRC/LEN 거절 카운터가 없다
(STM-60-01). `ERR_BUSY` 가 v6 에서 생기기 전 스캔 거절이 딱 이 상태였고, 그때
원인 규명이 어려웠던 것이 이 이슈를 P0 로 둔 이유다.

반증: CRC 게이트가 실제로 작동한다면 잡음 구간에서 명령이 실행되는 일은 없어야
한다. 반대로 잘못된 명령이 실행된다면 CRC 검증이나 `crc_len` 계산이 틀린 것이다.

### 4.5 `uart_rpi_status_tick()` (`:128`) — 1Hz 상태

```c
static uint32_t s_last_ms = 0u;
const uint32_t now = HAL_GetTick();

/* 부호 없는 뺄셈이라 HAL_GetTick 이 49일 만에 한 바퀴 돌아도 안전하다. */
if ((now - s_last_ms) >= STATUS_PERIOD_MS) {
    struct proto_status st;
    uint8_t flags = 0u;
    s_last_ms = now;

    if (scan_is_homed()) flags |= (uint8_t)STF_HOMED;
    if (scan_is_busy())  flags |= (uint8_t)STF_SCANNING;

    st.cur_pan_ddeg  = (proto_s16)motor_pulse_to_ddeg(motor_get_pulse(MOTOR_AXIS_PAN));
    st.cur_tilt_ddeg = (proto_s16)motor_pulse_to_ddeg(motor_get_pulse(MOTOR_AXIS_TILT));
    st.flags         = flags;
    st.tx_fail       = sat16(s_tx_fail);
    st.rx_ovf        = sat16(s_rb_ovf);
    st.enc_retry     = sat16(motor_encoder_retry_count(MOTOR_AXIS_PAN)
                           + motor_encoder_retry_count(MOTOR_AXIS_TILT));
    st.lidar_drop    = sat16(lidar_get_queue_drops());
    st.reject_busy   = sat16(scan_reject_busy_count());

    (void)uart_rpi_send_frame((uint8_t)CMD_STATUS, &st, (uint8_t)sizeof(st));
}
```

메인루프에서 매 바퀴 호출하지만 주기 판정은 내부에서 한다. 호출자가 타이밍을
알 필요가 없고, 주기를 바꿔도 `main.c` 를 수정하지 않는다.

결정 — 주기를 1초로 잡았다(`uart_rpi.h:45` `STATUS_PERIOD_MS 1000u`).

| 주기 | UART 점유 | 판단 |
|---|---:|---|
| 1초 | 20B × 1Hz = 0.17% | 채택. 스캔 점유(20%)에 영향이 없다 |
| 100ms | 1.7% | 여전히 무해하지만 얻는 것이 없다 |

각도는 이미 `SCAN_DATA` 에 실려 오고 카운터는 천천히 변하므로 더 자주 보낼
이유가 없다(`uart_rpi.c:123~127`).

파급: 주기를 늘리면 드라이버의 `STF_HOMED` 가 진실을 따라잡는 지연도 같이
늘어난다. 그 플래그는 데몬이 "스캔을 시작해도 되나" 를 판단하는 근거다
([[61 scan 2축 스캔 시퀀서]] 4.5).

반증: 이 함수가 실제로 1Hz 로 돈다면 드라이버의 `status_seen` 이 서고 카운터
5종이 갱신돼야 한다. 메인루프가 막히면 주기가 늘어질 뿐 멈추지는 않는다 —
멈춘다면 원인은 주기 판정이 아니라 메인루프 자체다.

`sat16()` (`:113`) 은 u32 를 65535 에서 포화시킨다. 잘라내면 65536번째에
0 으로 보여 오히려 정상처럼 읽힌다.

카운터 출처가 네 모듈에 흩어져 있다 — 이 함수가 모아서 한 프레임으로 만드는
집계 지점이다.

| 카운터 | 출처 모듈 |
|---|---|
| `tx_fail`, `rx_ovf` | uart_rpi 자신 |
| `enc_retry` | motor (양축 합) |
| `lidar_drop` | lidar |
| `reject_busy` | scan |

#### v6 에서 이 함수가 바꾼 것

v5 까지 `proto_status` 는 정의만 있고 한 번도 보내진 적이 없었다.

Protocol v6 이전에도 RPi 커밋 `4bb5708`에서 `TURRET_HOME` 요청 시
`STF_HOMED` 를 내리는 경로가 추가됐으므로, v6 STATUS가 이 플래그를 내린 최초의
수단은 아니다. 다만 STATUS가 없던 시기에는 STM32의 현재 상태가 주기적으로
드라이버 캐시에 반영되지 않았고, 진단 카운터를 외부에서 읽을 경로도 없었다.
당시 리셋·재플래시 뒤 거절 사건은 커밋 설명에만 남아 있고 원본 프레임 로그는
보존돼 있지 않다.

주기 송신을 켜자 이전 홈의 `homed` 값이 되살아나 홈 완료 전에 `SCAN_START` 가 나가는
문제가 드러났다. `ERR_BUSY`(v6 신설)가 이를 잡는다.

### 4.6 스캔 점 상행 — `uart_rpi_send_scan_point()` (`:167`)

기구각·거리·원본 품질값·두 시계를 `proto_scan_point`(18B)로 만들고,
프레임 TX 가 성공할 때만 `s_scan_count` 를 올린다.

결정 — 펌웨어가 유효성을 판정하지 않는다(`uart_rpi.c:161~163`).

v5 에서 라이다 원시 품질 필드가 붙어 6B → 18B 가 됐다. 정규화하거나 걸러내지
않고 **F2P 가 준 값을 그대로** 올린다. 판정 기준이 나중에 바뀌어도 이미 찍은
스캔을 다시 해석할 수 있게 원본을 보존하는 경계이다. 현재 데몬도
`dis_status` 로 점을 제외하지 않고, 범위 안에서 채워진 셀은 모두 `valid:true`로
출력한다. 따라서 센서 유효성 필터는 상위 계층에서 구현할 수 있도록 열어 둔
정책이지, 현재 데몬이 수행하는 검증으로 보아서는 안 된다.

| 대안 | 기각 사유 |
|---|---|
| `dis_status != 1` 인 점을 펌웨어에서 버린다 | 기준이 바뀌면 과거 스캔을 재해석할 수 없다 |
| 품질값을 정규화해 올린다 | 원본 손실. payload는 18B, 와이어 프레임은 23B이며 115200 8N1·100Hz에서 약 20.0%다 |

파급: 산출물의 `dis_status` 히스토그램은 **F2P 원본 분포**다. 펌웨어가 걸러
시작하면 그 히스토그램의 의미가 조용히 바뀐다.

반증: 펌웨어가 안 거른다면 데몬이 받은 프레임 수와 히스토그램 합이 같아야
한다. 2026-08-21 Phase 4 산출물에서 `0:128 / 1:53,620` 합 53,748 이
수신 프레임 수와 일치한다.

```c
void uart_rpi_reset_scan_count(void)   /* :94 */
```

> 스캔 점 카운터를 0 으로. 요청이 받아들여진 뒤에 부를 것 — 디스패처에서
> 먼저 밀면 거절된 요청이 진행 중인 스캔의 집계를 지운다.

`scan_start()` 가 검증을 통과한 뒤에만 부르는 이유이다.

### 4.7 완료 통지 — `uart_rpi_send_scan_done()` (`:189`)

현재 `s_scan_count` 를 `proto_scan_done` 으로 보낸다. 이 값은 RPi 수신 확인이
아니라 STM32 로컬 TX 호출 성공 수이다 ([[10 Protocol v6 통신 계약]] 5.1).

### 4.8 링버퍼 배출 — `uart_rpi_process()` (`:354`)

```c
while (s_rb_tail != s_rb_head) {                     /* 버퍼에 데이터 있으면 */
    uint8_t bb = s_rb[s_rb_tail];
    s_rb_tail  = (uint16_t)((s_rb_tail + 1u) & 0xFFu);
    proto_feed(bb);                                  /* 파싱 (느긋해도 안전) */
}
```

메인루프에서 tail 부터 head 까지 전부 배출한다. ISR 이 파싱이나 I2C/모터 명령을
수행하지 않는다는 계층 분리가 이 4줄로 완성된다.

### 4.9 에러 복구 — `uart_rpi_on_error()` (`:345`)

```c
/* cppcheck-suppress misra-c2012-14.4 ; HAL 벤더 매크로 내부 표현식 */
__HAL_UART_CLEAR_OREFLAG(huart);
(void)HAL_UART_Receive_IT(huart, (uint8_t *)&s_rx, 1u);
```

HAL IT 수신에서 ORE는 blocking error로 처리되어 진행 중 수신을 끝내지만,
FE/NE/PE는 non-blocking error로 콜백 뒤 수신을 계속한다. 따라서 재무장은 ORE
복구에 필요하지만 모든 UART 에러 1회가 링크를 영구 정지시키는 것은 아니다.

> [!warning] 워치독은 이 정지와 무관하게 계속 급여된다
> IWDG 는 메인루프가 도는 한 refresh 되므로 링크만 조용히 멈춘 상황이 겉으로
> 드러나지 않는다. 현재 STATUS에는 UART 오류 원인별 카운터나 재무장 실패
> 카운터가 없어 기존 진단값만으로 이 정지를 식별할 수 없다.

> [!bug] STM-60-05 — UART 에러 원인별 카운터가 없다
> ORE/FE/NE/PE 를 구분하지 않고 파서 상태 리셋 정책도 명시적이지 않다. 단순
> 재시작은 복구에는 도움이 되지만 장애가 보이지 않게 사라진다.

---

## 5. 인터페이스 — `uart_rpi.h` 가 만드는 경계

| 의존 방향 | 쓰는 API |
|---|---|
| `main.c` → `uart_rpi` | `init`, RX/error 콜백 위임, `process`, `status_tick` |
| `scan.c` → `uart_rpi` | `send_frame`(ERROR/HOMED), `send_scan_point`, `send_scan_done`, `reset_scan_count` |
| `uart_rpi` → `motor`/`lidar` | STATUS 조립용 상태 카운터 getter |

공개돼 있으나 위 표에 없는 것이 둘 있다 — `uart_rpi_tx_fail_count()` (`:99`) 와
`uart_rpi_rx_overflow_count()` (`:105`). 현재 저장소에서 호출자가 없고, 두 값은
`uart_rpi_status_tick()` 이 내부 변수로 직접 읽어 `CMD_STATUS` 에 싣는다.
진단 경로용으로 열어 둔 API 이며 MISRA 8.7 deviation 근거도 그렇게 적혀 있다.

`uart_rpi` 는 `scan` 을 호출하고(디스패치), `scan` 은 `uart_rpi` 를
호출한다(상행). 따라서 모듈 호출 그래프에는 순환 의존이 있다. 다만 두 공개
헤더가 서로를 include하지 않고 자료구조를 공유하지 않아 헤더 포함 순환과
공유 상태 결합은 피한다.

---

## 6. 검증

| 항목 | 방법 | 등급 | 결과 |
|---|---|---|---|
| CMake Debug 빌드 | clean 후 `cmake --build build/Debug` | B | 성공 |
| text / data / bss | `arm-none-eabi-size` | B | 44,092 / 468 / 3,052 B |
| RAM | 링커 리포트 | B | 3,520 B (3.58% of 96KB) |
| FLASH | 링커 리포트 | B | 44,576 B (8.50% of 512KB) |
| cppcheck / MISRA | `tools/run_static_analysis.sh` | B | 15파일 통과, exit 0 (cppcheck 2.21) |
| protocol 해시 | `shasum` | B | RPi 와 일치 |
| 실기 프레임 왕복 | 표준 스캔 | A | 52,794 프레임, `tx_fail`/`rx_ovf` 0 |
| v6 STATUS 주기 송신 | 같은 스캔 | A | 드라이버 `status_seen=1`, 카운터 5종 수신 |
| 프레임 왕복 재현 | 2026-08-21 실기 2회 | A | `checksum_error_count` 0 · `out_of_range` 0, 두 판 일치 |
| `ERR_BAD_CRC`/`ERR_BAD_LEN` 발화 | — | D | 거절 경로가 침묵이라 관측 수단이 없다. STM-60-01 |
| `Receive_IT` 재무장 실패 | — | D | 반환값을 안 봐서 발생해도 기록이 남지 않는다. STM-60-03 |

빌드·정적분석은 기준선 `bd53921` 에서 2026-08-24 에 다시 돌린 결과다. 직전
기준선 `c5c1c67` 의 값(text 43,916 / FLASH 8.47%)은 그 시점 것이다.

> [!important] 진단 카운터 수신이 v6 실기 동작의 증거다
> 15바이트 `CMD_STATUS` 는 v6 에만 있다. v5 이하였다면 드라이버가 길이 불일치로
> `turret_bad_len` 을 찍었을 것이다.

> [!note] 운영 규칙 — 증거 등급 D
> 펌웨어 플래시는 사용자가 직접 하고 자동화 세션은 빌드·전송까지만 한다는
> 과거 세션 메모가 있다. 실행 소스나 로그로 검증할 성질의 주장은 아니며,
> 현재도 유효한지는 사용자 운영 규칙으로 확인해야 한다.

### 6.1 진단 — 카운터로 원인 가르기

```bash
# RPi 쪽에서
watch -n1 sudo ./turret_test state
mosquitto_sub ... -t adts/state/daemon -C 1 | jq .diag
```

| 관측 | 원인 |
|---|---|
| `pong_seq` 안 오름 | 배선(TX/RX 뒤바뀜) · GND · STM32 전원 · 오버레이 등 링크 경로 확인 |
| `pong_seq` 오르는데 `status_seen=0` | 첫 1초 이내이거나 구버전 펌웨어, STATUS 송신 경로·메인루프 점검 |
| `rx_ovf > 0` | 하행 입력이 소비를 앞질렀다. 연속 115200 8N1일 때 255B가 약 22ms이며, 입력량과 지연을 함께 봐야 함 |
| `tx_fail > 0` | STM32 HAL TX 실패·타임아웃. USART1은 흐름제어가 없어 이 값만으로 RPi 정체나 링크 품질을 판정할 수 없음 |
| `lidar_drop > 0` | 라이다 큐 넘침 — 역시 메인루프 지연 |
| `enc_retry > 0` | MT6701 I2C 간헐 고장 |
| `reject_busy > 0` | 진행 중에 `SCAN_START` 가 들어왔다 |

### 6.2 정적분석

`App/` 은 MISRA-C:2012 게이트 대상이다. 정책 A — Required/Mandatory 만
차단하고 Advisory 는 근거를 달아 deviation. 폴더 통째 억제는 금지이다.

이 모듈의 deviation 및 규칙 회피:

| 룰 | 분류 | 위치 | 근거 |
|---|---|---|---|
| 21.15 | deviation | `memcpy(&frame[3], payload, len)` | 합의된 바이트열 직렬화 |
| 14.4 | deviation | `__HAL_UART_CLEAR_OREFLAG` | ST HAL 벤더 매크로 |
| 8.7 | deviation | 공개 API 함수 | 다른 App 모듈 또는 진단 경로에 노출 |
| 21.6 | 조건부 deviation | `UART_RPI_DEBUG=1`의 `printf` | 디버그 빌드 한정. 기본값 0에서는 컴파일아웃 |
| 10.8 | 코드로 회피 | CRC 복원 시 `uint32_t` 경유 | 합성식 직접 캐스트를 사용하지 않음 |

```bash
bash tools/run_static_analysis.sh     # -> "정적분석 통과"
```

> [!warning] 로컬 통과가 CI 통과를 보장하지 않는다
> CI는 `ubuntu-latest`에서 `apt-get install -y cppcheck`를 실행해 버전을 고정하지
> 않는다. 로컬 결과는 cppcheck 2.21이며, CI 버전과 차이가 있는지는 각 실행 로그에
> `cppcheck --version`을 남겨 확인해야 한다.

---

## 7. 알려진 이슈

| ID | 항목 | 우선순위 | 상태 | 조치 방향 |
|---|---|---|---|---|
| STM-60-01 | `ERR_BAD_CRC`/`ERR_BAD_LEN` 을 안 보냄 | P0 | 열림 | CRC/LEN 거절 카운터를 `proto_status` 에 추가해 양 끝 대조 가능하게 |
| STM-60-02 | 길이 검증 느슨 | P1 | 열림 | zero-payload 는 `LEN==0` 강제, `SCAN_START` 는 정확한 크기만 |
| STM-60-03 | `Receive_IT` 재등록 반환 무시 | P1 | 열림 | 실패 시 retry / fault 상태 |
| STM-60-04 | `HAL_UART_Transmit` 100ms 블로킹 | P1 | 열림 | IT/DMA TX + 유한 큐 + 우선순위(fatal ERROR ≫ 명령 응답 ≫ SCAN_DATA ≫ STATUS) |
| STM-60-05 | UART 에러 원인별 카운터 없음 | P1 | 열림 | ORE/FE/NE/PE 분리 + 파서 리셋 정책 명시 |
| STM-60-06 | `init` 이 static state 미리셋 | P2 | 열림 | `s_scan_count`·`s_tx_fail`·`s_rb_ovf`·파서 상태·status tick 타임스탬프 |
| STM-60-07 | 와이어 버전 없음 | P2 | 보류 | 현재는 드라이버의 payload 길이 불일치 경고가 대신 잡는다 |
| STM-60-08 | `tx_fail`/`rx_overflow` getter 에 호출자가 없다 | P2 | 열림 | 5장. `status_tick` 이 내부 변수를 직접 읽는다. 열어 둘지 지울지 결정 |

---

## 8. 참고

- 소스: `STM32/App/uart_rpi/uart_rpi.c`, `.h`
- 계약: [[10 Protocol v6 통신 계약]] (원본은 RPi 사본)
- 상위: [[61 scan 2축 스캔 시퀀서]]
- 결선: [[62 펌웨어 런타임 연결]]
- 대응 드라이버: [[20 turret_driver 커널 드라이버]]

### 8.1 개정 이력

| 날짜 | 변경 |
|---|---|
| 2026-08-24 | `claims-60` 재대조 반영 — UART 오류·진단 의미, point_count ABI, 링버퍼·프레임 크기, 의존 방향, 근거 등급 정정 |
