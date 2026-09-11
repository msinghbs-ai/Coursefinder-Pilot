const VERSION='2.15.78'
const RELEASE={
  version:VERSION,
  date:'11 Sep 2026',
  title:'Governed Scheduled Tasks target builder',
  changes:[
    'Scheduled Tasks adds a server-authorised target builder for AU Course Facts enrichment with Country, State/Territory and University/Provider scopes.',
    'Every consequential run requires a same-actor server preview receipt bound to the exact workflow, target and acquisition-only processing mode before dispatch.',
    'Layer 2 dispatch now fails closed unless scoped profiles have valid current versions, governed execution policies and remain within the supported per-profile scope limit.',
    'Exact-scope dispatch is serialised and deduplicated across operators while preview-token ownership remains actor-bound.',
    'Jobs and Evidence remain the authoritative follow-through for underlying work; automatic generic Layer 3/Layer 4 orchestration, Evidence reprocessing and recurring scope construction remain unavailable.'
  ],
  bugFixes:[
    'Prevented stale scope, university search and preview responses from authorising a different target or leaving the builder busy.',
    'Retired the bypassable v1 target-builder run path and enforced preview-before-dispatch on the server.',
    'Rejected country scopes carrying arbitrary target IDs and revalidated live runnable scope immediately before dispatch.',
    'Measured duplicate suppression from actual dispatch time and rejected empty or unqualified starts atomically.',
    'Preserved Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human resolution and separate Search/Publication admission boundaries.'
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
