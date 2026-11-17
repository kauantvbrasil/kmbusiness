/* Presentation only: observe existing loading UI, never wrap requests or mutate catalog data. */
(() => {
  'use strict';
  const body = document.body;
  const scene = document.getElementById('kmCinema');
  const emblem = document.getElementById('kmEmblem');
  const grid = document.getElementById('grid');
  const toggle = document.getElementById('kmMotionToggle');
  if (!scene || !emblem || !grid || !toggle) return;
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  let paused = reduced.matches;
  let observer, boot, completed = false, flight;
  const startedAt = performance.now();
  const updateMotion = () => {
    body.classList.toggle('km-motion-paused', paused || reduced.matches);
    if (paused || reduced.matches) flight?.cancel();
    toggle.setAttribute('aria-pressed', String(paused || reduced.matches));
    toggle.querySelector('span').textContent = paused || reduced.matches ? 'Animações pausadas' : 'Pausar animações';
    toggle.setAttribute('aria-label', paused || reduced.matches ? 'Retomar animações' : 'Pausar animações');
    toggle.disabled = reduced.matches;
  };
  toggle.addEventListener('click', () => { paused = !paused; updateMotion(); });
  const visibility = () => { body.classList.toggle('km-tab-hidden', document.hidden); if (document.hidden) flight?.cancel(); };
  window.addEventListener('resize', () => flight?.cancel());
  document.addEventListener('visibilitychange', visibility);
  visibility(); updateMotion();
  function finish(animate = true) {
    if (completed) return;
    completed = true;
    observer?.disconnect();
    const from = emblem.getBoundingClientRect();
    body.classList.remove('km-initializing');
    const immediate = performance.now() - startedAt < 120 || !animate || reduced.matches || paused || document.hidden || !emblem.animate;
    if (immediate) { boot?.remove(); return; }
    const to = emblem.getBoundingClientRect();
    if (!to.width || !to.height) { boot?.remove(); return; }
    boot.classList.add('km-boot-leaving');
    boot.querySelector('.km-boot-status')?.remove();
    boot.querySelector('button')?.remove();
    const veil = boot.animate([{opacity:1},{opacity:0}], {duration:420, easing:'ease-out'});
    veil.finished.catch(() => {}).finally(() => boot.remove());
    emblem.style.zIndex = '1002';
    // FLIP keeps the same logo node throughout. Only transform/opacity animate.
    flight = emblem.animate([
      { transform: 'translate(-50%, -50%) translate(' + (from.left + from.width/2 - to.left - to.width/2) + 'px,' + (from.top + from.height/2 - to.top - to.height/2) + 'px) scale(' + from.width/to.width + ')' },
      { transform: 'translate(-50%, -50%) translate(0px,0px) scale(1)' }
    ], { duration: 680, easing: 'cubic-bezier(.22,1,.36,1)' });
    flight.finished.catch(() => {}).finally(() => { emblem.style.zIndex = ''; });
  }
  const preference = () => { updateMotion(); if (reduced.matches) { flight?.cancel(); finish(false); } };
  if (reduced.addEventListener) reduced.addEventListener('change', preference);
  else reduced.addListener(preference);
  // The existing loader disappears after the real catalog request settles, including errors.
  if (!grid.querySelector('.loading') || reduced.matches || location.pathname === '/admin') { completed = true; return; }
  boot = document.createElement('div');
  boot.className = 'km-boot';
  boot.innerHTML = '<div class="km-boot-status" role="status"><span class="km-boot-indicator" aria-hidden="true"></span>Carregando catálogo…</div><button type="button" class="km-skip-intro">Ir para o catálogo</button>';
  body.append(boot);
  boot.querySelector('button').addEventListener('click', () => finish(false));
  document.addEventListener('focusin', event => { if (!completed && !boot.contains(event.target)) finish(false); });
  body.classList.add('km-initializing');
  boot.querySelector('button').addEventListener('click', () => finish(false));
  // Never trap keyboard users behind an ornamental loading scene.
  document.addEventListener('focusin', event => { if (!completed && !boot.contains(event.target)) finish(false); });
  window.addEventListener('pagehide', () => finish(false), { once:true });
  window.addEventListener('resize', () => { if (completed) flight?.cancel(); });
  observer = new MutationObserver(() => { if (!grid.querySelector('.loading')) finish(); });
  observer.observe(grid, { childList:true, subtree:true });
  if (!grid.querySelector('.loading')) finish();
})();
