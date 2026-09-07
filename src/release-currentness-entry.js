const VERSION='2.15.73'
const RELEASE={
  version:VERSION,
  date:'7 Sep 2026',
  title:'Fluid catalogues, ranking datasets and Provider comparison',
  changes:[
    'Scholarship Catalogue now includes a bounded Provider filter and fluid columns while server authority continues to own filtering, paging and meaningful ordering.',
    'QILT and PRISMS datasets use governed server-backed sorting with fluid tables; QS and THE provide Open Dataset and Compare with edition-aware, server-backed ordering.',
    'Provider Compare enables QS and THE by default when accepted data exists, defaults each system to its latest retained edition and shows historical editions independently beneath the current observation.',
    'Provider identity stays visible while wide comparison data scrolls, and the accepted UI passed targeted source/build/browser gates, bounded 1600/1366/900/390 viewport validation and deployed Pilot UAT.',
    'The Scholarship provider_id and ranking sort/direction read-contract reconciliation preserves role/rank, Provider equivalence, Evidence and publication semantics. Production is unchanged; superseded v2.15.72 remains forensic history only.'
  ]
}
let pending=false
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function releaseHtml(){return `<article class="m-release-note" data-release-version="${VERSION}"><div class="m-release-note-meta"><span class="m-release-note-version">v${VERSION}</span><span class="m-release-note-date">${RELEASE.date}</span></div><h3>${esc(RELEASE.title)}</h3><ul>${RELEASE.changes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></article>`}
function reconcile(){
  document.title=document.title.replace(/v2\.15\.\d+\b/g,`v${VERSION}`)
  document.querySelectorAll('.m-brand-copy small,.m-login-version').forEach(el=>{if(/PIM Admin v2\.15\.\d+/.test(el.textContent||''))el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{el.textContent=`v${VERSION}`;el.setAttribute('aria-label',`Open release notes for PIM Admin v${VERSION}`)})
  const list=document.querySelector('.m-release-notes-list')
  if(list&&!list.querySelector(`[data-release-version="${VERSION}"]`))list.insertAdjacentHTML('afterbegin',releaseHtml())
  document.documentElement.dataset.cfReleaseVersion=VERSION
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},30)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
