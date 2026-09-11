const VERSION='2.15.77'
const RELEASE={
  version:VERSION,
  date:'11 Sep 2026',
  title:'Scheduled Tasks operator catalogue and workflow control',
  changes:[
    'Scheduled Tasks now presents human-readable task, dataset and target labels while retaining source, profile and entity IDs as secondary technical detail.',
    'Operators can search scheduled work across dataset, country, target, creator, owner and technical identifiers before pagination.',
    'Created By and Owner attribution remains intelligible when an account is removed or disabled, while system and legacy schedules remain explicitly non-human.',
    'Personal column visibility and ordering are retained per operator without changing governed execution policy.',
    'Run on demand remains bounded to executable Layer 1–2 policies; Layer 3 continues through its Evidence/profile/model-qualified control path.'
  ],
  bugFixes:[
    'Prevented stale debounced scheduler responses and supporting-panel refreshes from overwriting newer operator state.',
    'Made refresh-queue targets distinguishable and preserved source-profile identity when a policy also carries a source ID.',
    'Search now treats percent and underscore as literal text and matches both raw and humanised dataset labels.',
    'Resolved Provider, Course, Campus and Scholarship entity targets to governed business labels where available.',
    'Surfaced independent queue, context and Jobs read failures instead of presenting false empty operational state.'
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
