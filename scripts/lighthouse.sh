#!/usr/bin/env bash
# Run Lighthouse against the built web app and fail the run if scores drop
# below the launch thresholds. Targets: 90+ Perf / 95+ A11y / 95+ BP / 90+ SEO.
#
# Usage:
#   pnpm --filter @garageborrow/web build
#   ./scripts/lighthouse.sh                 # uses default port 4173
#   PORT=8080 ./scripts/lighthouse.sh       # override
#
# Requires: `npx lighthouse` (downloaded on first run) and Chrome/Chromium.
set -euo pipefail

PORT="${PORT:-4173}"
URL="http://localhost:${PORT}/"
PERF_MIN="${PERF_MIN:-90}"
A11Y_MIN="${A11Y_MIN:-95}"
BP_MIN="${BP_MIN:-95}"
SEO_MIN="${SEO_MIN:-90}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${REPO_ROOT}/.lighthouse"
mkdir -p "${REPORT_DIR}"
REPORT_JSON="${REPORT_DIR}/report.json"
REPORT_HTML="${REPORT_DIR}/report.html"

echo "→ starting vite preview on :${PORT}"
( cd "${REPO_ROOT}" && pnpm --filter @garageborrow/web preview --port "${PORT}" --strictPort >/dev/null 2>&1 ) &
PREVIEW_PID=$!
trap 'kill "${PREVIEW_PID}" 2>/dev/null || true' EXIT

# Wait for the preview server to come up (max 30s).
for _ in $(seq 1 30); do
  if curl -fsS "${URL}" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! curl -fsS "${URL}" >/dev/null 2>&1; then
  echo "preview server didn't start on ${URL}" >&2
  exit 1
fi

echo "→ running lighthouse against ${URL}"
npx --yes lighthouse "${URL}" \
  --quiet \
  --chrome-flags="--headless=new --no-sandbox" \
  --only-categories=performance,accessibility,best-practices,seo \
  --output=json --output=html \
  --output-path="${REPORT_DIR}/report" >/dev/null

PERF=$(node -e "console.log(Math.round((require('${REPORT_JSON}').categories.performance.score||0)*100))")
A11Y=$(node -e "console.log(Math.round((require('${REPORT_JSON}').categories.accessibility.score||0)*100))")
BP=$(node -e "console.log(Math.round((require('${REPORT_JSON}').categories['best-practices'].score||0)*100))")
SEO=$(node -e "console.log(Math.round((require('${REPORT_JSON}').categories.seo.score||0)*100))")

printf "Performance:    %3d  (min %3d)\n" "${PERF}" "${PERF_MIN}"
printf "Accessibility:  %3d  (min %3d)\n" "${A11Y}" "${A11Y_MIN}"
printf "Best Practices: %3d  (min %3d)\n" "${BP}" "${BP_MIN}"
printf "SEO:            %3d  (min %3d)\n" "${SEO}" "${SEO_MIN}"
echo "report: ${REPORT_HTML}"

FAIL=0
[[ "${PERF}" -lt "${PERF_MIN}" ]] && FAIL=1
[[ "${A11Y}" -lt "${A11Y_MIN}" ]] && FAIL=1
[[ "${BP}"   -lt "${BP_MIN}"   ]] && FAIL=1
[[ "${SEO}"  -lt "${SEO_MIN}"  ]] && FAIL=1
exit "${FAIL}"
