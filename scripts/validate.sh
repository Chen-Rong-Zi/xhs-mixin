#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== sbx kit validate (offline) =="
sbx kit validate ./ --offline
echo "== sbx kit inspect (summary) =="
sbx kit inspect ./ --offline --format table
