# turret_driver 커널 드라이버

| 항목 | 내용 |
|---|---|
| 문서 ID | `ADTS-DRV-20` |
| 파트 | Driver (`/dev/turret`) |
| 담당 | 이현우 |
| 대상 소스 | `RPi/driver/turret_driver.c` (620줄), `RPi/driver/overlays/turret-overlay.dts` (34줄), `RPi/driver/turret_test.c` (243줄), `RPi/driver/Makefile` (101줄) |
| 기준 코드 | RPi `2a683ee` (2026-08-21). 드라이버 관련 파일은 `f51ba0f` 이후 변경 없음 |
| 커널 | 6.12.y, vermagic `6.12.75+rpt-rpi-v8 SMP preempt mod_unload modversions aarch64` |
| 상태 | 구현 완료 · 소스/산출물 검증 · 2026-08-19 실기 기록 확인 |

---

## 1. 개요

`/dev/turret` 은 STM32 UART 바이트 스트림과 유저 데몬 사이의 커널 경계다. serdev
클라이언트 + misc device 조합으로 구현했다.

1. 와이어 프레임을 조립·검증한다 (SOF / LEN / CRC16)
2. 스캔 점은 kfifo 스트림, 제어 이벤트는 상태 캐시 + 통지로 나눈다
3. 데몬의 ioctl 을 Protocol v6 프레임으로 만들어 UART 로 내보낸다
4. heartbeat 카운터(`pong_seq`)만 올리고 판정은 하지 않는다

### 1.1 두 채널 분리

스캔 점은 한 판에 4만 개가 넘으므로 ioctl 로 하나씩 받으면 syscall 비용이 크다.
제어 상태는 개수가 적고 최신값만 필요하다.

| 채널 | 전달 | 소비 | 근거 |
|---|---|---|---|
| 고속 스캔 점 (`CMD_SCAN_DATA`) | kfifo 1024개 | `read()` 배치 + `poll()` | syscall 당 64점 |
| 저속 제어 상태 | `turret_link_state` 캐시 | `ioctl(GET_STATE)` | 누적이 아니라 최신값만 필요 |

### 1.2 얇은 드라이버 원칙

드라이버는 좌표 변환을 하지 않는다. STM32 가 올린 기구각과 거리를 그대로 통과시키고
계약 좌표계 해석은 데몬이 한다. link_dead 타이머도 돌리지 않는다 — `pong_seq` 만
올리고 300ms 판정은 데몬이 자기 `CLOCK_MONOTONIC` 으로 한다.

ABI가 유지되는 범위에서 좌표 해석이나 heartbeat 정책을 바꿀 때는 커널 모듈을 다시
만들 필요가 없다. 커널 모듈 교체는 `rmmod`/`modprobe` 와 vermagic 정합이 걸린 작업이다.

---

## 2. 적용 범위와 경계

| 다루는 것 | 다루지 않는 것 |
|---|---|
| 프레임 파싱·조립, kfifo, ABI | `/dev/imu` 내부 (송영빈) |
| serdev 바인딩과 DT 오버레이 | `/dev/led_sw` 내부 (강유근) |
| `turret_test` 브링업 클라이언트 | 데몬 FSM → 30 daemon core 이벤트 루프와 FSM |

같은 `driver/` 에서 `make` 한 번에 셋이 빌드되지만 IMU·LED 드라이버는 범위 밖이다.

### 2.1 결선과 부팅 조건

| 항목 | 값 |
|---|---|
| 포트 | RPi UART0 (PL011), GPIO14 TX / GPIO15 RX |
| 설정 | 115200 8N1, 흐름제어 없음 |
| compatible | `adts,turret` |
| 노드 | `/dev/turret` (misc, dynamic minor) |

```
RPi GPIO14 (TX, 물리핀 8)  ->  STM32 PA10 (USART1_RX)
RPi GPIO15 (RX, 물리핀 10) <-  STM32 PA9  (USART1_TX)
GND 공통
```

