const classify=(text='')=>{const t=text.toLowerCase();if(t.includes('rmit'))return'Australia · Courses · RMIT University';if(t.includes('queensland')||t.includes('uq'))return'Australia · Courses · The University of Queensland';if(t.includes('study australia')&&t.includes('scholar'))return'Australia · Scholarships · Study Australia';return text};
function apply(){
  document.querySelectorAll('select[aria-label="Layer 2 provider source profile"]').forEach(sel=>{
    sel.setAttribute('aria-label','Layer 2 enrichment source');
    const label=sel.closest('label');if(label&&label.firstChild?.nodeType===Node.TEXT_NODE)label.firstChild.textContent='Enrichment source';
    [...sel.options].forEach(o=>{o.textContent=classify(o.textContent)});
  });
  document.querySelectorAll('.l2t-controls label').forEach(label=>{
    if((label.textContent||'').trim().startsWith('Source profile')){
      const sel=label.querySelector('select');if(sel){label.childNodes.forEach(n=>{if(n.nodeType===Node.TEXT_NODE&&n.textContent.includes('Source profile'))n.textContent=n.textContent.replace('Source profile','Enrichment source')});[...sel.options].forEach(o=>o.textContent=classify(o.textContent));}
    }
  });
  document.querySelectorAll('.l2p-source-summary').forEach(el=>{const s=el.querySelector('span');if(s&&s.textContent.includes('Course Detail'))s.textContent=s.textContent.replace('Course Detail','Course enrichment');if(s&&s.textContent.includes('Course Catalogue'))s.textContent=s.textContent.replace('Course Catalogue','Course enrichment');if(s&&s.textContent.includes('Search Endpoint'))s.textContent=s.textContent.replace('Search Endpoint','Scholarship enrichment')});
}
let queued=false;const schedule=()=>{if(queued)return;queued=true;queueMicrotask(()=>{queued=false;apply()})};new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});apply();
