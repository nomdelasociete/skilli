const demo=document.querySelector('#demo'),card=document.querySelector('#si-card'),keys=document.querySelector('#keys'),message=document.querySelector('#mail-text'),instruction=document.querySelector('#instruction'),label=document.querySelector('#step-label'),completion=document.querySelector('#completion');
const original='feedback received / thanks!\nmeet tomorrow to finish presentation\nask what time works';
const otherOriginal='Thanks for your feedback. Can we meet tomorrow to finalise the presentation?';
const fixed='Thanks for your feedback! Could we meet tomorrow to put the finishing touches on the presentation? Let me know what time works for you.';
let streamTimer = 0;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
function streamResult(){
  clearTimeout(streamTimer);
  step='streaming';render();
  const output=card.querySelector('.stream-output');
  const text=mode==='fix'?fixed:translation();
  const chunks=text.match(/\S+\s*/g)||[];
  let index=0;
  const tick=()=>{
    if(step!=='streaming')return;
    if(reducedMotion.matches||document.hidden||document.body.classList.contains('motion-paused'))index=chunks.length;
    else index++;
    output.textContent=chunks.slice(0,index).join('');
    if(index>=chunks.length){step='result';render();}
    else streamTimer=setTimeout(tick,42);
  };
  streamTimer=setTimeout(tick,450);
}
addEventListener('pagehide',()=>clearTimeout(streamTimer));
let mode='fix',step='idle',language='en';
const choices={fix:{key:'G',name:'Notes → email'},translate:{key:'E',name:'Translate'},act:{key:'A',name:'Prepare a reply'}};
function key(text,action,used=false){const b=document.createElement('button');b.className='key'+(used?' used':'');b.textContent=text;b.setAttribute('aria-label',text==='↵'?'Apply':text==='Esc'?'Cancel':`Key ${text}`);b.onclick=()=>{handle(action);demo.focus({preventScroll:true})};keys.append(b)}
function cardTitle(title){return `<div class="card-title"><img src="../assets/brand/halo-menthe-glass.png" alt="">${title}</div>`}
function reset(){clearTimeout(streamTimer);step='idle';message.textContent=mode==='fix'?original:otherOriginal;message.classList.add('selected');completion.hidden=true;render()}
function render(){demo.setAttribute('aria-label',`Demo: ${choices[mode].name}. Press K then ${choices[mode].key}. Escape cancels.`);keys.replaceChildren();card.hidden=step==='idle'||step==='done';label.textContent=step==='done'?'Done':'Your turn';
if(step==='idle'){instruction.textContent=`Press K, then ${choices[mode].key}. Or click the keys.`;key('K','k');key(choices[mode].key,choices[mode].key.toLowerCase());}
if(step==='leader'){instruction.textContent=`Choose the next key. Press ${choices[mode].key} to ${choices[mode].name.toLowerCase()}.`;card.innerHTML=cardTitle('Your selection')+Object.values(choices).map(c=>`<div class="option"><span>${c.name}</span><kbd>${c.key}</kbd></div>`).join('')+'<div class="card-footer">✦ K &nbsp; · &nbsp; Esc to cancel</div>';key('K','k',true);key(choices[mode].key,choices[mode].key.toLowerCase());key('Esc','escape');}
if(step==='question'){instruction.textContent='Choose a language with 1 or 2. Return selects French.';card.innerHTML=cardTitle('Translate')+'<p>Which language?</p><button data-choice="1">1 &nbsp; French</button><button data-choice="2">2 &nbsp; Spanish</button><div class="card-footer">↵ French by default &nbsp; · &nbsp; Esc cancel</div>';key('1','1');key('2','2');key('↵','enter');key('Esc','escape');}
if(step==='streaming'){instruction.textContent='Your saved command is writing the email…';card.innerHTML=cardTitle(choices[mode].name)+'<p class="stream-output"></p><div class="card-footer">Writing… &nbsp; · &nbsp; Esc cancel</div>';key('Esc','escape');}
if(step==='result'){instruction.textContent='Review the result, then press Return to replace the text.';card.innerHTML=cardTitle(choices[mode].name)+'<p class="stream-output"></p><div class="card-footer">↵ Replace selection &nbsp; · &nbsp; Esc cancel</div>';card.querySelector('.stream-output').textContent=mode==='fix'?fixed:translation();key('↵','enter');key('Esc','escape');}
if(step==='approval'){instruction.textContent='The command asks for permission before replacing your text.';card.innerHTML=cardTitle('Prepare a reply')+'<p class="trace">✓ Selection read<br>✓ Reply prepared</p><p>Replace the selection?</p><p style="font-size:12px;margin-top:8px">Thanks for the feedback! I’m available tomorrow to finish the presentation together.</p><div class="card-footer">↵ Allow &nbsp; · &nbsp; Esc Deny</div>';key('Allow ↵','enter');key('Esc','escape');}
if(step==='done'){instruction.textContent='The result is in your message. Try the sequence again.';key('Try again','restart');}
card.querySelectorAll('[data-choice]').forEach(b=>b.onclick=()=>{handle(b.dataset.choice);demo.focus({preventScroll:true})});}
function translation(){return language==='en'?'Merci pour tes retours. Peut-on se retrouver demain pour finaliser la présentation ?':'Gracias por tus comentarios. ¿Podemos reunirnos mañana para terminar la presentación?'}
function handle(k){if(k==='escape'||k==='restart'){reset();return}if(step==='idle'){if(k==='k'){step='leader';render()}else{instruction.textContent='Start with K to open the commands.'}return}if(step==='leader'){const selected=Object.entries(choices).find(([,c])=>c.key.toLowerCase()===k);if(selected){mode=selected[0];syncTabs();message.textContent=mode==='fix'?original:otherOriginal;if(mode==='fix'){streamResult()}else{step=mode==='translate'?'question':'approval';render()}}else if(k!=='k'){instruction.textContent='Choose G, E or A, or press Escape to cancel.'}return}if(step==='question'&&['1','2','enter'].includes(k)){language=k==='2'?'es':'en';streamResult();return}if(['result','approval'].includes(step)&&k==='enter'){message.textContent=mode==='fix'?fixed:mode==='translate'?translation():'Thanks for the feedback! I’m available tomorrow to finish the presentation together.';message.classList.remove('selected');step='done';completion.hidden=false;render();}}
function syncTabs(){document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)))}
document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;syncTabs();reset();demo.dispatchEvent(new CustomEvent('demo:scenario'));demo.focus({preventScroll:true})});document.querySelector('#reset').onclick=()=>{reset();demo.focus({preventScroll:true})};
demo.addEventListener('keydown',e=>{if(e.metaKey||e.ctrlKey||e.altKey||e.key==='Tab')return;if(e.target.closest('button')&&['Enter',' '].includes(e.key))return;const k=e.key.toLowerCase();if(['k','g','e','a','1','2','enter','escape'].includes(k)){e.preventDefault();handle(k)}});
render();
document.querySelectorAll('a[href="#experience"]').forEach(a=>a.addEventListener('click',()=>{demo.focus({preventScroll:true})}));
