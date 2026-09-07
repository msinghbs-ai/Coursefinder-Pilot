const LABELS={qs_wur:['QS World University Rankings','Accepted QS ranking observations by edition, mapped to canonical Providers with Evidence retained.'],the_wur:['Times Higher Education','Accepted THE ranking observations by edition, mapped to canonical Providers with Evidence retained.']}
let queued=null
function params(){return new URLSearchParams(location.hash.split('?')[1]||'')}
function restore(){
 document.querySelectorAll('[data-cf-ranking-page-hidden="1"]').forEach(el=>{if(el.hidden)el.hidden=false;delete el.dataset.cfRankingPageHidden})
 const title=document.querySelector('.m-topbar h1'),subtitle=document.querySelector('.m-topbar h1 + p')
 if(title?.dataset.cfRankingOriginal){const original=title.dataset.cfRankingOriginal;if(title.textContent!==original)title.textContent=original;delete title.dataset.cfRankingOriginal}
 if(subtitle?.dataset.cfRankingOriginal!==undefined){const original=subtitle.dataset.cfRankingOriginal;if(subtitle.textContent!==original)subtitle.textContent=original;delete subtitle.dataset.cfRankingOriginal}
 document.querySelector('[data-cf-ranking-back]')?.remove()
 const crumb=[...document.querySelectorAll('.m-breadcrumbs button')].at(-1)
 if(crumb?.dataset.cfRankingOriginal){const original=crumb.dataset.cfRankingOriginal;if(crumb.textContent!==original)crumb.textContent=original;delete crumb.dataset.cfRankingOriginal}
}
function present(){
 if(!location.hash.startsWith('#statistics-rankings')){restore();return}
 const dataset=params().get('dataset')||''
 if(!LABELS[dataset]){restore();return}
 const panel=document.querySelector('[data-react-ranking-viewer="1"]'),stack=panel?.closest('.m-page-stack')
 if(!panel||!stack)return
 const [label,subtitleText]=LABELS[dataset]
 ;[...stack.children].forEach(el=>{if(el!==panel){if(el.dataset.cfRankingPageHidden!=='1')el.dataset.cfRankingPageHidden='1';if(!el.hidden)el.hidden=true}})
 const title=document.querySelector('.m-topbar h1'),subtitle=document.querySelector('.m-topbar h1 + p')
 if(title){if(!title.dataset.cfRankingOriginal)title.dataset.cfRankingOriginal=title.textContent||'Statistics & Rankings';if(title.textContent!==label)title.textContent=label}
 if(subtitle){if(subtitle.dataset.cfRankingOriginal===undefined)subtitle.dataset.cfRankingOriginal=subtitle.textContent||'';if(subtitle.textContent!==subtitleText)subtitle.textContent=subtitleText}
 const crumb=[...document.querySelectorAll('.m-breadcrumbs button')].at(-1)
 if(crumb){if(!crumb.dataset.cfRankingOriginal)crumb.dataset.cfRankingOriginal=crumb.textContent||'Statistics & Rankings';if(crumb.textContent!==label)crumb.textContent=label}
 if(!panel.querySelector('[data-cf-ranking-back]')){
  const head=panel.querySelector('.m-workspace-head')||panel.firstElementChild
  if(head){const b=document.createElement('button');b.type='button';b.className='m-secondary compact';b.dataset.cfRankingBack='1';b.textContent='Back to Statistics & Rankings';b.addEventListener('click',()=>{location.hash='#statistics-rankings'});head.appendChild(b)}
 }
}
function queue(){clearTimeout(queued);queued=setTimeout(present,60)}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',queue,{once:true});else queue()
 addEventListener('hashchange',queue)
 new MutationObserver(queue).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']})
}
