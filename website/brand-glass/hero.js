(() => {
  const opening = document.querySelector('.opening-glass');
  const frame = opening.querySelector('iframe');
  const brand = document.querySelector('.opening-brand a');
  const nav = document.querySelector('.nav');
  const menu = document.querySelector('.nav-menu');
  const sheet = document.getElementById('site-nav');
  const backdrop = document.querySelector('.nav-backdrop');
  const mobile = matchMedia('(max-width: 700px)');
  const compact = matchMedia('(max-width: 960px)');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let pending = false;
  let lastFocus = null;

  function post(data) {
    try { frame.contentWindow.postMessage(data, location.origin); } catch {}
  }
  function onOrient(event) {
    if (!mobile.matches || (event.beta == null && event.gamma == null)) return;
    post({ type: 'logo-tilt', beta: event.beta, gamma: event.gamma });
  }
  if (!reduce.matches) {
    addEventListener('deviceorientation', onOrient);
    addEventListener('deviceorientationabsolute', onOrient);
  }

  function update() {
    pending = false;
    const distance = innerHeight * .7;
    const progress = Math.max(0, Math.min(1, -opening.getBoundingClientRect().top / Math.max(1, distance)));
    frame.contentWindow.postMessage({type:'logo-scroll',progress}, location.origin);
    brand.classList.toggle('has-menu-mark', nav.getBoundingClientRect().top <= 1);
    const smooth = (a,b) => { const t=Math.max(0,Math.min(1,(progress-a)/(b-a)));return t*t*(3-2*t); };
    const shift=(smooth(.04,.70)*2.7+smooth(.74,1)*.35)*Math.min(innerWidth,innerHeight)/5.8;
    opening.style.setProperty('--caption-shift', `${-shift}px`);
    opening.classList.toggle('is-refracting', progress >= .24);
    opening.style.setProperty('--cue-opacity', String(1-Math.min(1,progress*5)));
  }
  function schedule() { if (!pending) { pending = true; requestAnimationFrame(update); } }

  function focusables() {
    return [menu, ...sheet.querySelectorAll('a')].filter(el => el && !el.hidden);
  }
  function parkMenu() {
    nav.insertBefore(sheet, nav.querySelector('.nav-end'));
    nav.append(backdrop);
  }
  function closeMenu() {
    if (!nav.classList.contains('is-open')) return;
    nav.classList.remove('is-open');
    menu.setAttribute('aria-expanded', 'false');
    menu.setAttribute('aria-label', 'Open menu');
    document.body.classList.remove('nav-locked');
    parkMenu();
    (lastFocus || menu).focus();
  }
  function openMenu() {
    lastFocus = document.activeElement;
    document.body.append(backdrop, sheet);
    nav.classList.add('is-open');
    menu.setAttribute('aria-expanded', 'true');
    menu.setAttribute('aria-label', 'Close menu');
    document.body.classList.add('nav-locked');
    (sheet.querySelector('a') || menu).focus();
  }
  function toggleMenu() { nav.classList.contains('is-open') ? closeMenu() : openMenu(); }

  menu?.addEventListener('click', toggleMenu);
  backdrop?.addEventListener('click', closeMenu);
  sheet?.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
  document.addEventListener('keydown', event => {
    if (!nav.classList.contains('is-open')) return;
    if (event.key === 'Escape') { event.preventDefault(); closeMenu(); return; }
    if (event.key !== 'Tab') return;
    const nodes = focusables();
    if (!nodes.length) return;
    const first = nodes[0], last = nodes[nodes.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
  compact.addEventListener('change', () => { if (!compact.matches) closeMenu(); });

  addEventListener('scroll', schedule, {passive:true});
  addEventListener('resize', schedule);
  frame.addEventListener('load', update);
  update();
})();