```
# /boot/firmware/config.txt
enable_uart=1
dtoverlay=disable-bt          # BT를 mini-UART로 넘기고 PL011(uart0) 확보
```

`/boot/firmware/cmdline.txt` 에서 `console=serial0,115200` 을 제거해야 시리얼 콘솔이
UART0 를 점유하지 않는다.

---

## 3. 설계

### 3.1 serdev 선택 근거

| serdev | tty 유저 공간 |
|---|---|
| 프레임 조립이 커널에서 끝나 유저는 온전한 점만 본다 | 유저가 바이트 스트림을 다시 조립 |
| kfifo 배치 전달로 syscall 감소 | read 마다 부분 프레임 처리 |
| DT 로 바인딩이 선언적 | 장치 경로가 부팅 순서에 의존 |
| 부트캠프 요건 "디바이스 드라이버 직접 구현" 충족 | 미충족 |

대가는 커널 모듈 빌드·vermagic 관리이며, Yocto 로 커널과 같은 빌드에서 생성해
해결했다 (72 커널 드라이버 DT 연결).

### 3.2 락 두 종류

| 락 | 보호 대상 | 컨텍스트 |
|---|---|---|
| `dev->lock` (mutex) | TX 프레임 직렬화 | ioctl (프로세스) |
| `dev->st_lock` (spinlock) | `st` 스냅샷 원자성 | RX 콜백 + ioctl |

ioctl 의 mutex 는 RX 콜백이 잡을 수 없다(콜백은 슬립 불가 컨텍스트). 그래서 상태에는
spinlock 을 따로 둔다.

kfifo 는 별도 락이 없다. 운영 계약은 상주 데몬 하나가 장치를 열어 소비하는 것이다.
이 계약에서는 생산자가 serdev RX 콜백 하나, 소비자가 `read()` 하나인 SPSC 구조가 되어
kfifo 자체 보장을 사용할 수 있다.

### 3.3 FIFO 깊이 1024

```c
#define SCAN_FIFO_POINTS 1024      /* turret_driver.c:61 */
DECLARE_KFIFO(scan_fifo, struct proto_scan_point, SCAN_FIFO_POINTS);
```

18B × 1024 = 18KiB의 요소 저장 공간이며, 라이다 100Hz 기준 약 10.24초치다.
`struct turret_dev` 안에 인라인이라 probe 의 `devm_kzalloc` 이 약 20KiB가 되며 probe는
비원자 컨텍스트다. 이 깊이는 일시적인 소비 지연을 흡수하지만 손실 없음을 보장하지
않는다. FIFO가 차면 해당 점은 버리고 ratelimited 경고를 남긴다.

---

## 4. 구현 — 코드 해설

### 4.1 파일 구성

| 파일 | 줄 | 역할 |
|---|---:|---|
| `turret_driver.c` | 620 | serdev 클라이언트 + misc device |
| `overlays/turret-overlay.dts` | 34 | UART0 자식 노드 선언 |
| `turret_test.c` | 243 | 브링업 CLI |
| `Makefile` | 101 | kbuild + 유저 도구 + dtbo |

### 4.2 `struct turret_dev` (`:64~95`)

| 필드 | 소유 컨텍스트 | 의미 |
|---|---|---|
| `serdev`, `misc` | probe / remove | UART 클라이언트와 캐릭터 디바이스 |
| `lock` | ioctl | TX 직렬화 (mutex) |
| `st_lock` | RX + ioctl | 상태 원자성 (spinlock) |
| `rx_wq` | RX 생산자 / 대기자 | 데이터·통지 wakeup |
| `scan_fifo` | RX / read | `proto_scan_point` × 1024 |
| `st` | RX writer / ioctl reader | 최신 `turret_link_state` |
| `last_point_count` | RX writer | `SCAN_DONE` 의 수. 현재 ABI에는 노출하지 않음 |
| `notify_pending` | RX writer / GET_STATE 소비 | HOMED·DONE·ERROR 엣지 |
| `rx_buf` / `rx_idx` / `rx_need` | RX 콜백 | 스트리밍 파서 상태 |

