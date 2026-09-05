const VERSION='2.15.66'
const RELEASE={
  version:VERSION,
  date:'5 Sep 2026',
  title:'Reusable Layer 4 Scholarship scope rules',
  changes:[
    'Layer 4 can now convert a reviewed Scholarship Course-scope cohort into one reusable accept/reject rule instead of recreating the same row-level review after every refresh.',
    'Reusable rules are bound to the exact Scholarship, candidate reason, Provider and first-party Evidence ID; any changed Evidence version deliberately falls back to Layer 4 review.',
    'Future matching Course-scope candidates are resolved automatically through the retained rule, with Evidence, actor, mapping basis and rule-use counters preserved for audit.',
    'Operators can inspect, apply, enable or disable retained rules from Layer 4; rule creation requires Pipeline Operator authority, audited reason and exact SAVE RULE N confirmation.',
    'No rule can bypass Provider mismatch or missing Evidence controls, and Publication/Search admission remains separate.',
    'CF-102 Provider logo display, private signed access and cache behaviour remain unchanged.'
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
