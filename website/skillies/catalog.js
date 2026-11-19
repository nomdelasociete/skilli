(() => {
  const search = document.querySelector('#skillie-search');
  const entries = [...document.querySelectorAll('.skillie-entry')];
  const filters = [...document.querySelectorAll('[data-filter]')];
  let category = 'all';
  function filter() {
    const words = search.value.toLowerCase().trim().split(/\s+/);
    entries.forEach(entry => { entry.hidden = !(category === 'all' || entry.dataset.category === category) || !words.every(word => entry.dataset.search.includes(word)); });
    document.querySelector('#empty-library').hidden = entries.some(entry => !entry.hidden);
  }
  search.addEventListener('input', filter);
  filters.forEach(button => button.onclick = () => {category = button.dataset.filter;filters.forEach(item => item.setAttribute('aria-pressed', String(item === button)));filter();});
  document.querySelectorAll('[data-share]').forEach(button => button.onclick = async () => {
    const url = new URL(location.href);url.hash = button.dataset.share;
    const entry = button.closest('.skillie-entry');
    const status = entry.querySelector('.share-status');
    const link = entry.querySelector('.share-link');
    try {
      await navigator.clipboard.writeText(url.href);
      button.textContent = 'Copied ✓';
      link.hidden = true;
      status.textContent = ['127.0.0.1','localhost'].includes(location.hostname) ? 'Link copied. This preview link works on this computer only.' : 'Link copied. Ready to share.';
    } catch {
      button.textContent = 'Copy link ↗';
      status.textContent = 'Couldn’t copy automatically. Select and copy the link below.';
      link.value = url.href;
      link.hidden = false;
      link.focus();
      link.select();
    }
  });
})();