`g_dev` 전역 하나만 두므로 단일 하드웨어 인스턴스만 지원한다.
`file->private_data` 를 쓰지 않아 여러 open 이 같은 FIFO·캐시를 공유한다.

### 4.3 송신 — `turret_send_frame()` (`:100`)

```c
static int turret_send_frame(struct turret_dev *dev, u8 cmd,
			     const void *payload, u8 plen)
{
	u8  frame[PROTO_MAX_FRAME];
	u16 crc;
	int total, ret;

	if (plen > PROTO_MAX_PAYLOAD)          /* CWE-120 경계검사 */
		return -EINVAL;

	frame[0] = PROTO_SOF;
	frame[1] = cmd;
	frame[2] = plen;
	if (plen && payload)
		memcpy(&frame[PROTO_HEADER_LEN], payload, plen);

	total = PROTO_HEADER_LEN + plen;
	crc   = proto_crc16(frame, (proto_u16)total);
	frame[total]     = crc & 0xFF;          /* 리틀엔디언 */
	frame[total + 1] = (crc >> 8) & 0xFF;
	total += PROTO_CRC_LEN;
	...
	ret = serdev_device_write(dev->serdev, frame, total, HZ);
	return (ret == total) ? 0 : (ret < 0 ? ret : -EIO);
}
```

- `plen > PROTO_MAX_PAYLOAD` 검사가 스택 버퍼 오버플로(CWE-120)를 막는 지점이다.
  `frame[]` 이 `PROTO_MAX_FRAME` 고정이므로 이 검사가 빠지면 스택을 넘는다
- 반환 0 은 프레임 전체를 serdev 에 넘겼다는 뜻이지 STM32 의 ACK 가 아니다
- `serdev_device_write(..., HZ)` 는 최대 1초 블로킹. ioctl 프로세스 컨텍스트라 안전

TX 덤프 로그는 `KERN_DEBUG`다. heartbeat가 100ms 주기이므로 프레임 단위 디버그 로그를
활성화할 때는 커널 링버퍼의 로그량을 함께 관리한다.

### 4.4 상태 플래그 — `st_flags_update()` (`:142`)

```c
/* st.flags 를 st_lock 아래에서 갱신한다. ioctl 이 dev->lock 을 쥐고 있어도
 * RX 콜백은 그 뮤텍스를 안 잡으므로, flags 읽기-수정-쓰기가 RX 의 갱신과
 * 겹칠 수 있다. 둘 다 같은 스핀락을 거쳐야 의미가 있다. */
static void st_flags_update(struct turret_dev *dev, u8 set, u8 clear)
```

3.2 의 락 설계가 드러나는 지점이다. mutex 를 쥐어도 RX 로부터 보호되지 않는다.

### 4.5 수신 파서 — `turret_rx_callback()` (`:175`)

```c
for (i = 0; i < count; i++) {
	u8 b = buf[i];

	/* ① SOF 탐색 */
	if (dev->rx_idx == 0) {
		if (b != PROTO_SOF) continue;
		dev->rx_buf[0] = b; dev->rx_idx = 1; dev->rx_need = 0;
		continue;
	}

	/* 오버플로우 방지(CWE-120) */
	if (dev->rx_idx >= PROTO_MAX_FRAME) { dev->rx_idx = 0; continue; }

	dev->rx_buf[dev->rx_idx++] = b;

	/* ② 헤더 완성 -> 전체 길이 확정 */
	if (dev->rx_idx == PROTO_HEADER_LEN) {
		u8 len = dev->rx_buf[2];
		if (len > PROTO_MAX_PAYLOAD) {          /* CWE-120 */
			pr_warn("turret: bad LEN %u\n", len);
			dev->rx_idx = 0; continue;
		}
		dev->rx_need = PROTO_HEADER_LEN + len + PROTO_CRC_LEN;
	}

	/* ③ 프레임 완성 -> CRC -> 디스패치 */
	if (dev->rx_need && dev->rx_idx >= dev->rx_need) { ... }
}
```

