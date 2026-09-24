// Runtime release-currentness overlay. Current version authority lives only in release-manifest.js.
import{UI_VERSION as VERSION,RELEASE}from'./release-manifest.js'
let pending=false
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function releaseHtml(){return `<article class="m-release-note" data-release-version="${VERSION}"><div class="m-release-note-meta"><span class="m-release-note-version">v${VERSION}</span><span class="m-release-note-date">${RELEASE.date}</span></div><h3>${esc(RELEASE.title)}</h3><ul>${RELEASE.changes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul>${RELEASE.bugFixes?.length?`<div class="m-release-note-fixes"><strong>Bug / UI fixes</strong><ul>${RELEASE.bugFixes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></div>`:''}</article>`}
// P7: fill in releases missing from the legacy dialog list (so older notes never vanish)
// and link to the full, searchable release history page.
let history=null,historyLoading=false
function noteHtml(r){return `<article class="m-release-note" data-release-version="${esc(r.version)}"><div class="m-release-note-meta"><span class="m-release-note-version">v${esc(r.version)}</span><span class="m-release-note-date">${esc(r.date)}</span></div><h3>${esc(r.title)}</h3><ul>${(r.changes||[]).map(x=>`<li>${esc(x)}</li>`).join('')}</ul>${r.bugFixes?.length?`<div class="m-release-note-fixes"><strong>Bug / UI fixes</strong><ul>${r.bugFixes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></div>`:''}</article>`}
function completeHistory(list){
  if(!history){if(!historyLoading){historyLoading=true;fetch('/release-history.json',{cache:'no-store'}).then(r=>r.ok?r.json():null).then(h=>{history=h;schedule()}).catch(()=>{})}return}
  if(!list.querySelector('.m-release-history-link'))list.insertAdjacentHTML('afterbegin',`<p class="m-release-history-link" style="margin:0 0 10px;font-weight:600"><a style="color:#4338ca" href="/release-history.html" target="_blank" rel="noopener">All release notes (${history.count}) →</a></p>`)
  const present=new Set([...list.querySelectorAll('[data-release-version]')].map(e=>e.dataset.releaseVersion))
  const current=list.querySelector(`[data-release-version="${VERSION}"]`)
  const missing=(history.releases||[]).filter(r=>!present.has(r.version))
  if(missing.length&&current)current.insertAdjacentHTML('afterend',missing.map(noteHtml).join(''))
}
function reconcile(){
  document.title=`Coursefinder PIM Admin v${VERSION}`
  document.querySelectorAll('.m-brand-copy small,.m-login-version').forEach(el=>{if(/PIM Admin v2\.15\.\d+/.test(el.textContent||''))el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{const label=el.querySelector('.m-release-version-label');if(label)label.textContent=`v${VERSION}`;else el.textContent=`v${VERSION}`;el.setAttribute('aria-label',`Open release notes for PIM Admin v${VERSION}`)})
  const list=document.querySelector('.m-release-notes-list')
  if(list&&!list.querySelector(`[data-release-version="${VERSION}"]`))list.insertAdjacentHTML('afterbegin',releaseHtml())
  if(list)completeHistory(list)
  document.documentElement.dataset.cfReleaseVersion=VERSION
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},30)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true})
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
