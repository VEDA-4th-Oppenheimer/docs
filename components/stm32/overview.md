# STM32 펌웨어 (`adts`)

**원본: [STM32 저장소 README](https://github.com/VEDA-4th-Oppenheimer/STM32/blob/main/README.md)**

디렉토리 구조(3층 분리: `Core`/`Drivers` · `App` · `shared`), 빌드·플래시,
정적분석, `protocol.h` 동기화 규칙, CODEOWNERS가 거기 있습니다.

> 코드와 같은 저장소에 있어야 같은 PR에서 리뷰되고 안 썩습니다.
> 여기로 복사해오지 마세요.

## Confluence

[STM32 Firmware](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/5505025) ·
[탈조 감지·재영점 메커니즘 설계서](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/44728327) ·
[Protocol](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/3833923) ·
[IWDG](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/8454164)

## ⚠️ README의 프로토콜 버전이 낡았습니다

저장소 README가 `PROTO_VERSION=3`이라고 적고 있습니다. 실제는 **v6**입니다.
[작성 규칙 0번](../../CONTRIBUTING.md)대로 값을 적지 말고 헤더를 링크하는 편이 낫습니다.
