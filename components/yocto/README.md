# Yocto

임베디드 리눅스 이미지 빌드 관련 문서를 둔다 — 레시피, `local.conf` 설정과 그 이유,
레이어 구성, 빌드 삽질 기록.

빌드 절차처럼 "따라 하면 되는 것"은 `guides/` 로 보내고, 여기에는 **왜 그렇게 구성했는지**를
남긴다.

| 문서 | 내용 |
|---|---|
| [image.md](image.md) | 빌드 호스트 구성, `ybuild.sh`, 재현성 |
| [layers-and-recipes.md](layers-and-recipes.md) | 레이어 7종, `local.conf`, 레시피 8종 해설 |
| [kernel-drivers-dt.md](kernel-drivers-dt.md) | 커널 핀, 오버레이·`compatible` 짝, `led_sw` probe defer |

빌드·플래시 절차는 [../../guides/yocto-build.md](../../guides/yocto-build.md).
