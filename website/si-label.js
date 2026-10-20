// SI is the public label; reveal AI on hover, keyboard focus or touch.
(() => {
  const skip = 'script,style,textarea,input,code,pre,svg,.si-label,.pixel-character';
  function prepare(label) {
    if (label.dataset.ready) return;
    label.dataset.ready = 'true';
    label.setAttribute('aria-label', 'SI (AI)');
    if (!label.closest('a,button,summary')) label.tabIndex = 0;
    label.classList.toggle('si-pixel', getComputedStyle(label).fontFamily.includes('Geist Pixel'));
    const resting = document.createElement('span');
    resting.className = 'si-rest'; resting.textContent = 'SI';
    const revealed = document.createElement('span');
    revealed.className = 'si-reveal'; revealed.textContent = 'AI';
    resting.setAttribute('aria-hidden', 'true'); revealed.setAttribute('aria-hidden', 'true');
    label.replaceChildren(resting, revealed);
    label.addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch') label.classList.toggle('si-touched');
    });
    label.addEventListener('blur', () => label.classList.remove('si-touched'));
  }
  function scan(root) {
    if (root.nodeType === Node.ELEMENT_NODE && root.closest(skip)) return;
    if (root.nodeType === Node.ELEMENT_NODE) {
      if (root.matches('.si-label')) { prepare(root); return; }
      root.querySelectorAll('.si-label:not([data-ready])').forEach(prepare);
    }
    const nodes = [];
    if (root.nodeType === Node.TEXT_NODE) nodes.push(root);
    else {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      while (walker.nextNode()) nodes.push(walker.currentNode);
    }
    for (const node of nodes) {
      if (node.parentElement?.closest(skip) || !/\bAI\b/.test(node.textContent)) continue;
      const fragment = document.createDocumentFragment();
      node.textContent.split(/(\bAI\b)/).forEach(part => {
        if (part !== 'AI') { fragment.append(part); return; }
        const label = document.createElement('span');
        label.className = 'si-label'; label.textContent = 'SI'; fragment.append(label);
      });
      const parent = node.parentElement;
      node.replaceWith(fragment);
      parent.querySelectorAll('.si-label:not([data-ready])').forEach(prepare);
    }
  }
  scan(document.body);
  // Demos replace their result text while playing.
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === 'characterData') scan(record.target);
      else record.addedNodes.forEach(scan);
    }
  });
  observer.observe(document.body, {childList:true, subtree:true, characterData:true});
  addEventListener('pagehide', () => observer.disconnect());
})();
