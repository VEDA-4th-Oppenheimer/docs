# docs

VEDA 4th Oppenheimer 팀 문서 저장소입니다.

> **이 레포에는 코드를 두지 않습니다.** `.md` 문서와 `assets/`의 이미지만 커밋합니다.
> 소스 코드는 각 컴포넌트 레포에, 여기에는 "왜/무엇을" 만 남깁니다.

## 목차

### 전체 그림
- [시스템 아키텍처](overview/architecture.md)
- [요구사항](overview/requirements.md)
- [용어집](overview/glossary.md)

### 인터페이스 (컴포넌트 간 약속)
- [STM32 ↔ RPI UART 프로토콜](interfaces/stm32-rpi-uart.md)

### 기술 결정 기록 (ADR)
- [decisions/](decisions/) — 왜 그 기술을 골랐는지

### 가이드
- [guides/](guides/) — 환경 설정, 빌드, 트러블슈팅

### 컴포넌트별 문서
| 컴포넌트 | 문서 |
|---|---|
| STM32 | [components/stm32/](components/stm32/) |
| Raspberry Pi | [components/rpi/](components/rpi/) |
| Qt | [components/qt/](components/qt/) |
| Yocto | [components/yocto/](components/yocto/) |
| OpenSDK | [components/opensdk/](components/opensdk/) |
| 자동 캘리브레이션 | [components/calibration/](components/calibration/) |

### 회의록
- [meetings/](meetings/)

---

문서를 추가하기 전에 [작성 규칙](CONTRIBUTING.md)을 먼저 읽어주세요.
