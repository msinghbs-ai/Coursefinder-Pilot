const VERSION='2.15.4'

// Browser-facing release history. Keep newest first and add an entry whenever the visible
// PIM Admin version changes so operators can see exactly what changed between releases.
const RELEASES=[
  {
    version:'2.15.4',
    date:'26 Aug 2026',
    title:'Release notes in the Admin UI',
    changes:[
      'The top-right version number is now interactive and opens governed release notes.',
      'Release history shows the version, release date and operator-facing changes introduced.',
      'Release notes can be closed with the close button, backdrop click or Escape key.',
    ],
  },
  {
    version:'2.15.3',
    date:'26 Aug 2026',
    title:'Course detail decision-workspace polish',
    changes:[
      'Standardised Course detail sections for fees, entry requirements, locations and operational state.',
      'Kept required enrichment gaps visible while suppressing empty non-required sections.',
      'Added operator-controlled Course detail section ordering with persisted screen preference.',
    ],
  },
  {
    version:'2.15.2',
    date:'26 Aug 2026',
    title:'M2.3 governed decision UX hardening',
    changes:[
      'Continued M2.3 browser hardening without changing Layer 1 identity or publication authority.',
      'Preserved governed Evidence and Data Quality operational context across the Admin workspace.',
    ],
  },
]

let attempts=0
let releaseUiMounted=false

function releaseButton(el){
  el.setAttribute('role','button')
  el.setAttribute('tabindex','0')
  el.setAttribute('aria-haspopup','dialog')
  el.setAttribute('aria-label',`Open release notes for PIM Admin v${VERSION}`)
  el.title='View release notes'
  if(el.dataset.releaseNotesBound==='true')return
  el.dataset.releaseNotesBound='true'
  el.addEventListener('click',openReleaseNotes)
  el.addEventListener('keydown',event=>{
    if(event.key==='Enter'||event.key===' '){event.preventDefault();openReleaseNotes()}
  })
}

function ensureReleaseUi(){
  if(releaseUiMounted)return
  releaseUiMounted=true
  const style=document.createElement('style')
  style.id='pim-release-notes-style'
  style.textContent=`
    .m-release-pill[role="button"]{cursor:pointer;user-select:none;transition:box-shadow .15s ease,transform .15s ease}
    .m-release-pill[role="button"]:hover{box-shadow:0 0 0 3px rgba(82,100,234,.12)}
    .m-release-pill[role="button"]:focus-visible{outline:2px solid #5264ea;outline-offset:2px}
    .m-release-notes-backdrop{position:fixed;inset:0;z-index:50000;background:rgba(15,23,42,.52);display:none;align-items:flex-start;justify-content:flex-end;padding:72px 28px 28px;backdrop-filter:blur(3px)}
    .m-release-notes-backdrop.is-open{display:flex}
    .m-release-notes-dialog{width:min(540px,100%);max-height:calc(100vh - 100px);overflow:auto;background:#fff;border:1px solid #e4e9f1;border-radius:16px;box-shadow:0 24px 70px rgba(15,23,42,.28);color:#162033}
    .m-release-notes-head{position:sticky;top:0;background:#fff;display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding:20px 22px 16px;border-bottom:1px solid #eef1f5;z-index:1}
    .m-release-notes-head small{display:block;color:#7c8aa0;font-size:10px;font-weight:800;letter-spacing:.09em;text-transform:uppercase}
    .m-release-notes-head h2{margin:4px 0 0;font-size:21px;letter-spacing:-.03em}
    .m-release-notes-close{border:1px solid #dfe5ee;background:#fff;border-radius:8px;width:34px;height:34px;cursor:pointer;font-size:20px;line-height:1;color:#526073}
    .m-release-notes-list{padding:4px 22px 22px}
    .m-release-note{padding:18px 0;border-bottom:1px solid #eef1f5}
    .m-release-note:last-child{border-bottom:0}
    .m-release-note-meta{display:flex;align-items:center;gap:9px;flex-wrap:wrap}
    .m-release-note-version{display:inline-flex;padding:4px 8px;border-radius:999px;background:#eef0ff;color:#4454d9;font-size:11px;font-weight:800}
    .m-release-note-date{font-size:11px;color:#8a96a8}
    .m-release-note h3{margin:9px 0 7px;font-size:14px}
    .m-release-note ul{margin:0;padding-left:18px;color:#526073}
    .m-release-note li{font-size:12px;line-height:1.55;margin:5px 0}
    @media(max-width:760px){.m-release-notes-backdrop{padding:64px 12px 12px}.m-release-notes-dialog{max-height:calc(100vh - 76px)}}
  `
  document.head.appendChild(style)

  const backdrop=document.createElement('div')
  backdrop.className='m-release-notes-backdrop'
  backdrop.id='pim-release-notes'
  backdrop.innerHTML=`<section class="m-release-notes-dialog" role="dialog" aria-modal="true" aria-labelledby="pim-release-notes-title"><div class="m-release-notes-head"><div><small>Coursefinder Admin</small><h2 id="pim-release-notes-title">Release notes</h2></div><button type="button" class="m-release-notes-close" aria-label="Close release notes">×</button></div><div class="m-release-notes-list">${RELEASES.map(release=>`<article class="m-release-note" data-release-version="${release.version}"><div class="m-release-note-meta"><span class="m-release-note-version">v${release.version}</span><span class="m-release-note-date">${release.date}</span></div><h3>${release.title}</h3><ul>${release.changes.map(change=>`<li>${change}</li>`).join('')}</ul></article>`).join('')}</div></section>`
  backdrop.addEventListener('click',event=>{if(event.target===backdrop)closeReleaseNotes()})
  backdrop.querySelector('.m-release-notes-close').addEventListener('click',closeReleaseNotes)
  document.body.appendChild(backdrop)
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&backdrop.classList.contains('is-open'))closeReleaseNotes()})
}

function openReleaseNotes(){
  ensureReleaseUi()
  const backdrop=document.getElementById('pim-release-notes')
  backdrop?.classList.add('is-open')
  backdrop?.querySelector('.m-release-notes-close')?.focus()
}

function closeReleaseNotes(){
  const backdrop=document.getElementById('pim-release-notes')
  backdrop?.classList.remove('is-open')
  document.querySelector('.m-release-pill[role="button"]')?.focus()
}

function sync(){
  document.querySelectorAll('.m-brand-copy small').forEach(el=>{if(el.textContent!==`PIM Admin v${VERSION}`)el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-login-version').forEach(el=>{if(el.textContent!==`PIM Admin v${VERSION}`)el.textContent=`PIM Admin v${VERSION}`})
  document.querySelectorAll('.m-release-pill').forEach(el=>{if(el.textContent!==`v${VERSION}`)el.textContent=`v${VERSION}`;releaseButton(el)})
  attempts+=1
  if(attempts<20)setTimeout(sync,150)
}
if(document.readyState==='loading')addEventListener('DOMContentLoaded',sync,{once:true});else sync()
