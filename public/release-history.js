// CF-247 s810: the release notes page's script, in its own file because the Content-Security-Policy allows scripts from the app only (no inline script).
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
fetch('release-history.json',{cache:'no-store'}).then(r=>r.json()).then(h=>{
  document.getElementById('sub').textContent=`${h.count} releases, newest first. Current: v${h.current}.`
  const render=q=>{const t=q.trim().toLowerCase();const rows=h.releases.filter(r=>!t||JSON.stringify(r).toLowerCase().includes(t))
    document.getElementById('list').innerHTML=rows.length?rows.map(r=>`<article><div class="meta"><span class="v">v${esc(r.version)}</span>${r.version===h.current?'<span class="cur">Current</span>':''}<span>${esc(r.date)}</span></div><h2>${esc(r.title)}</h2>${r.changes.length?`<ul>${r.changes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul>`:''}${r.bugFixes.length?`<div class="fixes"><strong>Bug / UI fixes</strong><ul>${r.bugFixes.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></div>`:''}</article>`).join(''):'<p>No release notes match.</p>'}
  render('');document.getElementById('q').addEventListener('input',e=>render(e.target.value))
}).catch(()=>{document.getElementById('list').textContent='Release notes could not be loaded.'})
