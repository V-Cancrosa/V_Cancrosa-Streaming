# Vincent-Media – stream w OBS

Komplet do streamowania na Twitchu i nagrywania: karta „Teraz gram”, ekrany przed streamem i przerwy, alerty, czat na ekranie, postacie (fursony) jako prowadzący, motywy gier, cenzura ekranu, Kreator własnych stron i pilot z telefonu.

**Jak to jest zbudowane:**

| Część | Gdzie działa | Co robi |
|---|---|---|
| **Serwis** (`site/`) | przeglądarka – <https://v-cancrosa.github.io/Vincent-Media/> | wszystkie ustawienia i Kreator, z podglądem widoków 1920×1080 |
| **Panel** (`panel.html`) | dok w OBS | prowadzenie streamu: stan, gra, sceny, testy |
| **Widoki** (`stage.html`, `overlay.html`, `alerts.html`…) | źródła przeglądarki w OBS | to, co widzą widzowie |
| **GameRadar** (`detector/`) | Twój komputer, w tle | wykrywa grę, łączy z Twitchem, aktualizuje, przekazuje zmiany między serwisem a OBS |

Wszystko jest w HTML i PowerShellu (wbudowanym w Windows) – nic nie trzeba instalować poza OBS.

---

## Instalacja

1. Pobierz **[Zainstaluj-Vincent-Media.bat](https://github.com/V-Cancrosa/Vincent-Media/raw/main/Zainstaluj-Vincent-Media.bat)** i kliknij go dwa razy (przy „System Windows ochronił ten komputer”: *Więcej informacji → Uruchom mimo to*).
2. Instalator (bez uprawnień administratora):
   - pobiera pliki do `%LOCALAPPDATA%\Vincent-Media`,
   - za Twoją zgodą konfiguruje OBS (OBS musi być zamknięty; najpierw robi kopię zapasową): scena **`VM · Stream`** na cały stream, scena **`VM · Nakładki`** do Twoich własnych scen, dok **Vincent-Media** z panelem,
   - tworzy skróty w *Menu Start → Vincent-Media*: **Start streamu**, GameRadar, Aktualizuj, Folder,
   - opcjonalnie: GameRadar razem z Windows, uruchamianie go z panelu i strażnik w Harmonogramie zadań.
3. Uruchom **Start streamu** – włącza GameRadar w tle, a po nim OBS.

Instalator można uruchomić ponownie – nie tworzy duplikatów.

**Panel z GitHub Pages zamiast z dysku** (zmiany są na streamie kilka minut po wypchnięciu do repo): w OBS *Docki → Własne docki przeglądarki* zmień adres panelu na `https://v-cancrosa.github.io/Vincent-Media/obs-game-overlay/panel.html`. Panel sam przepnie źródła VM w OBS na ten sam adres.

**Odinstalowanie:** usuń sceny `VM · …` i dok w OBS, folder `%LOCALAPPDATA%\Vincent-Media` i folder *Vincent-Media* w Menu Start.

---

## Dzień streamu

**Kokpit „Na żywo”** (serwis → *Na żywo*, działa też na telefonie) – cały stream z jednej strony:
- start i koniec transmisji, nagrywanie, czas na żywo, liczba widzów,
- prawdziwy podgląd z OBS (co sekundę),
- etapy: Przygotowania → Stream za… → Zaraz zaczynamy / Spóźnienie → Głosowanie → Gra · Ramka · Rozmowa → Przerwa → Koniec, przycisk **Dalej**,
- mikrofon z miernikiem, wyciszanie mikrofonu, dźwięku gry i alertów,
- **Zasłoń obraz** – przycisk paniki: zasłona na cały obraz i schowana gra, drugi klik odsłania,
- czat z moderacją (🗑 usuń, ⏱ wycisz na 10 min, ⛔ ban; po aktualizacji trzeba raz zalogować się ponownie do Twitcha – nowe uprawnienia),
- ostatnie alerty z przyciskiem ↻ (pokaż jeszcze raz; nie liczy się drugi raz do statystyk),
- głosowanie: postać czy gra, 2/3/5 min, wynik na żywo, zakończenie przed czasem.

Na razie panel w OBS dalej działa w tle (sam łapie okno gry i pilnuje nagrywania) – zniknie, gdy kokpit przejmie te rzeczy.

1. **Start streamu** (skrót) → GameRadar w tle, potem OBS. Z opcją *uruchamiaj OBS razem z GameRadarem* i autostartem GameRadara wszystko wstaje samo po włączeniu komputera.
2. **Panel → Start** pokazuje uruchamianie krok po kroku: GameRadar, OBS, Twitch, przechwytywanie gry – kółko kręci się, dopóki trwa łączenie, i rysuje ✓, gdy zadziała. Gdy wszystko działa, zostaje jedna zielona belka. Coś nie gra → lista zostaje otwarta, przy kroku jest **Napraw**.
3. **Sceny** to jeden pulpit stanów w jednej scenie OBS:
   - start: *Przygotowania → Stream za… → Zaraz zaczynamy (→ spóźnienie) → Głosowanie → Gra* – przycisk **Dalej**, kliknięcie etapu przeskakuje do niego,
   - **Na wizji:** Gra · Gra w ramce · Rozmowa,
   - **Przerwa i koniec:** Przerwa · Przedłuża się · Koniec (z napisami).
4. **Koniec dnia:** w serwisie **⏻ Zamknij OBS i GameRadar** – kończy transmisję i nagrywanie (pyta), zamyka OBS normalnie i wyłącza GameRadar. Nic nie uruchomi się samo, dopóki nie włączysz tego sam albo nie zrestartujesz komputera.

Start transmisji w OBS sam przechodzi z przygotowań dalej; koniec odliczania bez przejścia dalej zmienia ekran w „Spóźnienie”; wynik głosowania ustawia motyw i po 8 s przełącza na grę.

---

## Serwis (GitHub Pages)

Zwykła strona w przeglądarce, bez ciasnoty doku. Każda strona ma po prawej podgląd prawdziwego widoku 1920×1080 (**⤢** pełny rozmiar, **⧉** adres do OBS).

| Strona | Co tam robisz |
|---|---|
| **Start** | co jest na wizji, adresy widoków do OBS |
| **Gry i programy** | lista z GameRadara z okładkami/logo Steama i ikonami programów; wybór gry, motyw dla gry, uruchamianie |
| **Postać i wygląd** | kto prowadzi, gdzie stoi karta, tryb motywu, układ czatu |
| **Ekrany** | który ekran, odliczanie, termin, podpisy, sociale, „Pokaż na streamie” |
| **Ułożenie scen** | edytor ułożenia |
| **Kreator stron** | strony i liczniki jak w Bubble |
| **Wszystkie ustawienia** | pełny panel (czat, alerty, cenzura, Twitch, OBS) w kolumnach |
| **Pilot (telefon)** | przyciski do sterowania z telefonu |

Przeglądarka i OBS mają osobne pamięci – łączy je GameRadar (`themes/sync.js`: ustawienia przez `/settings`, strony z Kreatora, stany i widoczność przez `/kv`). W OBS odbiera je `stage.html`, więc dok nie musi być otwarty. Kropki w lewym dolnym rogu serwisu mówią, czy GameRadar działa i czy zmiany idą do OBS.

**Panel w doku jako sam pilot:** *Więcej → Wersja → „to okno jako pilot”* zostawia w doku tylko Start i Sterowanie.

---

## Wygląd

### Postacie i motywy

**Postacie:** Vince · Chip · Ragnar · Toro · Myr-35 · Zarin. Przy każdym uruchomieniu OBS jedna jest losowana jako prowadząca (można od razu zmienić). Każda ma swoje kolory, czcionki, napis nad nazwą gry, głos w alertach i wygląd czatu. Myr-35 to głowa protogena z matrycą LED i czterema rejestrami (protokół / człowiek / terminal / Nanite Syndrome).

Na ekranach Vince'a (start, przerwa) tło to żywy szkic architekta w WebGL: przy każdym alercie przechodzi przez niego fala – legendarny alert daje falę z echem. Wyłączysz na stronie *Postać i wygląd* (Kratka).

**Motywy gier** włączają się same: Talisman, Palworld, Mass Effect (ME1/2/3/Andromeda osobno), Warframe, Deadlock, Darkest Dungeon (głos narratora), Hollow Knight / Silksong, Cyberpunk 2077, Counter-Strike 2, C&C Red Alert / Tiberium / Generals (z częściami), Townscaper, visual novel (Ren'Py rozpoznawane po plikach), Blender i programy 3D („Teraz tworzę”). Grafika motywów jest narysowana od zera (SVG i canvas) – bez logotypów gier.

**Gdy postać i gra mają swoje motywy** – cztery tryby (Wygląd → Postać i gra):

| Tryb | Wygląd |
|---|---|
| **Fuzja 50:50** (domyślny) | kolory, czcionki i teksty po równo z obu |
| **Gra + postać** | karta w czystym motywie gry, postać wchodzi portretem, plakietką z imieniem i swoim kolorem |
| **Sam motyw gry** | tylko gra |
| **Sama postać** | tylko postać, gra z nazwy |

Dla pojedynczej gry wybierasz inny motyw albo „bez motywu gry” w jej kafelku na liście. Kropka przy grze: kolorowa – ma motyw, przerywana – czeka na motyw, szara – sama postać.

### Karta, ułożenie, avatar

- **Pozycja karty:** lewy/prawy górny, lewy/środkowy/prawy dolny – albo dowolne miejsce w edytorze ułożenia.
- **Edytor ułożenia** (Wygląd → ✥ albo serwis): przeciągasz okno gry, avatara, czat, pasek z linkami, strefę alertów i kartę. Przyciąganie do siatki 10 px, krawędzi i innych elementów; gra trzyma 16:9 (Shift – dowolnie); strzałki – o 1 px. Panel przestawia też przechwytywanie gry w OBS. Każdy układ czatu ma osobne ułożenie.
- **Avatar: tak / nie.** Postać ożywa, gdy mówisz – przy karcie, w portrecie „Gra + postać” i na zdjęciu na ekranach przerw.
- **Ekrany przed streamem i przerwy:** karta na dole przy zdjęciu postaci, lewa górna część ekranu wolna dla alertów, sociale w prawym górnym rogu.
- **Przejścia:** zasłona w stylu postaci/gry albo **taśma filmowa** (ekrany przesuwają się jak klatki – wzorowane na `film()` z SSGOI).
- **Język streama:** polski albo angielski (wszystko, co widać na streamie; panel zostaje po polsku).

---

## Gry: GameRadar

GameRadar działa jak wykrywanie gier w Discordzie, ale bez Discorda: raz w tygodniu pobiera publiczną bazę gier (ok. 22 tys.), co 3 s sprawdza uruchomione programy, pyta Steama o grę i okładkę. Wynik jest dostępny tylko na Twoim komputerze (`http://localhost:7777`).

- **Źródło gry jest zawsze auto.** Kliknięcie gry w „Co dziś?” to chwilowe nadpisanie – **↺ auto** wraca do wykrywania.
- **Lista „Co dziś?”**: gry (Steam, Epic, GOG, Ubisoft, EA, Battle.net, Xbox) i programy, których używasz. Bez dodatków – soundtracki, artbooki, *Bonus Content*, DLC, serwery, SDK, narzędzia i biblioteki nie trafiają na listę (gra ze Steama musi mieć `.exe`).
- **Gra niewykryta albo wykryte coś, co nie jest grą:** w panelu *Dodaj jako grę* / *To nie gra – ignoruj*. Zapisuje się w `detector\my-games.txt`:
  ```
  # plik.exe = Nazwa gry | opcjonalny adres okładki
  dolphin.exe = Dolphin (GameCube)
  # ignorowanie:
  !wallpaper64.exe
  !steam:431960
  ```
- **Przechwytywanie gry** dodaje się samo do `VM · Stream` (okno, z kursorem, Windows Graphics Capture) i przesuwa się z układem: pełny ekran, ramka albo schowane na ekranach.

---

## Czat i moderacja

- **Układ czatu** (jeden dla wszystkich scen): pionowo z lewej/prawej, pasek u góry/u dołu albo bez. Wygląd w stylu prowadzącej postaci (Myr – terminal, Vince – adnotacje architekta, Chip – karteczki, Ragnar – playlista, Toro – lampiony, Zarin – tabliczki z kadłuba).
- **Tempo:** przy zalewie czat zwalnia, a w razie potrzeby włącza na Twitchu tryb powolny („ciach”).
- **Komendy widzów:** `!styl neon|szklo|pixel|komiks|terminal|papier|holo|sakura|ogien|lod`, `!kolor turkus|#rrggbb…`, `!efekt konfetti|serca|gwiazdy|fajerwerki|iskry|babelki` (efekty też jako nagrody za punkty), `!reset`, `!linki`. Przełącznik **tylko motyw** ignoruje style widzów.
- **Słowa zakazane:** obelgi zakazane regulaminem Twitcha (też polskie) i ich przeróbki (leet, rozbijanie, cyrylica, „pod TTS”) – na czacie, w nickach alertów, w napisach końcowych i w skanie ekranu. Zamiana na zakrycie albo na furry żart (PL/EN). Przekleństwa opcjonalnie.
- **Cenzura ekranu:** GameRadar czyta tekst z przechwytywanych okien (OCR Windows, bez internetu, nic nie zapisuje), a warstwa `VM · Cenzura` zakleja zakazane słowa naklejkami z łapką. Ramki skanera tylko na życzenie. *Opóźnij okna o 0,5 s* sprawia, że zasłona jest na streamie, zanim słowo będzie widać.
- **Podejrzane konta:** świeże konta, nicki z generatora, brak awatara i bio, reklamy, fale followów bez raidu, zdrowie widowni (widzowie na piszącego, płaski wykres). Legalne boty (Nightbot, StreamElements…) mają znaczek BOT. Flaga to podpowiedź, nie wyrok.
- **Archiwum:** każdy stream w `detector\data\archive\streams\` (cały czat i alerty, podsumowanie); w panelu statystyki i pobieranie czatu jako TXT, SRT (napisy do nagrania) albo JSON. OBS może sam nagrywać lokalnie razem ze streamem.

---

## Alerty i głosowanie

Follow, sub, resub, gifty, bitsy, raid i nagrody za punkty – bez StreamElements, w stylu postaci i gry, z dźwiękami generowanymi w przeglądarce. **Poziomy 1–5**: im większe zdarzenie, tym większy i dłuższy alert (od 3 efekt na cały ekran, od 4 drżenie i bas, 5 – „LEGENDARNE”).

| Zdarzenie | 2 | 3 | 4 | 5 |
|---|---|---|---|---|
| Bitsy | 100+ | 500+ | 1000+ | 5000+ |
| Gift (suby) | 2+ | 5+ | 10+ | 50+ |
| Resub (miesiące) | 3+ | 6+ | 12+ | 24+ |
| Raid (widzowie) | 5+ | 20+ | 50+ | 200+ |
| Nagroda (punkty) | 500+ | 2000+ | 10 000+ | 50 000+ |

Każda scena mówi alertom, gdzie jest na niej wolne miejsce (`themes/zones.js`), więc alert nie zasłania gry, avatara ani czatu. Testy: Sterowanie → Alerty (z wyborem wielkości), Galeria wszystkich tekstów.

**Głosowanie** (etap startu): czat wybiera między postacią a grą (`1`/`2` albo nazwą). **⏹ Zakończ głosowanie** obok *Dalej* (albo w pilocie, albo `!vm koniecglosowania`) kończy od razu.

**Twitch – połączenie raz:** <https://dev.twitch.tv/console/apps> → *Register Your Application* (Redirect `http://localhost`, kategoria *Broadcaster Suite*, typ **Public**) → skopiuj **Client ID** → panel *Więcej → Twitch* → *Połącz z Twitchem* → kod na <https://www.twitch.tv/activate>. Logowanie jest zapamiętane (zaszyfrowane kontem Windows) i odświeża się samo.

---

## Kreator stron (HUB)

Panel → **Twórz** albo serwis → *Kreator stron*. Strony do 1920×1080, jak w Bubble.io:
- **Co robimy?** – gotowe pomysły: ekran „zaraz zaczynamy”, licznik śmierci, podziękowanie za follow, ostatni followerzy, pasek z linkami, Cyberpunk HUD, pilot, pusta strona.
- **✎ Projekt** – paleta: *wizualne* (tekst, przycisk, ikona, obrazek, kształt, wideo, HTML), *kontenery* (grupa, grupa powtarzalna, popup), *HUD* (tag statusu, statystyka, cytat, ramka CAM), *formularze* (pole, checkbox, lista), *stream* (postać, gra, odliczanie, zegar, linki, czat, miejsce na alerty). Przeciągasz na stronę, po prawej wygląd, układ i zachowanie.
- **⚡ Workflow** – „Kiedy (klik, alert, komenda, co jakiś czas, zmiana ekranu) → Zrób (pokaż, ukryj, mrugnij, ustaw/dodaj do stanu, pokaż stronę na streamie)”.
- **▤ Dane** – stany (np. `{smierci}`), wspólne dla wszystkich stron.

Na stream: **▶ Na stream** (strona 1920×1080 w `VM · Stream`), **＋ OBS** (osobne źródło `page.html?id=…`), **🎛 Pilot** (strona z działającymi przyciskami). Kopia zapasowa stron do pliku JSON.

---

## Pilot z telefonu

*Więcej → Pilot z telefonu → Włącz pilota* → zeskanuj kod QR. Strona pilota ma przyciski: Dalej, etapy startu, Głosowanie i jego koniec, Gra / Ramka / Rozmowa, Przerwa / Koniec, karta ukryj/pokaż/auto, wybór gry i sceny, test alertu. Po kliknięciu telefon pokazuje **„✓ Komputer odebrał”**.

Polecenia idą przez darmowy przekaźnik **ntfy.sh** pod długim losowym kluczem (**↻ Nowy klucz** unieważnia stary link) – bez Wi-Fi i bez otwierania portów. Wykonuje je panel w doku OBS. Alternatywa: na swoim czacie `!vm przerwa`, `!vm gra`, `!vm dalej`, `!vm scena <nazwa>`, `!vm gra <nazwa>`, `!vm auto`, `!vm ukryj`/`pokaz`, `!vm test`, `!vm koniecglosowania` (tylko z konta streamera, nie pojawia się na ekranie).

---

## Głos i mikrofon

- **Mikrofon:** panel → Start, wybór urządzenia (np. DGM20 USB Microphone). Przy „domyślnym w Windows” i jednym mikrofonie USB panel sam na niego przełącza. Wskaźnik i avatar słuchają mikrofonu, który naprawdę gra.
- **✨ Popraw głos:** jedno kliknięcie dokłada na mikrofon w OBS filtry w kolejności: redukcja szumów **RNNoise** → **bramka** (−36/−44 dB) → **kompresor** (4:1 od −20 dB, +4 dB) → **limiter** (−3 dB). Drugie kliknięcie zdejmuje. Dostrajasz w OBS: prawy klik na mikrofon → Filtry.
- **Głos postaci (TTS):** postacie czytają alerty na głos – swoje zdanie, a potem wiadomość widza (bitsy od progu, suby; do wyboru na stronie *Głos postaci*). Głosy z Windows: darmowe, bez internetu (GameRadar → `/tts`). Język wybiera się sam z każdego zdania, więc polski i angielski można mieszać. Barwy: Vince niżej z pogłosem pokoju, Chip wyżej i szybciej, Ragnar przez radio, Toro nisko w sali, Myr-35 robot, Zarin metal. Brakuje głosu? Ustawienia Windows → Czas i język → Mowa → Dodaj głosy. Linki, spam znaków i słowa nienawiści nie są czytane.

---

## Aktualizacje i bezpieczeństwo

- **Aktualizacje:** GameRadar co 10 minut sprawdza GitHuba, podmienia pliki i uruchamia się od nowa; nakładki i panel odświeżają się same. **W trakcie transmisji i nagrywania nic się nie aktualizuje.** *Więcej → Wersja* (odliczanie, *Sprawdź teraz*), *↻ Uruchom GameRadar ponownie*. Twoje dane (logowanie Twitcha, biblioteka gier, `my-games.txt`, ustawienia) zostają.
- **Zaufany korytarz:** GameRadar zna hasło do OBS i steruje czatem, więc odpowiada tylko zaufanym stronom: Twoim GitHub Pages (inne adresy w `detector\data\trusted-origins.txt`), stronom z dysku z kluczem `vm-key.js` (zapisuje go GameRadar; nie trafia do repo) i własnym stronom. Obce próby trafiają do dziennika.
- **Dziennik:** *Więcej → GameRadar – podgląd na żywo*, **📄 Otwórz pełny dziennik** / **⬇ Pobierz**, **📂 Otwórz folder Vincent-Media**.

---

## Dla programisty

```
obs-game-overlay/
  site/             serwis (GitHub Pages): menu, podglądy, synchronizacja
  panel.html        dok w OBS
  stage.html        jedna scena: ekrany, układy i strony z Kreatora jako ramki
  overlay.html      karta „Teraz gram” i pasek czatu
  layouts.html      gra pełny ekran / w ramce / rozmowa
  scenes.html       ekrany przed streamem, przerwy, koniec
  alerts.html  transition.html  censor.html  vote.html  page.html
  builder.html      Kreator stron      editor.html   edytor ułożenia
  themes/           motywy, postacie, czat, głosy, słowa, Kreator (pagekit.js), synchronizacja (sync.js)…
  detector/         GameRadar (PowerShell 5.1 – pliki .ps1 z polskimi znakami muszą mieć BOM UTF-8)
tools/check-ps1.py  sprawdzenie .ps1 przed commitem (BOM, cudzysłowy, nawiasy)
```

- **Wspólny stan:** `localStorage` `obsGameOverlay.v1` (ustawienia), `…pages` / `…pageState` / `…pageVis` (Kreator), `…detected`, `…activeTheme`, `…ready`; `BroadcastChannel('obsGameOverlay')`.
- **GameRadar (`http://localhost:7777`):** `/game`, `/library`, `/icon`, `/art`, `/events`, `/settings`, `/kv`, `/session`, `/vote…`, `/censor…`, `/relay`, `/launch`, `/shortcut`, `/restart`, `/shutdown`, `/log…`, `/update/…`.
- Przed commitem: `python3 tools/check-ps1.py`. Typograficzne cudzysłowy („ ”) w `.ps1` psują PowerShella – używaj « ».
- Wersja: `version.json` i `version.js`.

---

## Podziękowania i licencje

- Grafika motywów i dźwięki: napisane od zera, CC0.
- Portrety postaci w `themes/fursona/` należą do autorów ilustracji – zobacz `themes/fursona/CREDITS.md`; nie są na CC0.
- Ikony serwisów społecznościowych: [Simple Icons](https://simpleicons.org) (CC0). Czcionki: Google Fonts (OFL).
- Inspiracje z CodePen (MIT; wzięty pomysł lub wygląd, kod napisany na nowo):
  - zasady ruchu – „20 UI Animation Rules”, [web-strategist](https://codepen.io/web-strategist/pen/XJMOdGw), wg artykułu [Pixic Studio](https://pixicstudio.medium.com/ui-animation-best-practices-20-rules-e855e845f7e5),
  - przejście „taśma filmowa” – `film()` z biblioteki [SSGOI](https://github.com/meursyphus/ssgoi),
  - HUD cyberpunk – baner „Yuffie // Cyberpunk Edgerunners”, [velkaa](https://codepen.io/velkaa) (bez GIF-ów i muzyki z oryginału),
  - progi szerokości panelu – „Responsive Grid with @custom-media”, [Chris Coyier](https://codepen.io/chriscoyier).
- Tło Vince'a na ekranach (`themes/aether.js`) – „Aetheric Blueprint – Interactive Shader”, [Techartist / VoXelo](https://codepen.io/VoXelo/pen/azOeJVo) (MIT); shader przeniesiony z Three.js na czysty WebGL, fala od alertów zamiast kliknięcia, kolory z motywu, bez błysku, najwyżej 30 klatek.
- Przekaźnik pilota: [ntfy.sh](https://ntfy.sh).
