# STM32 펌웨어

STM32F401RE 펌웨어(`adts`) 관련 문서를 둔다.

| 문서 | 담당 |
|---|---|
| [motor.md](motor.md) — 2축 스텝모터 구동 및 가감속 제어 (S-Curve Q8, 750 PPS, 사다리꼴 램프) | 강유근 / 송영빈 |
| [encoder.md](encoder.md) — 14비트 I2C 각도 엔코더 (MT6701, 220Ω 직렬 댐핑, 3단계 버스 복구) | 강유근 |
| [scan.md](scan.md) — 2축 스캔 시퀀서 (9단계 FSM, SC_PARK 안전 제어, Serpentine 40ms 정착) | 강유근 / 이현우 |
| [lidar.md](lidar.md) — 라이다 수신 드라이버 | 송영빈 |
| [uart-rpi.md](uart-rpi.md) — RPi 링크 프로토콜 어댑터 | 이현우 |
| [runtime.md](runtime.md) — 초기화·메인루프·HAL 콜백·IWDG 결선 | 이현우 / 강유근 / 송영빈 |

`App/` 모듈 단위로 파일을 나누고, 새 문서를 추가하면 위 표에 한 줄 추가한다.
