const VERSION='2.15.63'
const RELEASE={
  version:VERSION,
  date:'5 Sep 2026',
  title:'International Scholarship runtime and queue hardening',
  changes:[
    'Scholarship Operations now supports governed Country and University acquisition, international-only detail qualification, Evidence-backed canonical-unpublished reconciliation, provider/course cross-reference and live UAT/statistics.',
    'The automatic detail queue now contains only active discovered candidates. Acquired, superseded, catalogue/filter, support/navigation and external records cannot silently re-enter firing.',
    'Existing first-party source records, Evidence and canonical unpublished Scholarships are reused instead of re-scraped; duplicate Provider/detail URL observations are retained for audit but removed from executable work.',
    'Runtime statistics now distinguish active detail-ready/review work from historical classification state. The AU active detail-ready queue is currently zero after reconciliation while canonical Scholarships remain unpublished.',
    'CF-102 Provider logo display and private cached signed-logo access remain unchanged and protected by their permanent regression gate.'
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
