const DATASET_META={
  qs_wur:{title:'QS World University Rankings',subtitle:'Accepted QS ranking observations by edition, mapped to canonical Providers with Evidence retained.'},
  the_wur:{title:'Times Higher Education',subtitle:'Accepted THE ranking observations by edition, mapped to canonical Providers with Evidence retained.'}
}
let queued=null
function currentDataset(){
  if(!location.hash.startsWith('#statistics-rankings'))return''
  return new URLSearchParams(location.hash.split('?')[1]||'').get('dataset')||''
}
function apply(){
  const dataset=currentDataset(),meta=DATASET_META[dataset]
  const title=document.querySelector('.m-topbar h1'),subtitle=document.querySelector('.m-topbar h1 + p')
  if(!title||!subtitle)return
  if(meta){
    if(title.dataset.cfDatasetOriginal===undefined)title.dataset.cfDatasetOriginal=title.textContent||'Statistics & Rankings'
    if(subtitle.dataset.cfDatasetOriginal===undefined)subtitle.dataset.cfDatasetOriginal=subtitle.textContent||''
    if(title.textContent!==meta.title)title.textContent=meta.title
    if(subtitle.textContent!==meta.subtitle)subtitle.textContent=meta.subtitle
    return
  }
  if(title.dataset.cfDatasetOriginal!==undefined){title.textContent=title.dataset.cfDatasetOriginal;delete title.dataset.cfDatasetOriginal}
  if(subtitle.dataset.cfDatasetOriginal!==undefined){subtitle.textContent=subtitle.dataset.cfDatasetOriginal;delete subtitle.dataset.cfDatasetOriginal}
}
function queue(){clearTimeout(queued);queued=setTimeout(apply,20)}
if(typeof document!=='undefined'){
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',queue,{once:true});else queue()
  addEventListener('hashchange',queue)
  new MutationObserver(queue).observe(document.documentElement,{childList:true,subtree:true})
}
