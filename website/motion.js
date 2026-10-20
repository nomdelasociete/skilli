(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 700px)');
  const story = document.querySelector('.ask-story');
  const theatre = document.querySelector('.ask-theatre');
  const bubble = document.querySelector('.ask-bubble');
  const transcript = document.querySelector('#ask-transcript');
  const result = document.querySelector('#found-result');
  const hint = document.querySelector('#ask-hint');
  const returnKey = document.querySelector('#ask-return');
  const chapters = [...document.querySelectorAll('.chapter')];
  const motionButton = document.querySelector('#demo-motion');
  const replayButton = document.querySelector('#story-replay');
  const demo = document.querySelector('#demo');
  const watch = document.querySelector('#watch-demo');
  const opener = document.querySelector('.opening');
  const caption = document.querySelector('.opening-caption');
  const launcher = document.querySelector('.launcher-scene');
  function playbackBar(parent, before, label) {
    const bar = document.createElement('div');
    bar.className = 'playback-progress';
    bar.setAttribute('role', 'progressbar');
    bar.setAttribute('aria-label', label);
    bar.setAttribute('aria-valuemin', '0');
    bar.setAttribute('aria-valuemax', '100');
    bar.setAttribute('aria-valuenow', '0');
    const fill = document.createElement('span');
    bar.append(fill); parent.insertBefore(bar, before);
    let animation, timer;
    function stop() {
      animation?.pause(); clearInterval(timer);
      bar.classList.remove('is-playing');
    }
    function finish() {
      stop(); animation?.cancel(); fill.style.transform = 'scaleX(1)';
      bar.setAttribute('aria-valuenow', '100');
      bar.setAttribute('aria-valuetext', 'Step complete');
    }
    function start(duration) {
      stop(); animation?.cancel();
      bar.classList.add('is-visible', 'is-playing');
      bar.setAttribute('aria-valuenow', '0');
      bar.setAttribute('aria-valuetext', `${(duration / 1000).toFixed(1)} seconds remaining`);
      animation = fill.animate([{transform:'scaleX(0)'}, {transform:'scaleX(1)'}], {
        duration, easing:'linear', fill:'forwards'
      });
      timer = setInterval(() => {
        const elapsed = Number(animation.currentTime || 0);
        bar.setAttribute('aria-valuenow', String(Math.min(100, Math.round(elapsed / duration * 100))));
        bar.setAttribute('aria-valuetext', `${Math.max(0, (duration - elapsed) / 1000).toFixed(1)} seconds remaining`);
      }, 200);
      animation.onfinish = finish;
    }
    return {start, stop, finish};
  }
  const keyboardProgress = playbackBar(demo, demo.querySelector('.demo-console'), 'Keyboard demo step playback');
  const storyProgress = playbackBar(theatre, null, 'Ask demo step playback');
  let active = 0, paused = false, storyVisible = false, frame = 0, chapterFinished = false;
  let storyTimers = [], demoTimers = [], hasPlayed = false, interacted = false;
  const request = 'Turn these notes into a friendly, clear email.';
  const draft = document.querySelector('#story-draft');
  const original = draft.textContent;
  const rewriteNode = document.querySelector('.rewrite-text');
  const rewritten = rewriteNode.textContent;
  const outcome = document.querySelector('#story-outcome');
  const storyKeys = [...document.querySelectorAll('[data-story-key]')];
  let sequenceStep = 0;
  const canAnimate = () => !paused && !reduce.matches && !document.hidden;
  const later = (fn, delay) => storyTimers.push(setTimeout(fn, delay));
  function clearStory() { storyProgress.stop(); storyTimers.forEach(clearTimeout); storyTimers = []; }
  function stopDemo() {
    keyboardProgress.stop();
    demoTimers.forEach(clearTimeout); demoTimers = [];
    demo.classList.remove('is-playing'); watch.textContent = 'Watch demo ▷';
    watch.setAttribute('aria-pressed', 'false');
  }
  function showResult(stream = false, thenApply = false) {
    transcript.textContent = request;
    bubble.classList.remove('is-typing', 'listening');
    bubble.classList.add('has-result'); result.classList.add('visible');
    theatre.classList.add('reviewing');
    const finish = () => {
      rewriteNode.textContent = rewritten;
      bubble.classList.remove('is-streaming');
      hint.textContent = 'Return to replace the selection';
      returnKey.disabled = false;
      if (thenApply) later(applyRewrite, 1200);
    };
    if (!stream || !canAnimate()) { finish(); return; }
    returnKey.disabled = true;
    hint.textContent = 'Writing your email…';
    bubble.classList.add('is-streaming');
    rewriteNode.textContent = '';
    const chunks = rewritten.match(/\S+\s*/g) || [];
    chunks.forEach((_, i) => later(() => {
      rewriteNode.textContent = chunks.slice(0, i + 1).join('');
      if (i === chunks.length - 1) finish();
    }, 450 + i * 42));
  }
  function applyRewrite() {
    if (!result.classList.contains('visible') || returnKey.disabled) return;
    clearStory(); storyProgress.finish(); chapterFinished = true;
    returnKey.classList.add('pressed');
    draft.textContent = rewritten;
    theatre.classList.add('completed');
    outcome.classList.add('visible'); outcome.setAttribute('aria-hidden', 'false');
    storyKeys.forEach(key => key.classList.remove('pressed'));
  }
  function pressStoryKey(key) {
    const node = storyKeys.find(node => node.dataset.storyKey === key);
    if (node) node.classList.add('pressed');
    if (key !== 'hyper') later(() => node?.classList.remove('pressed'), 240);
  }
  function sequenceInput(key) {
    if (active !== 2) return;
    if (key === 'hyper') { pressStoryKey(key); return; }
    if (key === 'k') {
      clearStory(); sequenceStep = 1; chapterFinished = false;
      theatre.classList.remove('completed', 'reviewing');
      outcome.classList.remove('visible'); outcome.setAttribute('aria-hidden', 'true');
      draft.textContent = original;
      bubble.classList.remove('has-result'); result.classList.remove('visible');
      pressStoryKey('hyper'); pressStoryKey('k');
      theatre.classList.add('sequence-armed');
      if (canAnimate()) storyProgress.start(4000);
    } else if (key === 's' && sequenceStep === 1) {
      sequenceStep = 2; pressStoryKey('s'); showResult(true);
    } else if (key === 'enter' && sequenceStep === 2) { pressStoryKey('enter'); applyRewrite(); }
  }
  function renderChapter() {
    clearStory(); chapterFinished = false; sequenceStep = 0;
    chapters.forEach((button, i) => {
      button.classList.toggle('active', i === active);
      button.setAttribute('aria-pressed', String(i === active));
    });
    theatre.dataset.scene = active;
    document.querySelector('.sequence-dock').inert = active !== 2;
    theatre.classList.remove('completed', 'reviewing', 'sequence-armed');
    bubble.classList.remove('has-result', 'listening', 'is-typing', 'is-streaming');
    result.classList.remove('visible'); returnKey.classList.remove('pressed');
    returnKey.disabled = true;
    storyKeys.forEach(key => key.classList.remove('pressed'));
    draft.textContent = original;
    outcome.classList.remove('visible'); outcome.setAttribute('aria-hidden', 'true');
    document.querySelector('#ask-mode').textContent = active === 2 ? 'Notes → email' : 'Ask by Voice';
    document.querySelector('#ask-trigger').textContent = active === 2 ? '✦ K S' : 'Your shortcut';
    hint.textContent = 'On-device transcription · Return to ask';
    transcript.textContent = request;
    if (!canAnimate() || !storyVisible) { showResult(); if(active === 2) sequenceStep = 2; return; }
    const streamDuration = 450 + ((rewritten.match(/\S+\s*/g) || []).length - 1) * 42;
    storyProgress.start(active === 0 ? 2700 + streamDuration : active === 1 ? streamDuration + 1200 : 5200);
    if (active === 0) {
      bubble.classList.add('is-typing', 'listening'); transcript.textContent = '';
      [...request].forEach((_, i) => later(() => { transcript.textContent = request.slice(0, i + 1); }, 300 + i * 40));
      later(() => { bubble.classList.remove('is-typing', 'listening'); hint.textContent = 'Return to ask'; }, 2250);
      later(() => showResult(true), 2700);
    } else if (active === 1) {
      showResult(true, true);
    } else {
      // The same mail stays anchored while the voice card folds into a saved command.
      later(() => {
        sequenceInput('k');
        later(() => sequenceInput('s'), 550);
        later(() => { pressStoryKey('enter'); applyRewrite(); }, 4000);
      }, 1200);
    }
  }
  chapters.forEach((button, i) => button.addEventListener('click', () => {
    active = i; renderChapter();
    if (!compact.matches && !reduce.matches) {
      const top = story.getBoundingClientRect().top + scrollY;
      const travel = story.offsetHeight - innerHeight + 84;
      scrollTo({ top: top - 84 + travel * ((i + .2) / 3), behavior: 'instant' });
    }
  }));
  storyKeys.forEach(button => button.addEventListener('click', () => sequenceInput(button.dataset.storyKey)));
  returnKey.addEventListener('click', applyRewrite);
  theatre.addEventListener('keydown', event => {
    if (event.target !== theatre) return;
    const key = event.key.toLowerCase();
    if (['enter','k','s'].includes(key)) { event.preventDefault(); active === 2 ? sequenceInput(key) : key === 'enter' && applyRewrite(); }
    if (key === 'escape') renderChapter();
  });
  replayButton.addEventListener('click', renderChapter);
  function playDemo(remaining = Object.keys(choices).length) {
    stopDemo();
    syncTabs(); reset();
    if (!canAnimate()) return;
    keyboardProgress.start(6500);
    demo.classList.add('is-playing'); watch.textContent = 'Take over Ⅱ';
    watch.setAttribute('aria-pressed', 'true');
    const sequence = [[450, 'k'], [1250, choices[mode].key.toLowerCase()]];
    if (mode === 'translate') sequence.push([2050, '1']);
    sequence.push([4400, 'enter']);
    sequence.forEach(([delay, key]) => {
      demoTimers.push(setTimeout(() => handle(key), delay));
    });
    demoTimers.push(setTimeout(() => {
      if (remaining <= 1) { stopDemo(); keyboardProgress.finish(); return; }
      const modes = Object.keys(choices);
      mode = modes[(modes.indexOf(mode) + 1) % modes.length];
      playDemo(remaining - 1);
    }, 6500));
  }
  demo.addEventListener('demo:scenario', () => {
    interacted = true;
    playDemo();
  });
  watch.addEventListener('click', () => {
    interacted = true;
    if (demo.classList.contains('is-playing')) stopDemo(); else playDemo();
  });
  demo.addEventListener('pointerdown', event => {
    if (event.target.closest('#watch-demo')) return;
    interacted = true; stopDemo();
  }, true);
  demo.addEventListener('keydown', () => { interacted = true; stopDemo(); }, true);
  const demoObserver = new IntersectionObserver(entries => {
    if (entries[0].isIntersecting) {
      if (!hasPlayed && !interacted && canAnimate()) { hasPlayed = true; playDemo(); }
    } else stopDemo();
  }, {threshold: .5});
  demoObserver.observe(demo);
  const storyObserver = new IntersectionObserver(entries => {
    storyVisible = entries[0].isIntersecting;
    if (storyVisible && canAnimate() && !chapterFinished) renderChapter();
    else { clearStory(); bubble.classList.remove('listening', 'is-typing'); }
  }, {threshold: .3});
  storyObserver.observe(theatre);
  function updateScroll() {
    frame = 0;
    if (!canAnimate()) {
      caption.style.transform = ''; caption.style.opacity = '';
      launcher.style.transform = ''; launcher.querySelector('img').style.transform = '';
      return;
    }
    const heroProgress = Math.max(0, Math.min(1, -opener.getBoundingClientRect().top / opener.offsetHeight));
    caption.style.transform = `translateY(${heroProgress * 45}px)`;
    caption.style.opacity = String(Math.max(0, 1 - heroProgress * 1.7));
    const rect = launcher.getBoundingClientRect();
    const p = Math.max(0, Math.min(1, (innerHeight - rect.top) / (innerHeight * .85)));
    launcher.style.transform = '';
    launcher.style.opacity = String(.65 + .35 * p);
    launcher.querySelector('img').style.transform = '';
    if (!compact.matches && storyVisible) {
      const rect = story.getBoundingClientRect();
      const travel = story.offsetHeight - innerHeight + 84;
      const p = Math.max(0, Math.min(.999, (84 - rect.top) / travel));
      const next = Math.floor(p * 3);
      if (next !== active) { active = next; renderChapter(); }
    }
  }
  function scrollFrame() { if (!frame) frame = requestAnimationFrame(updateScroll); }
  function syncMotion() {
    document.body.classList.toggle('motion-paused', paused || reduce.matches);
    motionButton.textContent = paused ? 'Play demos ▷' : 'Pause demos Ⅱ';
    motionButton.setAttribute('aria-pressed', String(paused));
    stopDemo(); renderChapter(); scrollFrame();
  }
  motionButton.addEventListener('click', () => { paused = !paused; syncMotion(); });
  reduce.addEventListener('change', syncMotion);
  compact.addEventListener('change', () => { renderChapter(); scrollFrame(); });
  document.addEventListener('visibilitychange', syncMotion);
  addEventListener('scroll', scrollFrame, {passive:true});
  addEventListener('resize', scrollFrame);
  addEventListener('pagehide', () => {
    clearStory(); stopDemo(); cancelAnimationFrame(frame);
    storyObserver.disconnect(); demoObserver.disconnect();
  });
  renderChapter(); scrollFrame();
})();
