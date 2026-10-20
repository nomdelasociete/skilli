/* Motion 14.1.0, self-hosted. No third-party requests. */
(() => {
  const section = document.querySelector('#speed');
  const layer = section.querySelector('.speed-particles');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const counters = [...section.querySelectorAll('[data-count]')];
  const animations = [];
  let visible = false, counted = false;
  const particles = Array.from({length: 18}, () => {
    const particle = document.createElement('i');
    particle.style.top = `${8 + Math.random() * 84}%`;
    particle.style.width = `${16 + Math.random() * 65}px`;
    particle.style.opacity = .1 + Math.random() * .22;
    layer.append(particle);
    return particle;
  });
  function finalNumbers() {
    counters.forEach(node => { node.textContent = Number(node.dataset.count).toFixed(Number(node.dataset.decimals || 0)); });
  }
  function stop() {
    animations.splice(0).forEach(animation => animation.stop());
    layer.style.opacity = '0';
    finalNumbers();
  }
  function sync() {
    stop();
    if (!visible || reduce.matches || document.hidden || document.body.classList.contains('motion-paused') || !window.Motion) return;
    layer.style.opacity = '1';
    const distance = section.clientWidth;
    particles.forEach(particle => {
      animations.push(Motion.animate(particle, {x: [-100, distance + 100]}, {
        duration: .65 + Math.random() * .7, delay: -Math.random() * 2,
        repeat: Infinity, ease: 'linear'
      }));
    });
    if (!counted) {
      counted = true;
      counters.forEach((node, index) => {
        animations.push(Motion.animate(0, Number(node.dataset.count), {
          duration: 1.25, delay: index * .12, ease: [0.16, 1, 0.3, 1],
          onUpdate: value => { node.textContent = value.toFixed(Number(node.dataset.decimals || 0)); }
        }));
      });
    }
  }
  const observer = new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting; sync();
  }, {threshold: .25});
  observer.observe(section);
  const pauseObserver = new MutationObserver(sync);
  pauseObserver.observe(document.body, {attributes: true, attributeFilter: ['class']});
  reduce.addEventListener('change', sync);
  document.addEventListener('visibilitychange', sync);
  addEventListener('resize', sync);
  addEventListener('pagehide', () => { stop(); observer.disconnect(); pauseObserver.disconnect(); });
})();