경계 검사가 두 겹이다 — `rx_idx >= PROTO_MAX_FRAME`(버퍼 자체)와
`len > PROTO_MAX_PAYLOAD`(선언된 길이). 둘째가 없으면 손상된 LEN 이 `rx_need` 를
부풀려 프레임 경계를 잃는다.

```c
u16 rx_crc = dev->rx_buf[dev->rx_need - 2]
	   | ((u16)dev->rx_buf[dev->rx_need - 1] << 8);
u16 calc   = proto_crc16(dev->rx_buf, (proto_u16)(PROTO_HEADER_LEN + len));

if (rx_crc == calc) {
	/* st 갱신 전체를 한 임계구역으로 묶는다. 프레임 하나가 여러 필드를
	 * 함께 바꾸므로(예: CMD_STATUS 는 각도와 flags 를 같이),
	 * 필드별로 잠그면 스냅샷이 여전히 섞인다. */
	spin_lock_irqsave(&dev->st_lock, fl);
	switch (cmd) { ... }
	spin_unlock_irqrestore(&dev->st_lock, fl);
}
```

임계구역을 프레임 단위로 잡는다. 필드마다 잠그면 `GET_STATE` 가 "각도는 새 값,
flags 는 옛 값"인 스냅샷을 볼 수 있다.

| CMD | 상태·FIFO 변화 | wakeup |
|---|---|---|
| `PONG` | `pong_seq++`, `link_alive=1` | 없음 |
| `HOMED` | 홈 provenance 캐시, `STF_HOMED` set | notify |
| `STATUS` | 각도·flags·진단 5종·`status_seen=1` | 없음 |
| `SCAN_DATA` | `kfifo_put` | `rx_wq` |
| `SCAN_DONE` | `last_point_count`, `STF_SCANNING` clear | notify |
| `ERROR` | `last_err` + `last_err_axis` | notify |

`STATUS` 는 1Hz 이고 데몬의 100ms tick 이 `GET_STATE` 를 읽으므로 별도 통지를 하지
않는다. 통지를 남발하면 tick 마다 깨우는 것과 같아진다.

`link_alive`는 PONG을 한 번 받은 뒤 1로 남으며 드라이버가 다시 0으로 내리지 않는다.
따라서 이 필드는 현재 링크 생존 여부가 아니라 PONG 수신 이력에 가깝다. 현재 생존 여부는
데몬이 `pong_seq` 증가 시각을 기준으로 판정한다.

```c
case CMD_SCAN_DATA:
	if (len == sizeof(struct proto_scan_point)) {
		struct proto_scan_point pt;
		memcpy(&pt, pl, sizeof(pt));
		/* SPSC: 별도 락 없이 kfifo 로 밀어넣음 */
		if (!kfifo_put(&dev->scan_fifo, pt))
			pr_warn_ratelimited("turret: scan fifo full, point dropped\n");
		wake_up_interruptible(&dev->rx_wq);
	}
	break;
```

### 4.6 읽기 — `turret_read()` (`:352`)

```c
/* proto_scan_point 정수 배수만 전달(부분 점 금지) */
max = count - (count % sizeof(struct proto_scan_point));
if (max == 0)
	return -EINVAL;      /* 버퍼가 1점보다 작음 */

if (kfifo_is_empty(&dev->scan_fifo)) {
	if (f->f_flags & O_NONBLOCK)
		return -EAGAIN;
	ret = wait_event_interruptible(dev->rx_wq,
				       !kfifo_is_empty(&dev->scan_fifo));
	if (ret) return ret;  /* -ERESTARTSYS */
}

ret = kfifo_to_user(&dev->scan_fifo, ubuf, max, &copied);
```

부분 점을 넘기지 않는다. 유저 버퍼를 점 크기의 배수로 내림하므로 데몬은 `read()`
반환값을 `sizeof` 로 나누면 점 개수를 얻는다.

