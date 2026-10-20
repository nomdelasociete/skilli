(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const stage = document.querySelector('.action-stage');
  const query = document.querySelector('#action-query');
  const response = document.querySelector('#action-response');
  const route = document.querySelector('#action-route');
  const caption = document.querySelector('#action-caption');
  let timers = [], scene = 'awake', visible = false, entered = false;
  const examples = {
    awake: {query:'Keep my Mac awake.', route:'Mac command', title:'Keep Awake', detail:'Sleep is prevented until you choose Allow Sleep.', caption:'Ask selects a built-in command. No agent loop needed.', button:'Run ↵', done:'Keep Awake is on. Your download can keep running.'},
    open: {query:'Open my vector drawing app.', route:'Installed apps', title:'Which app?', detail:'Two installed apps match your request.', caption:'When more than one app fits and Ask is unsure, you choose.', apps:['VectorCraft','Adobe Illustrator']},
    export: {query:'Export the current document.', route:'skil.li · Matching action', title:'Save As…', detail:'Word is in front.', caption:'One shortcut, one intention. The action adapts to the app and the menus it exposes.', contextual:true},
    message: {query:'Tell Camille in Slack: the release is ready.', route:'Tools · Slack', title:'Send to Camille Martin in Slack?', detail:'“The release is ready.”', caption:'The conversation is opened and checked before you confirm who receives the message.', button:'Send ↵', done:'Message sent to Camille Martin.'}
  };
  function cancel() { timers.forEach(clearTimeout); timers=[]; }
  function later(fn, ms) { timers.push(setTimeout(fn,ms)); }
  function finish() {
    const item=examples[scene]; stage.classList.add('settled');
    response.replaceChildren();
    const title=document.createElement('h3'); title.textContent=item.title;
    const detail=document.createElement('p'); detail.textContent=item.detail;
    response.append(title,detail);
    if(item.contextual) {
      const apps=[['Word','Save As…'],['Illustrator','Export…'],['InDesign','Export…'],['Video editor','Render…']];
      const selector=document.createElement('div');selector.className='export-apps';
      selector.setAttribute('role','group');selector.setAttribute('aria-label','Choose the foreground app');
      const shortcut=document.createElement('div');shortcut.className='export-shortcut';
      shortcut.innerHTML='<div class="export-keys" role="img" aria-label="Example shortcut: Command Shift E"><kbd>⌘</kbd><kbd>⇧</kbd><kbd>E</kbd></div><span>Your keys. Your choice.</span>';
      const pressKeys=()=>{
        if(reduced.matches || document.body.classList.contains('motion-paused'))return;
        shortcut.querySelectorAll('kbd').forEach(key=>key.animate([{transform:'translateY(0)'},{transform:'translateY(3px)',background:'#35564e',borderColor:'#a6d9c7'},{transform:'translateY(0)'}],{duration:320,easing:'ease-out'}));
      };
      const buttons=apps.map(([app,action],index)=>{
        const button=document.createElement('button');button.textContent=app;
        button.setAttribute('aria-pressed',String(index===0));
        button.onclick=()=>{
          pressKeys();
          title.textContent=action;detail.textContent=`${app} is in front.`;
          buttons.forEach((b,i)=>b.setAttribute('aria-pressed',String(i===index)));
        };
        selector.append(button);return button;
      });
      response.prepend(selector,shortcut);
    } else if(item.apps) {
      item.apps.forEach((app,index)=>{
        const button=document.createElement('button');
        button.textContent=`${index+1} · ${app}`;
        button.onclick=()=>{
          cancel();title.textContent=app;detail.textContent=`${app} is now in front.`;
          response.querySelectorAll('button').forEach(b=>b.remove());stage.classList.add('action-done');
        };
        response.append(button);
      });
    } else if(item.choices) {
      ['1 · Answer here','2 · Rewrite the selection'].forEach((label,index)=>{
        const button=document.createElement('button');button.textContent=label;
        button.onclick=()=>{cancel();title.textContent=index?'Rewrite the selection':'Answer here';detail.textContent=index?'The translated text will replace your selection after you review it.':'The translation will stay in the card for you to read.';response.querySelectorAll('button').forEach(b=>b.remove());};response.append(button);
      });
    } else {
      const button=document.createElement('button');button.textContent=item.button;
      button.onclick=()=>{title.textContent='Done';detail.textContent=item.done;response.querySelectorAll('button').forEach(b=>b.remove());stage.classList.add('action-done');};response.append(button);
      if(scene==='message'){const deny=document.createElement('button');deny.textContent='Cancel';deny.onclick=()=>{title.textContent='Cancelled';detail.textContent='Nothing sent.';response.querySelectorAll('button').forEach(b=>b.remove());};response.append(deny);}
    }
  }
  function render(animate=true) {
    cancel(); const item=examples[scene];
    stage.classList.remove('settled','action-done');query.textContent=item.query;route.textContent=item.route;caption.textContent=item.caption;response.replaceChildren();
    stage.classList.toggle('contextual-ask', Boolean(item.contextual));
    if (item.contextual) {
      const claim=document.createElement('strong');claim.textContent='One shortcut. One intention.';
      const explanation=document.createElement('span');explanation.textContent='The action adapts to the app and the menus it exposes.';
      caption.replaceChildren(claim,explanation);
      stage.insertBefore(caption,stage.querySelector('.action-request'));
    } else stage.append(caption);

    document.querySelectorAll('[data-action-scene]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.actionScene===scene)));
    if(!animate || !visible || reduced.matches || document.body.classList.contains('motion-paused') || document.hidden){finish();return;}
    query.textContent=''; [...item.query].forEach((_,i)=>later(()=>query.textContent=item.query.slice(0,i+1),i*27));later(finish,item.query.length*27+350);
  }
  document.querySelectorAll('[data-action-scene]').forEach(b=>b.onclick=()=>{scene=b.dataset.actionScene;render();});
  document.querySelector('.action-workspace').addEventListener('keydown',event=>{if(scene==='open' && !event.metaKey && !event.ctrlKey && !event.altKey && ['1','2'].includes(event.key)){const button=response.querySelectorAll('button')[Number(event.key)-1];if(button){event.preventDefault();button.click();}}});
  const observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;if(visible && !entered){entered=true;render();}else if(!visible && !stage.classList.contains('settled')){cancel();query.textContent=examples[scene].query;finish();}}, {threshold:.45});observer.observe(stage);
  const motionObserver=new MutationObserver(()=>{if(document.body.classList.contains('motion-paused')){cancel();query.textContent=examples[scene].query;finish();}});motionObserver.observe(document.body,{attributes:true,attributeFilter:['class']});
  reduced.addEventListener('change',()=>render(false));document.addEventListener('visibilitychange',()=>{if(document.hidden){cancel();query.textContent=examples[scene].query;finish();}});
  const utilities={awake:{query:'awake',title:'Keep Awake',sub:'Prevent your Mac from sleeping',note:'Your Mac stays awake until you turn it off.',done:'Keep Awake enabled · choose Allow Sleep to stop.'},port:{query:'kill 3000',title:'node',sub:'Example process · Port 3000 · PID 4821',note:'Return quits the process. Shift + Return forces it.',done:'Process stopped · port 3000 is available.'},dark:{query:'dark',title:'Toggle Dark Mode',sub:'Change your Mac’s appearance',note:'A built-in system command. No prompt or model involved.',done:'Dark mode toggled.'}};
  let utility='awake';
  function renderUtility(){const item=utilities[utility];document.querySelectorAll('[data-utility]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.utility===utility)));document.querySelector('#utility-query').textContent=item.query;document.querySelector('#utility-result').innerHTML='<span class="utility-symbol">'+(utility==='port'?'⌁':utility==='dark'?'◐':'☀')+'</span><div><strong>'+item.title+'</strong><small>'+item.sub+'</small></div><kbd>↵</kbd>';document.querySelector('#utility-status').textContent=item.note;document.querySelector('#utility-run').disabled=false;document.querySelector('.utility-desktop').classList.remove('utility-done');}
  document.querySelectorAll('[data-utility]').forEach(b=>b.onclick=()=>{utility=b.dataset.utility;renderUtility();});
  document.querySelector('#utility-run').onclick=()=>{document.querySelector('#utility-status').textContent=utilities[utility].done;document.querySelector('.utility-desktop').classList.add('utility-done');document.querySelector('#utility-run').disabled=true;};
  const output={replace:'Review the result, then replace your selected text with Return.',insert:'Keep the original. Insert the result immediately after it.',copy:'Copy the generated result, ready to paste wherever you need it.',card:'Read the result in the card. Your document stays untouched.'};
  document.querySelector('#output-mode').onchange=event=>document.querySelector('#output-preview').textContent=output[event.target.value];
  render(false);renderUtility();
  addEventListener('pagehide',()=>{cancel();observer.disconnect();motionObserver.disconnect();});
})();
