(() => {
  const map = document.querySelector('.connection-map');
  if (!map) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const cards = [...map.querySelectorAll('.connection-targets article')];
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.classList.add('connection-flow');
  svg.setAttribute('aria-hidden', 'true');
  map.prepend(svg);
  cards.forEach((card, index) => card.style.setProperty('--flow-delay', `${index * 2.4}s`));
  function layout() {
    const bounds = map.getBoundingClientRect();
    const origin = map.querySelector('.connection-origin img').getBoundingClientRect();
    svg.setAttribute('viewBox', `0 0 ${bounds.width} ${bounds.height}`);
    svg.replaceChildren();
    if (bounds.width < 600) return;
    const x = origin.right - bounds.left + 12, y = origin.top + origin.height / 2 - bounds.top;
    cards.forEach((card, index) => {
      const end = card.getBoundingClientRect();
      const ex = end.left - bounds.left, ey = end.top + end.height / 2 - bounds.top;
      const middle = x + (ex - x) * .48;
      const d = `M ${x} ${y} C ${middle} ${y}, ${middle} ${ey}, ${ex} ${ey}`;
      for (let segment = -1; segment < 6; segment++) {
        const kind = segment < 0 ? 'track' : 'signal';
        const path = document.createElementNS(svg.namespaceURI, 'path');
        path.setAttribute('d', d);path.setAttribute('pathLength', '100');
        path.classList.add(`flow-${kind}`);
        if (kind === 'signal') {
          const length = 2 + Math.random() * 3;
          path.style.setProperty('--segment-length', length);
          path.style.setProperty('--travel-time', `${.65 + Math.random() * .7}s`);
          path.style.setProperty('--segment-delay', `${-Math.random() * 4}s`);
          path.style.setProperty('--segment-direction', segment % 2 ? 'alternate-reverse' : 'alternate');
          path.style.setProperty('--segment-opacity', .45 + Math.random() * .5);
        }
        svg.append(path);
      }
    });
  }
  let visible = false;
  function sync() { map.classList.toggle('flow-running', visible && !document.hidden && !reduced.matches); }
  const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; sync(); }, {threshold:.3});
  observer.observe(map);
  const resize = new ResizeObserver(layout);resize.observe(map);
  document.fonts.ready.then(layout);
  reduced.addEventListener('change', sync);
  document.addEventListener('visibilitychange', sync);
  window.addEventListener('pagehide', () => {observer.disconnect();resize.disconnect();});
})();
