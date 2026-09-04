const VERSION='2.15.58'
const RELEASE={
  version:VERSION,
  date:'4 Sep 2026',
  title:'Scholarship acquisition provenance and fixed Layer operations sequence',
  changes:[
    'Evidence now identifies live acquisition versus downstream artifacts derived from already-retained private Evidence, including acquisition provider, origin Evidence, storage path and shared-fetch reuse context.',
    'Data Operations and Administration keep Layer 1 → Layer 2 → Layer 3 → Layer 4 in a fixed operator sequence so execution controls do not reshuffle after UI re-renders.',
    'Scholarship detail acquisition continues through bounded first-party international waves with Evidence-backed canonical-unpublished reconciliation; no automatic Publication/Search/Website/Zoho admission is introduced.',
    'The second bounded wave added ECU 2027 ASEAN International Scholarship plus two Monash international/ASEAN awards and retained structured percentage/fixed-amount semantics for Course-side calculation.'
  ]
}
let pending=false
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function releaseHtml(){return `<article class="m-release-note" data-release-version="${VERSION}"><div class="m-release-note-meta"><span class="m-release-note-version">v${VERSION}</span><span class="m-release-note-date">${RELEASE.date}</span></div><h3>${esc(RELEASE.title)}</h3><ul>${RELEASE.changes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></article>`}
function reconcile(){
  document.title=document.title.replace(/v2\.15\.57\b/g,`v${VERSION}`)
  document.querySelectorAll('.m-brand-copy small,.m-login-version').forEach(el=>{if(/PIM Admin v2\.15\.\d+/.test(el.textContent||''))el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{el.textContent=`v${VERSION}`;el.setAttribute('aria-label',`Open release notes for PIM Admin v${VERSION}`)})
  const list=document.querySelector('.m-release-notes-list')
  if(list&&!list.querySelector(`[data-release-version="${VERSION}"]`))list.insertAdjacentHTML('afterbegin',releaseHtml())
  document.documentElement.dataset.cfReleaseVersion=VERSION
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},30)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
