// CF-233 — bounded Compare recovery for QILT category/year alignment.
// The base Compare workspace exposes a global QILT year selector. When the
// newest global QILT year belongs to a different category, the default
// Current student experience tab can otherwise render an empty comparison.
// This recovery only advances to the next retained year when the active QILT
// comparison has selected entities, is currently empty, and the selected year
// is the first (global newest) option. It never invents statistics or mutates
// canonical data.

let pending=false
let lastSignature=''

function schedule(){
  if(pending)return
  pending=true
  setTimeout(()=>{pending=false;reconcile()},60)
}

function reconcile(){
  if(!location.hash.startsWith('#compare'))return
  const shell=document.querySelector('.cf-compare-shell')
  const empty=shell?.querySelector('.cf-compare-no-rows')
  const entities=shell?.querySelectorAll('.cf-compare-entity')?.length||0
  if(!shell||!empty||entities<1)return

  const config=document.querySelector('.cf-compare-config')
  const yearSelect=[...(config?.querySelectorAll('select')||[])].find(x=>/QILT year/i.test(x.closest('label')?.textContent||''))
  if(!yearSelect||yearSelect.options.length<2)return

  const activeTab=shell.querySelector('.cf-compare-tabs button.active')?.textContent?.trim()||''
  const selected=yearSelect.value
  const first=yearSelect.options[0]?.value||''
  const signature=[location.hash,activeTab,selected,entities].join('|')
  if(signature===lastSignature)return
  lastSignature=signature

  // Only repair the initial/global-newest mismatch. An operator who later
  // deliberately chooses an empty historical year keeps that explicit choice.
  if(selected!==first)return
  const next=yearSelect.options[1]?.value
  if(!next||next===selected)return
  yearSelect.value=next
  yearSelect.dispatchEvent(new Event('change',{bubbles:true}))
}

new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['class']})
addEventListener('hashchange',()=>{lastSignature='';schedule()})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
