#!/usr/bin/env bash
# deploy.sh — Sentry 컨테이너에 ko.js 배포
#
# 사용:
#   sudo bash scripts/deploy.sh                      # docker host (기본)
#   sudo bash scripts/deploy.sh --pct <LXC_ID>       # Proxmox LXC 내부 docker
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODE=docker
PCT_ID=""
CONTAINER="sentry-self-hosted-web-1"
NGINX="sentry-self-hosted-nginx-1"
CHUNK_DIR="/usr/src/sentry/src/sentry/static/sentry/dist/chunks/locale"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pct) MODE=pct; PCT_ID="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

run_docker() {
  if [[ "$MODE" == "pct" ]]; then
    pct exec "$PCT_ID" -- docker "$@"
  else
    docker "$@"
  fi
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

echo "[1/3] 현재 서빙 중인 ko.* 해시 탐지"
CURRENT=$(run_docker exec "$CONTAINER" ls "$CHUNK_DIR" 2>/dev/null | grep -oE 'ko\.[a-f0-9]+\.js$' | head -1)
[[ -n "$CURRENT" ]] || { echo "ko.*.js not found in $CHUNK_DIR"; exit 1; }
echo "  target: $CURRENT"

echo "[2/3] $HERE/dist/ko.js 덮어쓰기"
push_file "$HERE/dist/ko.js"    "$CHUNK_DIR/$CURRENT"
push_file "$HERE/dist/ko.js.gz" "$CHUNK_DIR/$CURRENT.gz"

echo "[3/3] nginx cache flush + reload"
run_docker exec "$NGINX" sh -c 'rm -rf /var/cache/nginx/* 2>/dev/null; nginx -s reload' 2>/dev/null || true

echo "완료. 브라우저 F5 하면 반영. 캐시 문제 있으면 scripts/bust-cache.sh 사용."
