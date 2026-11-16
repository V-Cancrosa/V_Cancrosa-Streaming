# NOTES – dla przyszłego mnie (i Claude'a)

Osobisty power-tool do streamowania, nie produkt. Te notatki mają pozwolić coś naprawić za pół roku w trakcie streamu,
bez czytania całego kodu. Szczegóły dla użytkownika: `obs-game-overlay/README.md`. Testy: `tools/test/README.md`.

## Mapa w jednym ekranie

```
 Przeglądarka (Edge)                       OBS (CEF – osobna przeglądarka, osobna pamięć!)
 ─────────────────────                     ──────────────────────────────────────────────
 serwis site/*.html  ──┐                   dok: site/live.html?dock=1 (kokpit) + ukryty panel.html?engine=1
 kokpit site/live.html │                   sceny VM · …: scenes.html?scene=…, layouts.html?layout=…,
                       │                   overlay.html, alerts.html, transition.html, censor.html
                       │  HTTP localhost:7777  │
                       └──────► GameRadar ◄────┘   (detector\detector.ps1 + core\*.ps1 + mods\*.ps1, PowerShell 5.1)
                                  │  ├─ Twitch: EventSub (WebSocket) + Helix (kary, czat, klucz transmisji)
                                  │  ├─ dane: detector\data\  (settings.json, kv.json, library.json, logowanie, kopie)
                                  │  └─ aktualizacje z GitHuba (update.ps1), kopie zapasowe, głos (Windows + Piper)
 Nora (nora\Nora.exe, C# + WebView2) ──► GameRadar (sprawdza, uruchamia, prosi o aktualizacje) ──► OBS (start w tle)
 Kokpit/strona OBS ──► OBS WebSocket (ws://localhost:4455, hasło z GameRadara /obsws) – sceny, wyjście, filtry
 Telefon (site/pilot.html) ──► ntfy.sh (przekaźnik) ──► GameRadar
```

## Gdzie co mieszka

| Co | Gdzie |
|---|---|
| ustawienia (jeden obiekt) | `localStorage['obsGameOverlay.v1']` w każdej przeglądarce + GameRadar `data\settings.json` |
| strony Kreatora, stany, uwagi | `obsGameOverlay.pages / pageState / pageVis / notes` → GameRadar `/kv` (`data\kv.json`) |
| wykryta gra | `obsGameOverlay.detected` (z `/game`) |
| biblioteka gier | GameRadar `data\library.json`; kopia w serwisie `localStorage['vm.lib']` |
| synchronizacja | `themes/sync.js` (strony serwisu, stage/page w OBS); panel w ramce – NIE synchronizuje sam |
| migracje ustawień | `themes/sync.js` → `MIGRATIONS` (`settingsVersion`) – nowy format = nowy krok NA KOŃCU listy |
| motywy postaci i gier | `themes/fursona.js`, `themes/games.js`, fuzja `themes/fusion.js` |
| głos | `themes/tts.js` (przeglądarka: kolejka, język, efekty) → GameRadar `/tts` (Piper `mods\piper.ps1` albo Windows `mods\tts.ps1`) |
| OBS: sprawdzanie i „Ustaw” | `themes/obssetup.js` (osobne sceny / jedna scena, obraz, mikrofon, Twitch, wyjście) |
| bot czatu | wykrywanie `themes/automod.js` (kokpit) → kary/komendy/timery `mods\bot.ps1` |
| Nora | źródła `nora/*.cs`, interfejs `obs-game-overlay/nora/ui/index.html`, budowanie `tools/build-nora.py` |

## GameRadar: części i adresy

