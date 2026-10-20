(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const players = [...document.querySelectorAll('[data-qte]')].map(scene => {
    const keys = [...scene.querySelectorAll('.large-key, kbd')];
    const links = [...scene.querySelectorAll('.line')];
    let timers = [], visible = false;
    const later = (fn, delay) => timers.push(setTimeout(fn, delay));
    const disabled = () => !visible || reduce.matches || document.hidden || document.body.classList.contains('motion-paused');
    function clear() {
      timers.forEach(clearTimeout); timers = [];
      scene.classList.remove('sequence-running', 'sequence-arrived', 'sequence-reset');
      keys.forEach(key => key.classList.remove('is-held', 'is-pressed', 'is-done'));
      links.forEach(link => link.classList.remove('is-traversing', 'is-traversed'));
    }
    function run() {
      clear();
      if (disabled()) return;
      // Commit the invisible reset before starting the next forward pass.
      void scene.offsetWidth;
      scene.classList.add('sequence-running');
      keys[0].classList.add('is-held');
      keys.slice(1).forEach((key, i) => {
        const depart = 150 + i * 500;
        const arrive = depart + 420;
        const link = links.length === keys.length - 1 ? links[i] : (i ? links[0] : null);
        later(() => link?.classList.add('is-traversing', 'is-traversed'), depart);
        later(() => {
          link?.classList.remove('is-traversing');
          key.classList.add('is-pressed', 'is-done');
          if (i === keys.length - 2) scene.classList.add('sequence-arrived');
        }, arrive);
        later(() => key.classList.remove('is-pressed'), arrive + 180);
      });
      const arrival = 570 + (keys.length - 2) * 500;
      later(() => keys[0].classList.remove('is-held'), arrival + 350);
      later(() => scene.classList.add('sequence-reset'), arrival + 1000);
      later(run, arrival + 1700);
    }
    scene.querySelector('.qte-replay').addEventListener('click', run);
    const observer = new IntersectionObserver(entries => {visible = entries[0].isIntersecting; run();}, {threshold:.4});
    observer.observe(scene);
    return {clear, run, observer};
  });
  const sync = () => players.forEach(player => player.run());
  reduce.addEventListener('change', sync);
  document.addEventListener('visibilitychange', sync);
  const pauseObserver = new MutationObserver(sync);
  pauseObserver.observe(document.body, {attributes:true, attributeFilter:['class']});
  addEventListener('pagehide', () => {players.forEach(p => {p.clear();p.observer.disconnect();});pauseObserver.disconnect();});
})();
