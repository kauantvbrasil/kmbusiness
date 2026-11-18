(() => {
  if (!('IntersectionObserver' in window) ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const grid = document.getElementById('grid');
  const seen = new WeakSet();
  const observer = new IntersectionObserver(entries => {
    for (const { target, isIntersecting } of entries) {
      if (!isIntersecting) continue;
      observer.unobserve(target);
      target.classList.add('km-scroll-enter');
    }
  }, { threshold: 0.08 });

  function watch(element) {
    if (seen.has(element)) return;
    seen.add(element);
    observer.observe(element);
  }

  document.querySelectorAll('#steps, #catalogo > :not(#grid), .footer').forEach(watch);
  if (!grid) return;
  Array.from(grid.children).forEach(watch);
  new MutationObserver(records => {
    for (const { addedNodes, removedNodes } of records) {
      for (const node of removedNodes) {
        if (node.nodeType === 1) observer.unobserve(node);
      }
      for (const node of addedNodes) {
        if (node.nodeType === 1) watch(node);
      }
    }
  }).observe(grid, { childList: true });
})();
