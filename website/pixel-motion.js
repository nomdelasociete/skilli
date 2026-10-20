// Keep Line's layout; Square and Circle are paint-only layers.
(() => {
  const comparing = new URLSearchParams(location.search).has('type');
  const headings = document.querySelectorAll(comparing ? 'h2' : '.opening h1, h2');
  const fontsReady = Promise.all(['line', 'square', 'circle'].map(cut => document.fonts.load(`400 48px "Geist Pixel ${cut}"`)));
  for (const heading of headings) {
    const isHero = heading.matches('h1');
    const reduced = matchMedia('(prefers-reduced-motion: reduce)');
    const characters = [];
    const timers = new Map();
    let visible = false;
    let played = false;
    let arrival;
    const allowed = () => !reduced.matches && !document.hidden && visible;
    heading.setAttribute('aria-label', [...heading.childNodes].map(node => node.nodeName === 'BR' ? ' ' : node.classList?.contains('si-label') ? 'SI' : node.textContent).join(''));
    for (const node of [...heading.childNodes]) {
      if (node.nodeType !== Node.TEXT_NODE) continue;
      const fragment = document.createDocumentFragment();
      for (const word of node.textContent.split(/(\s+)/)) {
        if (/^\s+$/.test(word)) { fragment.append(document.createTextNode(word)); continue; }
        const wordSpan = document.createElement('span');
        wordSpan.className = 'pixel-word';
        fragment.append(wordSpan);
        for (const letter of word) {
        const character = document.createElement('span');
        character.className = 'pixel-character';
        character.setAttribute('aria-hidden', 'true');
        for (const cut of ['line', 'square', 'circle']) {
          const layer = document.createElement('span');
          layer.className = `pixel-${cut}`;
          layer.textContent = letter;
          character.append(layer);
        }
        wordSpan.append(character);
        characters.push(character);
        }
      }
      node.replaceWith(fragment);
    }
    function pulse(character, delay = 0) {
      if (!allowed() || timers.has(character)) return;
      character.style.setProperty('--pixel-delay', `${delay}ms`);
      character.classList.add('pixel-active');
      timers.set(character, setTimeout(() => {
        character.classList.remove('pixel-active');
        timers.delete(character);
      }, delay + 520));
    }
    function stop() {
      clearTimeout(arrival);
      for (const [character, timer] of timers) {
        clearTimeout(timer);
        character.classList.remove('pixel-active');
      }
      timers.clear();
    }
    if (isHero) heading.addEventListener('pointerover', event => {
      if (event.pointerType === 'touch') return;
      const character = event.target.closest('.pixel-character');
      const index = characters.indexOf(character);
      if (index < 0) return;
      pulse(character);
      if (characters[index + 1]) pulse(characters[index + 1], 65);
    });
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (!visible) { stop(); return; }
      if (played || !allowed()) return;
      played = true;
      arrival = setTimeout(() => characters.forEach((character, index) => pulse(character, index * 32)), isHero ? 450 : 100);
    }, { threshold: 0.55, rootMargin: '0px 0px -8% 0px' });
    reduced.addEventListener('change', stop);
    document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
    fontsReady.then(() => observer.observe(heading)).catch(() => {});
    window.addEventListener('pagehide', () => { stop(); observer.disconnect(); });
  }
})();
