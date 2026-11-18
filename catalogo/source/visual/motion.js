(() => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const grid = document.getElementById('grid');
  const pending = new Set();
  let frame = 0;

  function update() {
    frame = 0;
    const scrollTop = Math.max(0, window.scrollY);
    const viewport = window.innerHeight;
    const maxScroll = Math.max(0, document.documentElement.scrollHeight - viewport);
    const distance = Math.min(190, viewport * 0.28);
    const measurements = [];

    for (const element of pending) {
      const bounds = element.getBoundingClientRect();
      if (!bounds.height) continue;
      const top = scrollTop + bounds.top;
      const start = Math.max(0, Math.min(top - viewport * 0.9, maxScroll - distance));
      const travel = Math.min(distance, maxScroll - start);
      const progress = travel > 0 ? Math.max(0, Math.min(1, (scrollTop - start) / travel)) : 1;
      measurements.push([element, progress]);
    }

    for (const [element, progress] of measurements) {
      if (progress === 1) {
        pending.delete(element);
        element.classList.remove('km-scroll-reveal');
        element.style.removeProperty('--km-reveal-opacity');
      } else {
        element.style.setProperty('--km-reveal-opacity', String(0.16 + 0.84 * progress));
        element.classList.add('km-scroll-reveal');
      }
    }
  }

  function schedule() {
    if (!frame && pending.size) frame = window.requestAnimationFrame(update);
  }

  document.querySelectorAll('#steps, #catalogo > :not(#grid), .footer').forEach(element => pending.add(element));
  if (grid) {
    for (const element of grid.children) pending.add(element);
    new MutationObserver(records => {
      for (const { addedNodes, removedNodes } of records) {
        for (const node of removedNodes) pending.delete(node);
        for (const node of addedNodes) {
          if (node.nodeType === 1) pending.add(node);
        }
      }
      schedule();
    }).observe(grid, { childList: true });
  }

  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule);
  update();
})();
