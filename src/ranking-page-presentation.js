const RANKING_LABELS={
 qs_wur:['QS World University Rankings','Accepted QS ranking observations by edition, mapped to canonical Providers with Evidence retained.'],
 the_wur:['Times Higher Education','Accepted THE ranking observations by edition, mapped to canonical Providers with Evidence retained.']
}
const BREADCRUMB_ROUTES={
 '#outcomes-qilt':[
  ['Home','#dashboard'],['Statistics & Rankings','#statistics-rankings'],['Dataset',null],['QILT',null]
 ],
 '#student-flow-prisms':[
  ['Home','#dashboard'],['Statistics & Rankings','#statistics-rankings'],['Dataset',null],['PRISMS',null]
 ],
 '#compare':[
  ['Home','#dashboard'],['Statistics & Rankings','#statistics-rankings'],['Compare',null]
 ]
}
let queued=null
function params(){return new URLSearchParams(location.hash.split('?')[1]||'')}
function routeBase(){return location.hash.split('?')[0]||'#dashboard'}
function ensureStyle(){
 if(document.getElementById('cf-submodule-navigation-style'))return
 const style=document.createElement('style')
 style.id='cf-submodule-navigation-style'
 style.textContent=`html[data-cf-ranking-subpage="1"] .m-page-stack>section.m-panel:not([data-react-ranking-viewer="1"]){display:none!important}`
 document.head.appendChild(style)
}
function setBreadcrumb(items){
 const nav=document.querySelector('.m-breadcrumbs')
 if(!nav)return
 const signature=items.map(x=>x[0]).join('>')
 if(nav.dataset.cfBreadcrumbSignature===signature)return
 nav.replaceChildren()
 items.forEach(([label,href],i)=>{
  const button=document.createElement('button')
  button.type='button';button.textContent=label
  if(href){button.addEventListener('click',()=>{location.hash=href})}else button.disabled=true
  nav.appendChild(button)
  if(i<items.length-1){const sep=document.createElement('span');sep.textContent='/';nav.appendChild(sep)}
 })
 nav.dataset.cfBreadcrumbSignature=signature
}
function restoreRankingHeader(){
 delete document.documentElement.dataset.cfRankingSubpage
 const title=document.querySelector('.m-topbar h1'),subtitle=document.querySelector('.m-topbar h1 + p')
 if(title?.dataset.cfRankingOriginal!==undefined){title.textContent=title.dataset.cfRankingOriginal;delete title.dataset.cfRankingOriginal}
 if(subtitle?.dataset.cfRankingOriginal!==undefined){subtitle.textContent=subtitle.dataset.cfRankingOriginal;delete subtitle.dataset.cfRankingOriginal}
 document.querySelector('[data-cf-ranking-back]')?.remove()
}
function presentRankingDataset(dataset){
 const panel=document.querySelector('[data-react-ranking-viewer="1"]')
 if(!panel)return false
 ensureStyle();document.documentElement.dataset.cfRankingSubpage='1'
 const[label,subtitleText]=RANKING_LABELS[dataset]
 const title=document.querySelector('.m-topbar h1'),subtitle=document.querySelector('.m-topbar h1 + p')
 if(title){if(title.dataset.cfRankingOriginal===undefined)title.dataset.cfRankingOriginal=title.textContent||'Statistics & Rankings';title.textContent=label}
 if(subtitle){if(subtitle.dataset.cfRankingOriginal===undefined)subtitle.dataset.cfRankingOriginal=subtitle.textContent||'';subtitle.textContent=subtitleText}
 setBreadcrumb([['Home','#dashboard'],['Statistics & Rankings','#statistics-rankings'],['Dataset',null],[dataset==='qs_wur'?'QS':'THE',null]])
 if(!panel.querySelector('[data-cf-ranking-back]')){
  const head=panel.querySelector('.m-workspace-head')||panel.firstElementChild
  if(head){const b=document.createElement('button');b.type='button';b.className='m-secondary compact';b.dataset.cfRankingBack='1';b.textContent='Back to Statistics & Rankings';b.addEventListener('click',()=>{location.hash='#statistics-rankings'});head.appendChild(b)}
 }
 return true
}
function present(){
 const base=routeBase(),dataset=base==='#statistics-rankings'?(params().get('dataset')||''):''
 if(RANKING_LABELS[dataset]){presentRankingDataset(dataset);return}
 restoreRankingHeader()
 const mapped=BREADCRUMB_ROUTES[base]
 if(mapped){setBreadcrumb(mapped);return}
 const nav=document.querySelector('.m-breadcrumbs')
 if(nav)delete nav.dataset.cfBreadcrumbSignature
}
function queue(){clearTimeout(queued);queued=setTimeout(present,35)}
if(typeof document!=='undefined'){
 ensureStyle()
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',queue,{once:true});else queue()
 addEventListener('hashchange',queue)
 new MutationObserver(queue).observe(document.documentElement,{childList:true,subtree:true})
}
