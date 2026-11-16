# Testy (bez Windowsa)

Playwright + Chromium, uruchamiane z folderu `obs-game-overlay` (skrypt robi to sam):

```
bash tools/test/run-all.sh /tmp/vm-test
```

| Test | Co sprawdza |
|---|---|
| `smoke.js` | wszystkie strony i widoki otwierają się bez błędów JS |
| `sync-race.js` | synchronizacja pole po polu: dwie „przeglądarki” zmieniają różne pola naraz, nic się nie cofa (udawany `/settings`) |
| `tts.js` | głos postaci: wybór głosu PL/EN, filtr tekstu, alert z wiadomością widza (udawane `/tts`) |
| `screens.js` | strona Ekrany: ustawienia ekranu trafiają do podglądu, uwagi się zapisują |
| `socials.js` | sociale w stylu każdej postaci (zrzuty) |
| `nora-ui.js` | interfejs Nory w trybie podglądu (zrzut) |
| `cockpit.js` | kokpit z udawanym OBS: etapy, transmisja, wyciszanie, zasłona, moderacja, powtórka alertu, wersja na telefon |
| `obs-scenes.js` | strona OBS: wykrywanie braków i „Ustaw” dla osobnych scen; kokpit przełącza sceny OBS |

`obs-mock.js` – udawany OBS WebSocket v5 (sceny, źródła, filtry, ustawienia profilu, usługa, transmisja); co robią strony, wypisuje na wyjście.

PowerShell (GameRadar, kreator, update) nie da się tu uruchomić – sprawdza go `tools/check-ps1.py` (składnia znaków, BOM, nawiasy, `$zmienna:`), a na Windowsie kreator/Nora (parsowanie przy starcie).
