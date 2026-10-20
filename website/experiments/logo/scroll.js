const story = document.querySelector('.story');
const frame = document.querySelector('iframe');
const hint = document.querySelector('.hint');
let pending = false;
function update() {
  pending = false;
  const rect = story.getBoundingClientRect();
  const distance = story.offsetHeight - innerHeight;
  const progress = Math.max(0, Math.min(1, -rect.top / Math.max(1, distance)));
  frame.contentWindow.postMessage({ type: 'logo-scroll', progress }, location.origin);
  hint.style.opacity = String(1 - Math.min(1, progress * 8));
}
function schedule() { if (!pending) { pending = true; requestAnimationFrame(update); } }
addEventListener('scroll', schedule, { passive: true });
addEventListener('resize', schedule);
frame.addEventListener('load', update);
update();
