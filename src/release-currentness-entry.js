const VERSION='2.15.61'
const RELEASE={
  version:VERSION,
  date:'5 Sep 2026',
  title:'International Scholarship selector — University and Course search',
  changes:[
    'Scholarship Selection now enforces an international-students-only audience boundary in the governed backend selector.',
    'Operators can search and test by University/provider name or by Course title, CRICOS/course code or university name; raw Course UUID entry is no longer required.',
    'University mode shows the current international Scholarship inventory count for direct coverage reconciliation, while Course mode limits unscoped Provider-owned Scholarships to the Course Provider and admits Provider-neutral Scholarships only through an explicit recorded scope.',
    'Scholarship selection remains decision support only: exact Course eligibility and individual student eligibility remain unresolved unless supported by governed scopes/criteria; no Publication, Search, Website or Zoho admission is changed.'
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
