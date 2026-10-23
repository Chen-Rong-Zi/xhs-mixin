#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# 拷贝源码（排除 dist 与 .git），避免 zip 里带上空的 dist/ 和 git 内部对象
tar cf - --exclude=./dist --exclude=.git --exclude=./.git/* . | (cd "$staging" && tar xf -)
mkdir -p dist
sbx kit pack "$staging" --output dist/xhs-query.kit.zip
echo "== packed =="
unzip -l dist/xhs-query.kit.zip
