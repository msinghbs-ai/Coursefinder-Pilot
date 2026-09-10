const VERSION='2.15.76'
const RELEASE={
  version:VERSION,
  date:'10 Sep 2026',
  title:'Scheduled Tasks configuration and governed run control',
  changes:[
    'Data Operations now includes Scheduled Tasks immediately before Evidence, with operator-friendly schedule configuration, latest refresh queue and recent Job results.',
    'Pipeline Operators can edit exact bounded recurring Layer 1–3 schedules through audited SECURITY INVOKER contracts with optimistic concurrency and durable governance reason/actor evidence.',
    'Run on demand is available only for executable Layer 1–2 schedules and creates or reuses an exact bounded manual_governed refresh request without altering recurring cadence or next-run time.',
    'Layer 3 remains Evidence/profile/model-qualified and is not given a generic autonomous execution path.',
    'Jobs remain read through public.admin_read and historical Jobs are never reset or replayed.'
  ],
  bugFixes:[
    'Preserved PostgreSQL time-only whole-day cadence values when editing schedules.',
    'Corrected datetime-local handling so stored next-run instants are not shifted by the operator timezone.',
    'Surfaced governed Jobs-read failures instead of presenting false empty history.',
    'Completion timestamps remain blank until a Job is terminal.',
    'Added complete paged policy reads, cadence bounds and stale-snapshot rejection for schedule edits.'
  ]
}
let pending=false
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function releaseHtml(){return `<article class="m-release-note" data-release-version="${VERSION}"><div class="m-release-note-meta"><span class="m-release-note-version">v${VERSION}</span><span class="m-release-note-date">${RELEASE.date}</span></div><h3>${esc(RELEASE.title)}</h3><ul>${RELEASE.changes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul>${RELEASE.bugFixes?.length?`<div class="m-release-note-fixes"><strong>Bug / UI fixes</strong><ul>${RELEASE.bugFixes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></div>`:''}</article>`}
function reconcile(){
  document.title=document.title.replace(/v2\.15\.\d+\b/g,`v${VERSION}`)
  document.querySelectorAll('.m-brand-copy small,.m-login-version').forEach(el=>{if(/PIM Admin v2\.15\.\d+/.test(el.textContent||''))el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{const label=el.querySelector('.m-release-version-label');if(label)label.textContent=`v${VERSION}`;else el.textContent=`v${VERSION}`;el.setAttribute('aria-label',`Open release notes for PIM Admin v${VERSION}`)})
  const list=document.querySelector('.m-release-notes-list')
  if(list&&!list.querySelector(`[data-release-version="${VERSION}"]`))list.insertAdjacentHTML('afterbegin',releaseHtml())
  document.documentElement.dataset.cfReleaseVersion=VERSION
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},30)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
