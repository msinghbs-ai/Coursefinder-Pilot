const VERSION='2.15.75'
const RELEASE={
  version:VERSION,
  date:'10 Sep 2026',
  title:'QS ranking duplicate cleanup and 2026/2027 acquisition correction',
  changes:[
    'Administration → Sources & Imports now presents one active QS workflow row per edition while retained source revisions remain auditable.',
    'QS 2024 and 2025 duplicate active editions were lifecycle-retired instead of destructively deleting historical observations or Evidence.',
    'The QS official-static acquisition contract now recognises the governed 2026 and 2027 indicator set, preventing those editions from being rejected solely because the completeness contract stopped at 2025.',
    'RLS remediation discovered during the ranking review is explicitly deferred to pending security task #60 so ranking recovery does not silently change runtime access controls.'
  ],
  bugFixes:[
    'Fixed duplicate QS edition rows in Sources & Imports by returning one active row per ranking system and edition.',
    'Fixed duplicate active QS 2024/2025 lifecycle state: the newest accepted publisher revision remains active and the older revision is Superseded/retired with Evidence preserved.',
    'Fixed the QS 2026/2027 official-static completeness contract so supported direct publisher payloads can qualify without being forced into Parse.bot fallback.',
    'Accepted ranking editions now validate with no duplicate institution observations after lifecycle cleanup.',
    'Recorded RLS hardening as pending security task #60 rather than applying incomplete policies during this bug-fix release.'
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
