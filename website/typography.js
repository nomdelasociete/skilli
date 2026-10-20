(() => {
  const params = new URLSearchParams(location.search);
  if (!params.has('type')) return;
  const options = [
    ['original','Original','The current system typeface.'],
    ['outfit','Outfit','Rounded forms. A clear, confident voice.'],
    ['sora','Sora','Graphic details. Crisp and deliberate.'],
    ['inclusive','Inclusive Sans','Open shapes. A warmer, more human voice.'],
    ['satoshi','Satoshi','Balanced proportions. Quietly distinctive.'],
    ['creato','Creato Display','Clean curves. A more sculpted silhouette.'],
    ['abeezee','ABeeZee','Soft, open letterforms.'],
    ['trueno','Trueno','Broad proportions. Geometric and grounded.'],
    ['geist','Geist Pixel','Five pixel constructions. One baseline.']
  ];
  const hero=document.querySelector('.opening');
  const panel=document.createElement('div');panel.className='type-comparison';
  const group=document.createElement('div');group.className='type-options';group.setAttribute('role','group');group.setAttribute('aria-label','Compare baseline typefaces');
  const note=document.createElement('p');note.className='type-description';note.setAttribute('aria-live','polite');
  const cuts=['Square','Circle','Grid','Triangle','Line'];
  const variant=document.createElement('select');variant.className='type-variant';variant.setAttribute('aria-label','Geist Pixel variant');
  for(const cut of cuts){const option=document.createElement('option');option.value=cut.toLowerCase();option.textContent=cut;variant.append(option);}
  variant.value=cuts.some(cut=>cut.toLowerCase()===params.get('cut'))?params.get('cut'):'square';
  function setCut(){hero.dataset.pixel=variant.value;const url=new URL(location.href);if(hero.dataset.type==='geist')url.searchParams.set('cut',variant.value);else url.searchParams.delete('cut');history.replaceState(null,'',url);}
  variant.onchange=setCut;
  function choose(id){const selected=options.find(item=>item[0]===id)||options[1];hero.dataset.type=selected[0];note.textContent=selected[2];group.querySelectorAll('button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.type===selected[0])));const url=new URL(location.href);url.searchParams.set('type',selected[0]);history.replaceState(null,'',url);variant.hidden=selected[0]!=='geist';setCut();}
  for(const [id,label] of options){const button=document.createElement('button');button.textContent=label;button.dataset.type=id;button.onclick=()=>{choose(id);scrollTo({top:0,behavior:'instant'});};group.append(button);}
  panel.append(group,variant,note);hero.append(panel);choose(params.get('type'));
})();
