const LAYER2_LABEL='Layer 2 — Enrichment'
const LAYER2_HASH='#layer-2-enrichment'

function makeAdminShortcut(){
  const tabs=document.querySelector('.m-admin-subnav')
  if(!tabs||tabs.querySelector('[data-cf-layer2-shortcut="true"]'))return
  const button=document.createElement('button')
  button.type='button'
  button.dataset.cfLayer2Shortcut='true'
  button.title='Operational Layer 2 enrichment and Scholarship acquisition'
  button.innerHTML='<span aria-hidden="true" style="font-size:12px;font-weight:800;min-width:15px;text-align:center">L2</span><span>'+LAYER2_LABEL+'</span>'
  button.addEventListener('click',()=>{location.hash=LAYER2_HASH})
  tabs.appendChild(button)
}

function ensureSidebarEntry(){
  const groups=[...document.querySelectorAll('.m-nav-group')]
  const group=groups.find(x=>x.querySelector('.m-nav-label')?.textContent?.trim()==='Data Operations')
  if(!group)return
  const existing=[...group.querySelectorAll('.m-nav-item')].find(x=>x.textContent?.includes(LAYER2_LABEL))
  if(existing)return
  const button=document.createElement('button')
  button.type='button'
  button.className='m-nav-item'
  button.title=LAYER2_LABEL
  button.dataset.cfLayer2NavRestore='true'
  button.innerHTML='<span aria-hidden="true" style="display:inline-grid;place-items:center;width:17px;height:17px;font-size:10px;font-weight:800">L2</span><span>'+LAYER2_LABEL+'</span>'
  button.addEventListener('click',()=>{location.hash=LAYER2_HASH})
  const layer1=[...group.querySelectorAll('.m-nav-item')].find(x=>x.textContent?.includes('Layer 1 — Operations'))
  if(layer1?.nextSibling)group.insertBefore(button,layer1.nextSibling);else group.appendChild(button)
}

function reconcile(){
  makeAdminShortcut()
  ensureSidebarEntry()
}

const observer=new MutationObserver(reconcile)
observer.observe(document.documentElement,{childList:true,subtree:true})
window.addEventListener('hashchange',()=>requestAnimationFrame(reconcile))
requestAnimationFrame(reconcile)
