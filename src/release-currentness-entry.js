const VERSION='2.15.71'
const RELEASE={
  version:VERSION,
  date:'6 Sep 2026',
  title:'Ranking dataset visibility and deployment currentness recovery',
  changes:[
    'Synchronised the visible PIM Admin release badge, login/version labels, browser title and release metadata to v2.15.71 so the deployed UI no longer reports the superseded v2.15.66 release after a successful Cloudflare deployment.',
    'Statistics & Rankings now exposes imported QS and THE dataset editions and the accepted-observation viewer, including search, pagination, Provider mapping, rank, score, country and Evidence references.',
    'Ranking workflow history identifies governed Layer 1 Ranking ETL activity while accepted publisher observations remain separate from canonical Provider identity and mapping exceptions stay traceable.',
    'Cloudflare deployment remains the native repository-connected build path; GitHub Actions retains the exact dist artifact and browser-smoke evidence without introducing a second automatic Worker deployment path.',
    'No regulatory source authority, Provider/Course identity, Publication/Search admission or Website/Zoho contract is changed by this release-currentness correction.'
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
