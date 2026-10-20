(() => {
  const word = document.querySelector('.must-emphasis');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let visible = false, played = false, animation, timer, lastShake = -Infinity;
  function shake() {
    if (!visible || document.hidden || reduce.matches || document.body.classList.contains('motion-paused') || performance.now() - lastShake < 1400) return;
    lastShake = performance.now();
    animation?.cancel();
    animation = word.animate([
      {transform:'translate(0,0) rotate(0deg)'},
      {transform:'translate(-1.4px,.2px) rotate(-1deg)'},
      {transform:'translate(1.4px,-.3px) rotate(1deg)'},
      {transform:'translate(-1.2px,0) rotate(-.7deg)'},
      {transform:'translate(1px,.2px) rotate(.7deg)'},
      {transform:'translate(-.7px,0) rotate(-.4deg)'},
      {transform:'translate(.5px,0) rotate(.2deg)'},
      {transform:'translate(0,0) rotate(0deg)'}
    ], {duration:420, iterations:1, easing:'linear'});
  }
  function stop() { clearTimeout(timer); animation?.cancel(); }
  const observer = new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (!visible) stop();
    else if (!played && !reduce.matches) {
      timer = setTimeout(() => { if (visible && !document.hidden) { played = true; shake(); } }, 900);
    }
  }, {threshold:1});
  observer.observe(word);
  word.addEventListener('pointerenter', shake);
  word.addEventListener('click', shake);
  reduce.addEventListener('change', stop);
  document.addEventListener('visibilitychange', () => { if(document.hidden) stop(); });
  const pause = new MutationObserver(() => { if(document.body.classList.contains('motion-paused')) stop(); });
  pause.observe(document.body, {attributes:true, attributeFilter:['class']});
  addEventListener('pagehide', () => { stop(); observer.disconnect(); pause.disconnect(); });
})();