`read()` 는 통지를 소비하지 않고 `GET_STATE` 는 점을 소비하지 않는다. 두 채널이
서로를 삼키지 않는다는 계약이다.

### 4.7 poll — `turret_poll()` (`:386`)

```c
if (!dev)
	return EPOLLERR;

poll_wait(f, &dev->rx_wq, wait);

if (!kfifo_is_empty(&dev->scan_fifo))
	mask |= EPOLLIN | EPOLLRDNORM;      /* 스캔 점 있음 */
if (READ_ONCE(dev->notify_pending))
	mask |= EPOLLIN;                    /* 통지 -> GET_STATE 확인 */
```

`POLLIN` 은 "점이 있다"는 뜻이 아니다. 통지만으로도 깨어나므로 `read()` 를
`EAGAIN` 까지 돌린 뒤 `GET_STATE` 로 상태를 확인해야 한다.

`EPOLLERR` 는 link dead 를 뜻하지 않는다. 현재 구현은 `dev` 가 NULL 인 경우에만
`EPOLLERR` 를 낸다. 링크 타임아웃 판정은 데몬이 `pong_seq` 와 자기 단조시계로 한다.

### 4.8 ioctl — `turret_ioctl()` (`:407`)

#### `TURRET_HOME`

`STF_HOMED` 를 먼저 내리고 `CMD_HOME` 을 보낸다. 이전 홈 완료 상태를 그대로 소비하는
경우를 줄이기 위한 처리다. 다만 Protocol v6의 주기 `STATUS`가 STM32가 새 HOME을
처리하기 전에 이전 `homed` 값을 다시 올릴 수 있으므로, `homed==1`만으로 이번 요청의
완료를 절대적으로 식별할 수는 없다. 데몬의 요청 상태와 STM32의 busy/error 응답을 함께
사용해야 한다.

#### `TURRET_SCAN_START` (`:455~490`)

```c
kfifo_reset_out(&dev->scan_fifo);
dev->last_point_count = 0;
{
	unsigned long fl;
	spin_lock_irqsave(&dev->st_lock, fl);
	dev->st.last_err = ERR_NONE;
	spin_unlock_irqrestore(&dev->st_lock, fl);
}

/* STF_SCANNING 을 여기서 세운다. STM 의 CMD_STATUS 를 기다리면
 * 그 사이 데몬이 "스캔 안 도는데?" 로 오판한다. 전송 실패 시 되돌린다. */
st_flags_update(dev, STF_SCANNING, 0);

ret = turret_send_frame(dev, CMD_SCAN_START, &ss, sizeof(ss));
if (ret < 0)
	st_flags_update(dev, 0, STF_SCANNING);   /* 롤백 */
```

FIFO 를 비우는 이유는 중단된 스캔이나 데몬이 다 읽지 않고 종료한 경우 이전 스캔의
점이 남아 격자 셀 충돌을 만들기 때문이다.

`kfifo_reset()` 이 아니라 `kfifo_reset_out()` 을 쓴다. 전자는 in/out 포인터를 모두
건드려 생산자(RX 콜백)와 동시 접근하면 깨진다. 후자는 소비자측 포인터만 옮기므로
단일 소비자일 때 사용할 수 있다. 이 구간은 ioctl 송신끼리만 직렬화하는 `dev->lock`
아래이며 일반 `read()`는 같은 mutex를 잡지 않는다.

`STF_SCANNING` 을 명령 시점에 세운다. STM32 의 `CMD_STATUS` 를 기다리면 그 사이 데몬이
스캔 미시작으로 오판한다.

#### `TURRET_GET_STATE`

`notify_pending` 을 0 으로 만들고 `st_lock` 아래에서 로컬 스냅샷을 뜬 뒤 락 밖에서
`copy_to_user` 한다. 스핀락 안에서 유저 메모리를 만지면 페이지 폴트로 슬립할 수 있어
금지다.

