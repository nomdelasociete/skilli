(() => {
  const demo = document.querySelector('.agent-demo');
  const play = demo.querySelector('.agent-play');
  const allow = demo.querySelector('.agent-allow');
  const approval = demo.querySelector('.agent-approval');
  const created = demo.querySelector('.agent-created');
  const live = demo.querySelector('.agent-live');
  const state = demo.querySelector('.agent-state');
  const steps = [...demo.querySelectorAll('.agent-steps li')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let timer;
  function review() {
    demo.dataset.stage = 'review'; approval.hidden = false;
    state.textContent = 'Your approval'; live.textContent = 'The script is ready. You decide whether to create it.';
    steps[1].classList.add('active');play.disabled = false;
  }
  play.onclick = () => {
    clearTimeout(timer); created.hidden = true; approval.hidden = true;
    steps.forEach(step => step.classList.remove('active')); steps[0].classList.add('active');
    demo.dataset.stage = 'writing';state.textContent = 'Writing';live.textContent = 'Your agent writes the script and asks skil.li to create it.';
    play.textContent = 'Replay creation ↻';play.disabled = true;
    if (reduced.matches) review(); else timer = setTimeout(review, 1100);
  };
  allow.onclick = () => {
    approval.hidden = true; created.hidden = false; demo.dataset.stage = 'created';
    state.textContent = 'Skillie created';steps[2].classList.add('active');
    live.textContent = 'Project status is ready. Future runs execute the script locally, without AI.';
    play.focus({preventScroll:true});
  };
  document.addEventListener('visibilitychange', () => {if(document.hidden && play.disabled){clearTimeout(timer);review();}});
  reduced.addEventListener('change', () => {if(reduced.matches && play.disabled){clearTimeout(timer);review();}});
  const observer = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    observer.disconnect();
    if (!reduced.matches && !document.body.classList.contains('motion-paused')) play.click();
  }, {threshold:.4});
  observer.observe(demo);
  window.addEventListener('pagehide', () => {clearTimeout(timer);observer.disconnect();});
})();
