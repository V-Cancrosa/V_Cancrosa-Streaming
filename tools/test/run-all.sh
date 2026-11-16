#!/usr/bin/env bash
# Testy Vincent-Media w przeglądarce (Playwright + Chromium) – bez Windowsa, OBS i Twitcha:
# udawany OBS (obs-mock.js, port 4455, hasło «tajne123») i udawany GameRadar (przechwycone zapytania w każdym teście).
# Użycie: bash tools/test/run-all.sh [folder_na_zrzuty]   (domyślnie /tmp/vm-test)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="${1:-/tmp/vm-test}"; mkdir -p "$OUT"
cd "$HERE/../../obs-game-overlay"
node "$HERE/obs-mock.js" > "$OUT/obs-mock.log" 2>&1 & MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
sleep 1
fail=0
for t in smoke sync-race tts screens socials nora-ui cockpit obs-scenes; do
  echo "== $t"
  if ! timeout 180 node "$HERE/$t.js" "$OUT"; then echo "!! $t: błąd"; fail=1; fi
done
echo "zrzuty i dziennik udawanego OBS: $OUT"
exit $fail
