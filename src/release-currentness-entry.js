const VERSION='2.15.59'
const RELEASE={
  version:VERSION,
  date:'4 Sep 2026',
  title:'QILT 2023 comparison reconciliation',
  changes:[
    'Provider comparison now retains QILT Student Experience Survey cohort grain when study_level_id is absent: UG is shown as Undergraduate and PGC as Postgraduate coursework instead of collapsing both into All study levels.',
    'Official QILT 2023 SES comparison observations for Monash University, RMIT University and La Trobe University are retained for the meeting proof alongside existing 2024 observations, with published confidence bounds and national benchmarks at the matching cohort/metric grain.',
    'The governed comparison read strips absent statistical fields before browser delivery, preventing missing 2024 confidence-high or national-benchmark values from being rendered as false 0.0% statistics.',
    'QILT remains contextual statistical intelligence only; no Provider/Course identity, Scholarship, Search, Publication, Website or Zoho authority changed.'
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
