/*
  Progi szerokości – zdefiniowane raz, używane w CSS przez html[data-bp="…"].
  Pomysł z pena „Responsive Grid with @custom-media” (CodePen): aliasy zapytań o szerokość w jednym miejscu
  zamiast liczb rozsianych po arkuszach. Przeglądarki (i OBS) nie znają jeszcze @custom-media, a my nie mamy
  kroku budowania (PostCSS), więc alias ustawia ten skrypt – reszta to zwykły CSS.

    sm  < 420 px   – wąski dok w OBS, telefon
    md  420–759    – zwykły dok
    lg  760–1199   – szeroki dok / okno: ustawienia w dwóch kolumnach
    xl  ≥ 1200     – duże okno: trzy kolumny
*/
(function () {
  const BP = [['sm', 0], ['md', 420], ['lg', 760], ['xl', 1200]];
  const root = document.documentElement;
  function set() {
    const w = root.clientWidth || window.innerWidth;
    let cur = 'sm'; for (const [n, min] of BP) if (w >= min) cur = n;
    if (root.dataset.bp !== cur) { root.dataset.bp = cur; window.dispatchEvent(new CustomEvent('vm-bp', { detail: cur })); }
  }
  set();
  if (window.ResizeObserver) new ResizeObserver(set).observe(root); else window.addEventListener('resize', set);
  window.VMBP = { BP, get: () => root.dataset.bp };
})();
