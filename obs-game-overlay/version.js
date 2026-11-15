// Wersja plików nakładki. Nakładki porównują ją z wersją zgłaszaną przez wykrywacz
// i same się odświeżają, gdy wykrywacz zainstalował aktualizację.
window.VM_VERSION = '1.57.0';
window.VM_ON_PAGES = /^https:$/.test(location.protocol) && /\.github\.io$/i.test(location.hostname);
window.vmCheckVersion = function (v, own) {
  if (!v || v === window.VM_VERSION) return;
  // GitHub Pages: wersję z dysku (wykrywacz) pomijamy – liczy się version.json z tej samej strony
  if (window.VM_ON_PAGES && !own) return;
  // w trakcie transmisji albo nagrywania nakładki się nie przeładowują – zrobią to po zakończeniu
  try { var L = JSON.parse(localStorage.getItem('obsGameOverlay.live') || 'null'); if (L && Date.now() - L.at < 20000 && (L.stream || L.rec)) return; } catch (e) {}
  try { if (sessionStorage.getItem('vmReloadedFor') === v) return; sessionStorage.setItem('vmReloadedFor', v); } catch (e) {}
  setTimeout(function () { location.reload(); }, 1500);
};
// Adres wykrywacza: na komputerze z ustawień (localhost), a gdy strona jest otwarta z wykrywacza
// (pilot z telefonu: http://192.168.x.x:7777/ui/…) – ten sam adres, z którego przyszła strona.
window.vmHub = function (fallback) {
  if (/^https?:$/.test(location.protocol) && location.pathname.indexOf('/ui/') === 0) return location.origin;
  return String(fallback || 'http://localhost:7777').replace(/\/+$/, '');
};

// GitHub Pages: co 2 minuty sprawdź version.json obok strony; nowa wersja = przeładowanie (nie w trakcie transmisji)
if (window.VM_ON_PAGES) setInterval(function () {
  fetch('version.json?t=' + Date.now(), { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (j) { window.vmCheckVersion(j && j.version, true); }).catch(function () {});
}, 120000);

// Zaufany korytarz: strony z dysku (OBS, panel z pliku) dołączają do zapytań do wykrywacza klucz z vm-key.js.
// Plik zapisuje wykrywacz obok panelu; strona z internetu nie ma do niego dostępu, więc nie podszyje się pod nakładkę.
// GitHub Pages nie potrzebuje klucza – wykrywacz rozpoznaje je po adresie (detector\data\trusted-origins.txt).
(function () {
  if (location.protocol !== 'file:' || !window.fetch) return;
  var key = '', base = (document.currentScript && document.currentScript.src) || location.href;
  function load() {
    return new Promise(function (ok) {
      var s = document.createElement('script'); s.src = new URL('vm-key.js', base).href + '?t=' + Date.now();
      s.onload = function () { key = window.VM_KEY || ''; s.remove(); ok(); }; s.onerror = function () { s.remove(); ok(); };
      (document.head || document.documentElement).appendChild(s);
    });
  }
  var ready = load(), orig = window.fetch.bind(window);
  var hub = function (u) { return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//i.test(u); };
  window.fetch = function (input, init) {
    var url = String(input && input.url || input);
    if (!hub(url)) return orig(input, init);
    var go = function () { var h = new Headers((init && init.headers) || {}); if (key) h.set('X-VM-Key', key); return orig(url, Object.assign({}, init || {}, { headers: h })); };
    return ready.then(go).then(function (r) {
      if (r.status !== 403) return r;
      ready = load(); return ready.then(go);          // wykrywacz wystartował później i zapisał nowy klucz
    });
  };
})();
