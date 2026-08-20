# STM32 펌웨어 정적분석

**원본: [STM32/docs/static_analysis.md](https://github.com/VEDA-4th-Oppenheimer/STM32/blob/main/docs/static_analysis.md)**

`tools/run_static_analysis.sh`로 push 전 로컬 검사. 우리 코드(`App/`, `Core/Src/main.c`)만
검사하고 지적사항이 있으면 exit 1 → CI 게이트로 머지를 막습니다.

관련: [정적 분석 및 예외 관리 가이드라인](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/4096023)
· [코드 품질 및 자동화 가이드라인 v2.0](https://lkj000619.atlassian.net/wiki/spaces/VPT/pages/13991958)
