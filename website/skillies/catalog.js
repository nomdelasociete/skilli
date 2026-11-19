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
})();
