#!/usr/bin/env bash
# bust-cache.sh — ko.js 파일 해시 재생성 + app.js 내 참조 치환
# 브라우저가 캐시한 구 버전을 강제로 깨야 할 때.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODE=docker
PCT_ID=""
CONTAINER="sentry-self-hosted-web-1"
NGINX="sentry-self-hosted-nginx-1"
DIST="/usr/src/sentry/src/sentry/static/sentry/dist"
CHUNK_DIR="$DIST/chunks/locale"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pct) MODE=pct; PCT_ID="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

run() {
  if [[ "$MODE" == "pct" ]]; then pct exec "$PCT_ID" -- "$@"
  else "$@"; fi
}
run_in_container() {
  run docker exec "$CONTAINER" "$@"
}
push_file() {
  local src="$1" dst="$2"
  if [[ "$MODE" == "pct" ]]; then
    pct push "$PCT_ID" "$src" "/tmp/$(basename $src)"
    pct exec "$PCT_ID" -- docker cp "/tmp/$(basename $src)" "$CONTAINER:$dst"
    pct exec "$PCT_ID" -- rm -f "/tmp/$(basename $src)"
  else
    docker cp "$src" "$CONTAINER:$dst"
  fi
}

OLD=$(run_in_container ls "$CHUNK_DIR" | grep -oE 'ko\.[a-f0-9]+\.js$' | head -1 | sed 's/\.js$//')
[[ -n "$OLD" ]] || { echo "ko.*.js 없음"; exit 1; }
OLD_HASH=${OLD#ko.}
NEW_HASH=$(head -c16 /dev/urandom | xxd -p)
NEW="ko.$NEW_HASH"
echo "[1/4] 해시 교체: $OLD_HASH → $NEW_HASH"

echo "[2/4] 새 파일 쓰기"
push_file "$HERE/dist/ko.js"    "$CHUNK_DIR/$NEW.js"
push_file "$HERE/dist/ko.js.gz" "$CHUNK_DIR/$NEW.js.gz"

echo "[3/4] 구 파일 삭제 + app.js/gsAdmin.js 의 해시 참조 치환"
run_in_container rm -f "$CHUNK_DIR/$OLD.js" "$CHUNK_DIR/$OLD.js.gz"
for f in entrypoints/app.js entrypoints/gsAdmin.js; do
  run_in_container bash -c "
    if grep -q '$OLD_HASH' '$DIST/$f' 2>/dev/null; then
      sed -i 's/$OLD_HASH/$NEW_HASH/g' '$DIST/$f'
      gzip -kf '$DIST/$f'
    fi
  "
done

echo "[4/4] nginx reload"
run docker exec "$NGINX" sh -c 'rm -rf /var/cache/nginx/* 2>/dev/null; nginx -s reload' 2>/dev/null || true

echo "완료. 브라우저 일반 새로고침으로 반영."