통지 클리어가 스냅샷보다 먼저이므로 그 사이 도착한 이벤트는 다음 epoll 턴에서
처리된다. `notify_pending`은 이벤트 큐가 아니라 1비트이므로 여러 HOMED·DONE·ERROR가
GET_STATE 전에 연속 도착하면 하나의 wakeup으로 합쳐지고 캐시에는 최신 상태만 남는다.

### 4.9 probe / remove (`:541`, `:588`)

```c
dev = devm_kzalloc(&serdev->dev, sizeof(*dev), GFP_KERNEL);
mutex_init(&dev->lock);
spin_lock_init(&dev->st_lock);
init_waitqueue_head(&dev->rx_wq);
INIT_KFIFO(dev->scan_fifo);

serdev_device_set_drvdata(serdev, dev);
serdev_device_set_client_ops(serdev, &turret_serdev_ops);

ret = serdev_device_open(serdev);
if (ret) { dev_err(...); return ret; }

serdev_device_set_baudrate(serdev, 115200);
serdev_device_set_flow_control(serdev, false);
serdev_device_set_parity(serdev, SERDEV_PARITY_NONE);

dev->misc.minor = MISC_DYNAMIC_MINOR;
dev->misc.name  = "turret";
dev->misc.fops  = &turret_fops;
dev->misc.mode  = 0666;

ret = misc_register(&dev->misc);
if (ret) { dev_err(...); serdev_device_close(serdev); return ret; }

g_dev = dev;
```

1. `serdev_device_open` 을 client_ops 등록 뒤에 한다. 순서가 바뀌면 첫 바이트를
   놓칠 수 있다
2. 실패 경로가 remove 와 다르다. `misc_register` 실패 시 `serdev_device_close` 만
   하고 `misc_deregister` 는 하지 않는다. 초기화·해제 경로를 한 함수로 합치면 이
   차이가 무너진다
3. `devm_kzalloc` 로 잡은 것은 수동으로 해제하지 않는다

`remove` 는 `misc_deregister` → `serdev_device_close` → `g_dev = NULL` 순으로,
등록의 역순이다.

### 4.10 DT 오버레이

```dts
/dts-v1/;
/plugin/;

&uart0 {
	status = "okay";

	turret {
		compatible = "adts,turret";
	};
};
```

이 문자열이 드라이버의 `turret_dt_ids` 와 정확히 일치해야 `probe()` 가 호출된다.
빌드는 성공하는데 장치가 생기지 않는 대부분의 원인이 여기다.

`dtc -@` 로 `__symbols__` 를 포함해야 `&uart0` phandle 참조가 런타임에 해석된다.

### 4.11 브링업 클라이언트 (`turret_test.c`)

`home`/`scan`/`stop`/`disarm`/`ping`/`state`/`stream` 서브커맨드를 ioctl·read 로
직접 매핑한다. 데몬 없이 계층을 가르는 도구다.

```bash
sudo systemctl stop adts-daemon     # 장치 점유 해제
sudo ./turret_test ping
sudo ./turret_test state
sudo ./turret_test home
sudo ./turret_test stream
```

### 4.12 빌드 (`driver/Makefile`)

| 산출물 | 비고 |
|---|---|
| `turret_driver.ko` | kbuild `obj-m` |
| `imu_driver.ko`, `led_sw_driver.ko` | 범위 밖이지만 같은 `all` 로 빌드 |
| `turret_test` | 유저 도구 |
| `*.dtbo` | `dtc -@` |

- 헤더 탐색 순서: 유저 도구는 `driver/protocol.h` → `shared/protocol.h` → 상위
  `protocol.h`, 커널은 `driver` → RPi 루트 → `shared`
- 커널·유저 모두 `-Wall -Wextra -Werror` + stack protector / FORTIFY / PIE
- `make rpi` 가 `ARCH=arm64`, `CROSS_COMPILE`, `KDIR` 을 맞춤

---

## 5. 인터페이스

### 5.1 권장 소비자 패턴

