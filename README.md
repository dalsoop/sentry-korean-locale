# sentry-korean-locale

Sentry self-hosted 한국어 locale 번역 파일.

- **15,173 entries** (Sentry 공식 ko 199 → 우리가 15,173 로 확장)
- **1.3 MB ko.js** (공식 초기 9 KB 대비 약 130배)
- 번역 엔진: Google **TranslateGemma 27B** (BF16, llama.cpp, 4 GPU tensor-split)
- 대상 Sentry 버전: 25.10.x (공식 ko chunk hash `711dae3eefae37a1` 기준)

## 빠른 적용 (docker 컨테이너 교체)

```bash
# 1) 현재 서빙 중인 ko.* 해시 확인
CONTAINER=sentry-self-hosted-web-1
CHUNK_DIR=/usr/src/sentry/src/sentry/static/sentry/dist/chunks/locale

OLD=$(docker exec $CONTAINER ls $CHUNK_DIR | grep -oE 'ko\.[a-f0-9]+\.js$' | head -1)
echo "current: $OLD"

# 2) dist/ko.js 를 그 해시 경로에 덮어쓰기
docker cp dist/ko.js        $CONTAINER:$CHUNK_DIR/$OLD
docker cp dist/ko.js.gz     $CONTAINER:$CHUNK_DIR/$OLD.gz

# 3) nginx cache flush + reload
docker exec sentry-self-hosted-nginx-1 sh -c 'rm -rf /var/cache/nginx/* 2>/dev/null; nginx -s reload'

# 4) 사용자 language = ko 로 설정 (admin 이면 shell 로)
docker exec -i $CONTAINER python -c "
from sentry.users.models.user import User
from sentry.users.models.user_option import UserOption
for u in User.objects.filter(is_superuser=True):
    UserOption.objects.set_value(u, key='language', value='ko')
    print('set ko for', u.email)
"

# 5) 브라우저 F5
```

자동화 스크립트: `scripts/deploy.sh <sentry-lxc-id-or-host>` 참고.

## 캐시 무효화 (옵션)

Sentry 가 locale chunk 파일명에 content hash 를 붙여 캐시를 관리하므로,
같은 해시로 덮어쓰면 브라우저가 캐시된 구 버전을 계속 씀.
`scripts/bust-cache.sh` 는 해시를 새로 만들어 `entrypoints/app.js` 등의
참조 해시도 함께 치환한다.

## 구조

```
sentry-korean-locale/
├── dist/
│   ├── ko.js           컴파일된 webpack 청크 (1.3 MB, 15 173 entries)
│   └── ko.js.gz        gzipped
├── src/
│   ├── translations.json   {msgid: msgstr} 깔끔한 딕셔너리 (기계 번역 결과 + 기존 Sentry 공식)
│   └── state.json         origin 태그 포함 (existing/translated/scanned/skip-svg/skip-tz)
├── scripts/
│   ├── deploy.sh       docker cp + nginx reload 자동화
│   └── bust-cache.sh   파일 해시 재생성 + app.js 참조 치환
└── README.md
```

## 번역 origin 태그

`state.json` 의 각 entry `origin` 값:
- `existing` — Sentry 공식 ko 번역 그대로
- `translated` — TranslateGemma 27B 기계 번역
- `scanned` — JS 번들 스캔으로 추가 발견한 msgid
- `skip-svg` / `skip-tz` — SVG path / timezone 데이터 (번역 불필요, 원본 유지)

## 번역 품질

- **UI 라벨/버튼**: 매우 양호 (Save→저장, Cancel→취소)
- **중간 문장**: 대체로 자연스러움
- **긴 설명문**: 가끔 모델이 문장 요약하거나 첨언 (경미)
- **플레이스홀더**: `%s`, `{name}`, `[tag]` 대부분 보존 (극단 케이스 순서 섞임 가능)

더 개선하려면 해당 msgid 를 수동으로 `translations.json` 에서 수정 후 `scripts/build.sh` 로 ko.js 재생성.

## 재생성 / 커스터마이즈

번역 엔진 재사용:

```bash
# 원본 프로젝트 (번역 인프라)
git clone https://github.com/dalsoop/gemma-translate.git
# CLI 설치 후
gemma-translate llama-install --from-local <gemma-27b-dir>
gemma-translate llama-up 0,1,2,3 8080

# 이 리포의 translations.json 을 특정 msgid만 re-translate
translate -i src/translations.json -o src/translations.ko.json -w 16
```

## 라이선스

- **번역 결과물 (`ko.js`, `translations.json`)**: MIT
- **번역에 사용된 모델** (TranslateGemma 27B): [Gemma Terms of Use](https://ai.google.dev/gemma/terms)
- **Sentry**: 이 리포는 Sentry 와 무관한 third-party 커뮤니티 자산. 적용은 자유지만 Sentry 측에 문의/지원 청구하지 말 것.
