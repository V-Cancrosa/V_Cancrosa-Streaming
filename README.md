# Vincent-Media

Wszystko do streamowania na Twitchu i nagrywania w OBS: karta „Teraz gram” z wykrywaniem gry, ekrany przed streamem i przerwy, alerty bez StreamElements, czat na ekranie, postacie jako prowadzący, motywy gier, cenzura ekranu, Kreator własnych stron i pilot z telefonu.

- **Serwis (ustawienia w przeglądarce):** <https://v-cancrosa.github.io/Vincent-Media/>
- **Instalacja (Windows):** pobierz i kliknij dwa razy **[Zainstaluj-Vincent-Media.bat](https://github.com/V-Cancrosa/Vincent-Media/raw/main/Zainstaluj-Vincent-Media.bat)** albo wklej w PowerShellu:
  ```powershell
  irm https://raw.githubusercontent.com/V-Cancrosa/Vincent-Media/main/install.ps1 | iex
  ```
- **Dokumentacja:** [obs-game-overlay/README.md](obs-game-overlay/README.md)

| W repo | Co to jest |
|---|---|
| [`obs-game-overlay/`](obs-game-overlay) | serwis, panel, widoki dla OBS i GameRadar (wykrywacz gier i most do Twitcha) |
| [`install.ps1`](install.ps1), [`Zainstaluj-Vincent-Media.bat`](Zainstaluj-Vincent-Media.bat) | instalator |
| [`tools/check-ps1.py`](tools/check-ps1.py) | sprawdzenie skryptów PowerShell przed commitem |
| [`index.html`](index.html) | przekierowanie z GitHub Pages do serwisu |