```c
/* O_NONBLOCK 으로 열고 epoll 사용 */
1. EPOLLIN 수신
2. read() 를 EAGAIN 까지 반복 — 점 FIFO 를 비운다
3. ioctl(TURRET_GET_STATE) 로 통지와 최신 상태 확인
4. DONE / ERROR / STATUS 를 명시적으로 소비
5. FSM 전이와 타임아웃은 유저 공간이 결정
```

데몬의 `core_on_turret_event()` 가 이 순서다.

### 5.2 `turret_link_state`

| 그룹 | 필드 | 도입 |
|---|---|---|
| 링크 | `link_alive`, `pong_seq` | v4 |
| 상태 | `flags`, `cur_pan_ddeg`, `cur_tilt_ddeg` | v4 |
| 오류 | `last_err`, `last_err_axis` | v4 / v6 |
| 홈 provenance | `home_*_encoder_raw`, `home_*_ddeg` | v5 |
| 진단 | 카운터 5종 + `status_seen` | v6 |

홈 provenance 를 올리는 이유는 복구 가능성이다. `*_ddeg` 는 영점 상수를 적용한
결과이므로 영점이 틀리면 raw 로부터 재계산해야 한다.

이 구조체가 v5·v6 에서 두 번 커져 `_IOR` 인코딩이 바뀌었다. 구버전 유저스페이스는
`-ENOTTY` 로 실패하므로 드라이버와 데몬을 함께 재빌드한다.

---

## 6. 검증

| 항목 | 방법 | 등급 | 결과 |
|---|---|---|---|
| ARM64 커널 모듈 산출물 | `file`, `strings` | B | AArch64 ELF, vermagic 일치 확인 |
| `turret_test.c` 컴파일 | AArch64 GCC `-fsyntax-only -Werror` | B | 2026-08-24 통과 |
| DT 오버레이 산출물 | `file` | B | DTB v17, 275B 확인 |
| 실기 스캔 완주 | 2026-08-19 산출물·검증 기록 | A | 40,400 셀 중 40,088 유효 |
| v6 15B STATUS 파싱 | 같은 실기 기록 | C | `status_seen=1`, 카운터 5종 수신 기록 |

### 6.1 진단

```bash
sudo dmesg -w                          # 드라이버 로그
watch -n1 sudo ./turret_test state     # 링크 상태 / pong_seq
```

| 관측 | 원인 |
|---|---|
| `pong_seq` 가 안 오름 | PING 송신 경로, TX 실패, 전원·배선·오버레이, STM32 응답 경로를 순서대로 점검 |
| `pong_seq` 는 오르는데 `status_seen=0` | 첫 STATUS 주기 전이거나 구버전 펌웨어, STATUS 송신 경로·메인루프를 점검 |
| `unknown cmd 0x..` | CRC가 맞는 미지원 명령. 프로토콜 세대와 송신 측 명령을 점검 |
| `turret: payload 길이 불일치` | 해당 CMD 구조체 크기 또는 펌웨어·헤더 버전을 점검 |
| `turret: bad LEN` | 선언 길이가 최대값을 넘은 프레임. 링크 노이즈와 송신 파서를 함께 점검 |
| `scan fifo full` | FIFO push 실패로 현재 점이 버려짐. 소비자 정체·다중 접근·입력률을 점검 |

`pr_debug` TX 덤프 사용 여부는 대상 커널 설정에 따른다. 덤프가 보이지 않으면 커널
설정을 확인하고 필요 시 모듈을 `-DDEBUG`로 빌드한다.

커널 로그의 `-517` 은 `-EPROBE_DEFER` 다.

---

## 7. 참고

- 소스: `RPi/driver/turret_driver.c`, `RPi/driver/overlays/turret-overlay.dts`, `RPi/driver/turret_test.c`, `RPi/driver/Makefile`
- 계약: 10 Protocol v6 통신 계약
- 소비자: 30 daemon core 이벤트 루프와 FSM
- 배포: 33 빌드 systemd 배포, 72 커널 드라이버 DT 연결
