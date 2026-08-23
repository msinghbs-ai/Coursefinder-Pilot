const VERSION='1.1.0'

const ICONS={
  pipeline:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="8" height="8" x="3" y="3" rx="2"/><rect width="8" height="8" x="13" y="13" rx="2"/><path d="M11 7h2a4 4 0 0 1 4 4v2M13 17h-2a4 4 0 0 1-4-4v-2"/></svg>',
  source:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5"/><path d="M3 12c0 1.7 4 3 9 3s9-1.3 9-3"/></svg>',
  config:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.72l.15-.1a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>',
  provider:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="8.5" y="14" width="7" height="7" rx="1"/><path d="M6.5 10v2h11v-2M12 12v2"/></svg>',
  trial:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 3h6M10 3v5l-5 9a3 3 0 0 0 2.6 4.5h8.8A3 3 0 0 0 19 17l-5-9V3"/><path d="M8.5 14h7"/></svg>',
  jobs:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg>',
  evidence:'<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>'
}

function text(el){return (el?.textContent||'').trim()}
function groups(){return [...document.querySelectorAll('.m-nav-group')]}
function group(name){return groups().find(g=>text(g.querySelector('.m-nav-label'))===name)}
function button(label){return [...document.querySelectorAll('.m-nav-item')].find(b=>text(b.querySelector('span'))===label)}
function hide(el){if(el)el.style.display='none'}
function renameGroup(from,to){const g=group(from);if(g){const l=g.querySelector('.m-nav-label');if(l)l.textContent=to}return g}
function custom(label,icon,run){const b=document.createElement('button');b.className='m-nav-item acquisition-nav-item';b.type='button';b.title=label;b.innerHTML=`${icon}<span>${label}</span>`;b.addEventListener('click',()=>{document.querySelectorAll('.acquisition-nav-item').forEach(x=>x.classList.remove('active'));b.classList.add('active');run()});return b}
function click(sel){const el=document.querySelector(sel);if(el)el.click()}

function install(){
  const nav=document.querySelector('.m-nav');if(!nav||document.querySelector('[data-acquisition-nav="1"]'))return
  const catalogue=group('Catalogue'),quality=group('Data Quality'),operations=group('Operations')
  if(!catalogue||!quality||!operations)return

  const evidence=button('Evidence'),jobs=button('Jobs'),sources=button('Sources')
  hide(evidence);hide(jobs);hide(sources)
  renameGroup('Data Quality','Quality & Review')
  renameGroup('Operations','Governance & Platform')

  const g=document.createElement('div');g.className='m-nav-group';g.dataset.acquisitionNav='1'
  const label=document.createElement('div');label.className='m-nav-label';label.textContent='Data Acquisition';g.appendChild(label)
  g.appendChild(custom('Pipeline Control',ICONS.pipeline,()=>click('.ops-launcher')))
  if(sources)g.appendChild(custom('Source Registry',ICONS.source,()=>sources.click()))
  g.appendChild(custom('Layer 2 Source Config',ICONS.config,()=>click('.l2-launcher')))
  g.appendChild(custom('Acquisition Providers',ICONS.provider,()=>click('.l2p-launcher')))
  g.appendChild(custom('Acquisition Trials',ICONS.trial,()=>click('.l2t-launcher')))
  if(jobs)g.appendChild(custom('Jobs',ICONS.jobs,()=>jobs.click()))
  if(evidence)g.appendChild(custom('Evidence',ICONS.evidence,()=>evidence.click()))
  catalogue.insertAdjacentElement('afterend',g)

  const style=document.createElement('style');style.dataset.acquisitionNavStyle='1';style.textContent='.ops-launcher,.l2-launcher,.l2p-launcher,.l2t-launcher{display:none!important}.acquisition-nav-item.active{background:linear-gradient(90deg,#283650,#243147);color:#fff;box-shadow:inset 3px 0 0 #7c83ff}.m-shell.is-collapsed .acquisition-nav-item span{display:none}'
  document.head.appendChild(style)
  document.documentElement.dataset.acquisitionNavVersion=VERSION
}

let pending=false
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;install()},50)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true})
addEventListener('DOMContentLoaded',schedule)
schedule()
