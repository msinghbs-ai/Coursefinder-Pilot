const VERSION='2.15.65'
const RELEASE={
  version:VERSION,
  date:'5 Sep 2026',
  title:'Layer 4 mass operations and quality cross-check',
  changes:[
    'Layer 4 Human Resolution now groups repeatable Scholarship Course-scope and generic review work into governed cohorts so operators do not need to process thousands of rows one by one.',
    'Scholarship cohorts show Evidence coverage, Provider mismatch, existing mappings, study-level spread, semantic-scope warnings and a bounded course sample before any mass decision.',
    'Mass accept/reject requires an audited reason plus an exact count confirmation; structural blockers prevent cohort acceptance and every mass operation is retained in an audit ledger.',
    'Generic Layer 4 cohorts can be rejected or returned to Layer 2/3 in bounded batches; bulk scalar approval remains intentionally unavailable where proposed values may differ.',
    'Layer 4 now includes cross-check diagnostics and a tracked Errors / Issues / Improvements register for structural integrity, stale review work and workflow-improvement opportunities.',
    'Publication remains separate and unchanged, and CF-102 Provider logo display, signed access and cache behaviour are retained.'
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
