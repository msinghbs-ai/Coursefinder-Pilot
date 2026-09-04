const LAYERS=[
 {label:'Layer 1 — Operations',short:'L1',hash:'#layer-1-operations'},
 {label:'Layer 2 — Enrichment',short:'L2',hash:'#layer-2-enrichment'},
 {label:'Layer 3 — AI Interpretation',short:'L3',hash:'#layer-3-ai-interpretation'},
 {label:'Layer 4 — Human Resolution',short:'L4',hash:'#layer-4-human-resolution'},
]
const ADMIN_ANCHOR_LABEL='Overview'

function makeButton(layer,kind){
 const b=document.createElement('button');b.type='button';b.dataset.cfLayerSequence=layer.short;b.title=`${layer.label} — governed execution workspace`;b.innerHTML=`<span aria-hidden="true" style="font-size:11px;font-weight:800;min-width:18px;text-align:center">${layer.short}</span><span>${layer.label}</span>`;b.addEventListener('click',()=>{location.hash=layer.hash});if(kind==='sidebar')b.className='m-nav-item';return b
}
function text(el){return(el?.textContent||'').replace(/\s+/g,' ').trim()}
function matchingButton(host,label){return[...host.querySelectorAll('button')].find(x=>text(x).includes(label))}

function ensureAdminSequence(){
 const tabs=document.querySelector('.m-admin-subnav');if(!tabs)return
 let anchor=matchingButton(tabs,ADMIN_ANCHOR_LABEL)
 let cursor=anchor
 for(const layer of LAYERS){
   let b=matchingButton(tabs,layer.label)||tabs.querySelector(`[data-cf-layer-sequence="${layer.short}"]`)
   if(!b){b=makeButton(layer,'admin')}
   b.dataset.cfLayerSequence=layer.short
   if(cursor){if(cursor.nextSibling!==b)tabs.insertBefore(b,cursor.nextSibling);cursor=b}else{tabs.insertBefore(b,tabs.firstChild);cursor=b}
 }
 tabs.dataset.cfLayerOrder='L1>L2>L3>L4'
}

function ensureSidebarSequence(){
 const groups=[...document.querySelectorAll('.m-nav-group')]
 const group=groups.find(x=>text(x.querySelector('.m-nav-label'))==='Data Operations');if(!group)return
 let cursor=null
 for(const layer of LAYERS){
   let b=matchingButton(group,layer.label)||group.querySelector(`[data-cf-layer-sequence="${layer.short}"]`)
   if(!b)b=makeButton(layer,'sidebar')
   b.dataset.cfLayerSequence=layer.short
   if(!cursor){const first=group.querySelector('.m-nav-item');if(first!==b)group.insertBefore(b,first);cursor=b}
   else{if(cursor.nextSibling!==b)group.insertBefore(b,cursor.nextSibling);cursor=b}
 }
 group.dataset.cfLayerOrder='L1>L2>L3>L4'
}

function reconcile(){ensureAdminSequence();ensureSidebarSequence()}
let pending=false
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},50)}
const observer=new MutationObserver(schedule);observer.observe(document.documentElement,{childList:true,subtree:true})
window.addEventListener('hashchange',()=>requestAnimationFrame(reconcile));requestAnimationFrame(reconcile)