- `detector.ps1` – start, blokada „jedna kopia” (mutex `Local\VincentMediaDetector`), dziennik, wczytanie części, główna pętla.
- `core\` (wymagane, w tej kolejności): `games` (wykrywanie, Steam, biblioteka) · `chat` (zdarzenia, boty, głosowanie) ·
  `archive` · `twitch` · `updates` · `http` (ustawienia, przekaźnik, zaufane strony, wysyłanie odpowiedzi) · `backup` · `api` (wszystkie adresy).
- `mods\` (opcjonalne – zablokowany przez antywirusa wyłącza tylko siebie): `censor`, `tts`, `windows`, `piper`, `bot`.
- Adresy: lista w `obs-game-overlay/README.md` („Dla programisty”); źródło prawdy: `switch` w `core\api.ps1`.

## Dlaczego tak (rzeczy, które już raz bolały)

- **Synchronizacja pole po polu** (`sync.js`, `panel.html save()`). Dawniej wygrywał cały obiekt zapisany jako ostatni: starsza
  kopia z OBS/doku/panelu cofała świeżą zmianę („skoki”, odhaczające się pola). Teraz: wysyłka tylko zmienionych pól doklejona
  do najnowszego stanu; cudza zmiana nie kasuje niewysłanych własnych; jedna synchronizująca strona na przeglądarkę (Web Locks).
- **Nowa kopia GameRadara nie zabija starej, jeśli ta odpowiada czymkolwiek** (`Stop-StaleDetector`, także 403). Wcześniej pytała
  o `/game`, dostawała 403 (lista zaufanych) i zabijała zdrową kopię → pętla restartów co kilkanaście sekund z panelem w roli
  „ratownika”. Panel przed uruchomieniem kopii też sprawdza, czy GameRadar naprawdę milczy.
- **Port 7777**: najpierw `localhost`, przy „Odmowa dostępu” `http://+:7777/` (stara rezerwacja po dawnym pilocie przez Wi-Fi).
  Zapytania spoza komputera i tak dostają 403.
- **Moduły w osobnych plikach** – Windows Defender (AMSI) zablokował kiedyś cały `detector.ps1` jako „złośliwy” (lokalny serwer
  + lista okien + zrzuty + uruchamianie programów). Podejrzane rzeczy są w `mods\` i ładują się w try/catch.
- **PowerShell 5.1**: pliki `.ps1` z polskimi znakami MUSZĄ mieć BOM; żadnych cudzysłowów „ ” (PowerShell bierze je za `"`) – używaj « »;
  `"$zmienna:"` w tekście to błąd składni (dwukropek = dysk) – pisz `"${zmienna}:"`. Pilnuje `tools/check-ps1.py`.
  `install.ps1` NIE może mieć BOM (uruchamiany przez `irm | iex`).
- **Spis plików** (`manifest.json`): sumy liczone bez CR i BOM dla plików tekstowych – paczka z GitHuba ma `.ps1` z końcami Windows.
- **Pliki w użyciu przy aktualizacji** (Nora.exe, biblioteki): przemianowane na `*.old` zamiast nadpisania (Windows nie pozwala
  nadpisać działającego programu); `.old` znika przy następnej aktualizacji.
- **GitHub Pages trzyma stare pliki do ~10 min** – podglądy w serwisie mają `?v=wersja` w adresie.
- **Osobne sceny w OBS** (domyślnie): nazwy scen są dawne („VM · Gra – pełny ekran”…), bo znają je alerty, czat i panel.
  Kokpit trzyma etap ↔ scenę w obie strony (`live.html` → `SCENE_FOR` / `KIND_OF`). Panel w trybie scen nie przekierowuje do „VM · Stream”.
- **Logowanie Twitcha**: device code (bez serwera); uprawnienia w `core\twitch.ps1` → `$TwitchScopes`. Nowe uprawnienie = trzeba się
  zalogować ponownie (strona OBS sama to proponuje, gdy Twitch odmawia).
- **Klucz tego komputera** (`data\local-key.txt` → `vm-key.js`): strony z dysku (OBS) wysyłają go w nagłówku `X-VM-Key`;
  strony z GitHub Pages są zaufane po adresie. Bez tego GameRadar (hasło do OBS, czat) odpowiadałby każdej stronie z internetu.
- **Nora nie uruchamia ukrytego PowerShella poza samym GameRadarem** – aktualizacje i naprawy zleca GameRadarowi (`/update/run`).

## Przed każdym wypchnięciem

1. `obs-game-overlay/version.json` i `version.js` – ta sama nowa wersja.
2. Zmiany w `nora/*.cs` → `python3 tools/build-nora.py` (exe trafia do `obs-game-overlay/nora/`).
3. `python3 tools/make-manifest.py && python3 tools/check-ps1.py`
4. `bash tools/test/run-all.sh` (przynajmniej `smoke`).

## Gdy coś nie działa w trakcie streamu

- Serwis → **Dziennik** (widok „Problemy”) – GameRadar pisze tam przyczyny; **Kopie zapasowe** na tej samej stronie.
- Nora pokazuje przy kroku, co nie gra, i daje przycisk naprawy.
- Ostateczność: serwis → **Zamknij OBS i GameRadar**, potem Nora od nowa.
